import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/constants/network_constants.dart';
import '../../core/engine/engine_api.dart';
import '../../core/net/gateway_finder.dart';
import '../../core/utils/formatters.dart';
import '../../state/engine_provider.dart';

class SharePage extends ConsumerStatefulWidget {
  const SharePage({super.key});

  @override
  ConsumerState<SharePage> createState() => _SharePageState();
}

class _SharePageState extends ConsumerState<SharePage> {
  final _ipController = TextEditingController();
  final _msgController = TextEditingController(text: 'Hello from here');
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
    final receivedFiles = ref.watch(completedTransfersProvider);
    final logs = ref.watch(engineLogsProvider);

    final connected = peer.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isPhone ? 'Phone (server)' : 'PC (client)'),
        actions: [
          if (connected)
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
              Icon(Icons.circle,
                  size: 14, color: connected ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Text(connected
                  ? 'Connected to ${peer.peerName}'
                  : 'Not connected'),
              const Spacer(),
              if (connected)
                TextButton.icon(
                  onPressed: active.isActive ? null : _runBenchmark,
                  icon: const Icon(Icons.speed, size: 16),
                  label: const Text('Test Speed (100 MB)'),
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
            _dropZone(connected),
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
            for (final f in receivedFiles.take(3))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.path ?? '', overflow: TextOverflow.ellipsis),
                trailing: Text(formatBytes(f.size)),
                onTap: f.path != null ? () => OpenFilex.open(f.path!) : null,
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
                onPressed: connected ? _sendText : null,
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
