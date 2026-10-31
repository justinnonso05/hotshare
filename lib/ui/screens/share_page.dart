import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/constants/network_constants.dart';
import '../../core/engine/engine_api.dart';
import '../../core/net/gateway_finder.dart';
import '../../core/storage/storage_resolver.dart';
import '../../core/utils/formatters.dart';
import '../../data/settings/app_settings.dart';
import '../../state/engine_provider.dart';

class SharePage extends ConsumerStatefulWidget {
  const SharePage({super.key});

  @override
  ConsumerState<SharePage> createState() => _SharePageState();
}

class _SharePageState extends ConsumerState<SharePage> {
  final _ipController = TextEditingController();
  final _msgController = TextEditingController(text: 'Hello from here');
  final _codeController = TextEditingController();
  bool _dragging = false;

  bool get _isPhone => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = ref.read(engineProvider);
      if (_isPhone) {
        engine.send(const StartServerCommand(port: kPort));
      } else {
        _findGateway();
      }
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _msgController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _findGateway() async {
    final gateways = await findWindowsGateways();
    if (gateways.isNotEmpty && mounted) {
      _ipController.text = gateways.first;
    }
  }

  void _connect() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    ref.read(engineProvider).send(ConnectCommand(host: ip, port: kPort));
  }

  Future<void> _pickAndSend() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isNotEmpty) {
      ref.read(engineProvider).send(SendFilesCommand(paths));
    }
  }

  void _sendText() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    ref.read(engineProvider).send(SendTextCommand(text));
  }

  void _runBenchmark() {
    ref.read(engineProvider).send(const RunBenchmarkCommand(sizeMb: 100));
  }

  void _openPairingWindow() {
    ref.read(engineProvider).send(const OpenPairingWindowCommand());
    _showPairingCodeSheet();
  }

  void _showPairingCodeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final pairing = ref.watch(pairingUiStateProvider);
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pair New Device',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Enter this 6-digit code on the other device:'),
                  const SizedBox(height: 16),
                  Text(
                    pairing.code ?? 'Generating...',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      fontFamily: 'monospace',
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pairing.qrPayload != null)
                    SizedBox(
                      height: 140,
                      width: 140,
                      child: QrImageView(
                        data: pairing.qrPayload!,
                        version: QrVersions.auto,
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Code expires in 60 seconds',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEnterCodeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Enter 6-Digit Pairing Code'),
          content: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 6,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              hintText: '123456',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final code = _codeController.text.trim();
                if (code.length == 6) {
                  ref.read(engineProvider).send(SubmitPairingCodeCommand(code));
                  Navigator.pop(ctx);
                  _codeController.clear();
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  void _showSasVerificationDialog(List<String> words, String peerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Verify Device Match'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Do these 4 words match on $peerName?'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in words)
                    Chip(
                      label: Text(
                        w.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.indigo.withValues(alpha: 0.15),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(engineProvider).send(const ConfirmPairingCommand(false));
                Navigator.pop(ctx);
              },
              child: const Text('No, Reject'),
            ),
            FilledButton(
              onPressed: () {
                ref.read(engineProvider).send(const ConfirmPairingCommand(true));
                Navigator.pop(ctx);
              },
              child: const Text('Yes, Match!'),
            ),
          ],
        );
      },
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            return AlertDialog(
              title: const Text('HotShare Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Accept Files'),
                      subtitle: const Text('Accept from paired devices automatically'),
                      value: settings.autoAcceptTrusted,
                      onChanged: (val) {
                        ref.read(settingsProvider.notifier).update(
                              (s) => s.copyWith(autoAcceptTrusted: val),
                            );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Reconnect'),
                      subtitle: const Text('Reconnect silently on local link'),
                      value: settings.autoReconnect,
                      onChanged: (val) {
                        ref.read(settingsProvider.notifier).update(
                              (s) => s.copyWith(autoReconnect: val),
                            );
                        ref.read(engineProvider).send(SetAutoReconnectCommand(val));
                      },
                    ),
                    if (_isPhone)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Storage Mode'),
                        subtitle: Text(
                          settings.androidSaveMode == 'byType'
                              ? 'Organize by Type (Pictures, Movies, Downloads)'
                              : 'All in Downloads folder',
                        ),
                        trailing: DropdownButton<String>(
                          value: settings.androidSaveMode,
                          items: const [
                            DropdownMenuItem(value: 'byType', child: Text('By Type')),
                            DropdownMenuItem(value: 'downloads', child: Text('Downloads')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(settingsProvider.notifier).update(
                                    (s) => s.copyWith(androidSaveMode: val),
                                  );
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getIconForKind(String kind) {
    switch (kind) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.video_file;
      case 'audio':
        return Icons.audio_file;
      case 'document':
        return Icons.description;
      case 'archive':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _dropZone(bool connected) {
    final zone = InkWell(
      onTap: connected ? _pickAndSend : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _dragging ? Colors.indigo : Colors.grey,
            width: _dragging ? 3 : 1.5,
          ),
          color: _dragging ? Colors.indigo.withValues(alpha: 0.08) : null,
        ),
        child: Text(
          connected
              ? (_isPhone
                  ? 'Tap to choose files to send'
                  : 'Drop files here, or click to choose')
              : 'Connect first',
        ),
      ),
    );

    if (_isPhone) return zone;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        final paths = d.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) {
          ref.read(engineProvider).send(SendFilesCommand(paths));
        }
      },
      child: zone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final peer = ref.watch(peerConnectionProvider);
    final active = ref.watch(activeTransferProvider);
    final historyAsync = ref.watch(transferHistoryStreamProvider);
    final logs = ref.watch(engineLogsProvider);
    final pairedDevicesAsync = ref.watch(pairedDevicesStreamProvider);

    final connected = peer.isConnected;
    final authenticated = peer.isAuthenticated;

    // Listen for verification dialog requirement
    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords != null && prev?.sasWords != next.sasWords) {
        _showSasVerificationDialog(next.sasWords!, next.peerName ?? 'peer');
      }
    });

    Color statusColor = Colors.red;
    String statusText = 'Not connected';

    if (connected) {
      if (authenticated) {
        statusColor = Colors.green;
        statusText = 'Connected to ${peer.peerName} (Paired)';
      } else {
        statusColor = Colors.amber;
        statusText = 'Connected to ${peer.peerName} (Unpaired)';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPhone ? 'Phone (server)' : 'PC (client)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
          ),
          if (connected && authenticated)
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Run 100 MB Network Benchmark',
              onPressed: active.isActive ? null : _runBenchmark,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.circle, size: 14, color: statusColor),
              const SizedBox(width: 8),
              Expanded(child: Text(statusText)),
              if (_isPhone)
                OutlinedButton.icon(
                  onPressed: _openPairingWindow,
                  icon: const Icon(Icons.qr_code, size: 16),
                  label: const Text('Pair Device'),
                )
              else if (connected && !authenticated)
                FilledButton.icon(
                  onPressed: _showEnterCodeDialog,
                  icon: const Icon(Icons.key, size: 16),
                  label: const Text('Enter Code'),
                ),
            ]),
            const SizedBox(height: 12),
            if (!_isPhone) ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Phone IP',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: connected ? null : _connect,
                  child: const Text('Connect'),
                ),
              ]),
              const SizedBox(height: 12),
            ],
            _dropZone(connected && authenticated),
            const SizedBox(height: 12),
            if (active.isActive) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${active.isSending ? 'Sending' : 'Receiving'} ${active.name} (${formatBytes(active.totalBytes)})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${(active.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: active.progress),
              const SizedBox(height: 8),
            ],
            // Paired devices chips
            pairedDevicesAsync.when(
              data: (devices) {
                if (devices.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Text('Paired: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final d in devices)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Chip(
                            avatar: Icon(
                              d.platform == 'android' ? Icons.phone_android : Icons.laptop,
                              size: 16,
                            ),
                            label: Text(d.name),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () => ref.read(engineProvider).send(RevokeDeviceCommand(d.id)),
                          ),
                        ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
            ),
            // Persistent Transfer History
            historyAsync.when(
              data: (transfers) {
                if (transfers.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Recent Transfers (Database)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    for (final t in transfers.take(3))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_getIconForKind(t.kind)),
                        title: Text(t.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${t.direction == 'in' ? 'Received' : 'Sent'} • ${formatBytes(t.size)} • ${t.status}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: (t.localPath != null && t.status == 'done')
                            ? IconButton(
                                icon: const Icon(Icons.folder_open, size: 20),
                                tooltip: 'Open / Show in Folder',
                                onPressed: () => StorageResolver.showInFileManager(t.localPath!),
                              )
                            : null,
                      ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (connected && authenticated) ? _sendText : null,
                child: const Text('Send'),
              ),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (_, i) => Text(
                  logs[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
