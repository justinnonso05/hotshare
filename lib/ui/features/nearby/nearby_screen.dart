import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/network_constants.dart';
import '../../../core/engine/engine_api.dart';
import '../../../core/net/gateway_finder.dart';
import '../../../core/storage/storage_resolver.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/settings/app_settings.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';
import 'radar_stage.dart';

/// Main "Nearby" screen — handles P2P discovery/server lifecycle, radar, and transfers.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  final _ipController = TextEditingController();
  Timer? _discoveryTimer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final engine = ref.read(engineProvider);
      if (Platform.isAndroid) {
        // Android Phone starts the P2P Hotspot WebSocket server
        engine.send(const StartServerCommand(port: kPort));
      } else if (Platform.isWindows) {
        // Windows PC auto-discovers the phone's gateway IP and connects
        _autoConnectWindows();
        _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          final conn = ref.read(peerConnectionProvider);
          if (!conn.isConnected && mounted) {
            _autoConnectWindows();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _autoConnectWindows() async {
    final gateways = await findWindowsGateways();
    if (gateways.isNotEmpty && mounted) {
      if (_ipController.text.isEmpty) {
        _ipController.text = gateways.first;
      }
      final host = _ipController.text.trim();
      ref.read(engineProvider).send(ConnectCommand(host: host, port: kPort));
    }
  }

  void _manualConnect(String host) {
    if (host.trim().isEmpty) return;
    _ipController.text = host.trim();
    ref.read(engineProvider).send(ConnectCommand(host: host.trim(), port: kPort));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(peerConnectionProvider);
    final active = ref.watch(activeTransferProvider);
    final history = ref.watch(transferHistoryStreamProvider);

    final deviceName = settings.deviceName.isEmpty
        ? (Platform.isWindows ? 'My PC' : 'My Phone')
        : settings.deviceName;

    Widget content = SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello,', style: HsText.body),
                        Text(
                          deviceName,
                          style: HsText.display,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            StatusDot(
                              state: conn.isConnected
                                  ? StatusDotState.online
                                  : StatusDotState.reconnecting,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                conn.isConnected
                                    ? 'Connected to ${conn.peerName}'
                                    : (Platform.isAndroid
                                        ? 'Hotspot server active (port $kPort)'
                                        : (_ipController.text.isNotEmpty
                                            ? 'Connecting to ${_ipController.text}…'
                                            : 'Searching for phone hotspot…')),
                                style: HsText.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (Platform.isWindows && !conn.isConnected)
                    IconButton(
                      tooltip: 'Change Target IP',
                      icon: const Icon(Icons.settings_ethernet_rounded, color: HsColors.glowHot),
                      onPressed: _showIpDialog,
                    ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon/icon_rounded_512.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Radar stage ──────────────────────────────────────────────────
            Center(
              child: RadarStage(
                reduceMotion: settings.reduceMotion,
                devices: conn.isConnected
                    ? [
                        DeviceBubble(
                          name: conn.peerName,
                          platform: conn.peerName.toLowerCase().contains('pc') ||
                                  conn.peerName.toLowerCase().contains('win')
                              ? 'windows'
                              : 'android',
                          isConnected: true,
                          isTransferring: active.isActive,
                          transferProgress: active.progress,
                          transferFileName: active.name,
                          speedBytesPerSec: active.speedBytesPerSec,
                          onTap: () => _pickAndSend(),
                        ),
                      ]
                    : [],
              ),
            ),

            const SizedBox(height: 32),

            // ── Active transfer card ──────────────────────────────────────────
            if (active.isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _ActiveTransferCard(state: active),
              ),

            // ── Send / Choose files button / Drop Zone ───────────────────────
            if (!active.isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: conn.isConnected
                    ? GlassButton(
                        label: Platform.isWindows
                            ? (_dragging ? 'Drop files here!' : 'Choose or drop files to send')
                            : 'Send files',
                        icon: Icons.upload_rounded,
                        width: double.infinity,
                        onPressed: _pickAndSend,
                      )
                    : GlassButton(
                        label: Platform.isAndroid
                            ? 'Waiting for PC to connect…'
                            : 'Searching for phone hotspot…',
                        variant: GlassButtonVariant.secondary,
                        width: double.infinity,
                        onPressed: Platform.isWindows ? _showIpDialog : null,
                      ),
              ),

            const SizedBox(height: 32),

            // ── Recent transfers card ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _RecentCard(historyAsync: history),
            ),
          ],
        ),
      ),
    );

    if (Platform.isWindows) {
      return DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          final paths = details.files.map((f) => f.path).toList();
          if (paths.isNotEmpty && conn.isConnected) {
            ref.read(engineProvider).send(SendFilesCommand(paths));
          } else if (!conn.isConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please connect to the phone before sending files.')),
            );
          }
        },
        child: content,
      );
    }

    return content;
  }

  Future<void> _pickAndSend() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    final paths = result.where((f) => f.path != null).map((f) => f.path!).toList();
    if (paths.isEmpty) return;
    ref.read(engineProvider).send(SendFilesCommand(paths));
  }

  void _showIpDialog() {
    final ctrl = TextEditingController(text: _ipController.text);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Phone Hotspot IP', style: HsText.headline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your phone\'s hotspot gateway IP address (typically 192.168.43.1):',
                style: HsText.body,
              ),
              const SizedBox(height: 16),
              GlassTextField(
                controller: ctrl,
                hint: '192.168.43.1',
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: HsColors.textTertiary)),
            ),
            GlassButton(
              label: 'Connect',
              height: 40,
              fontSize: 14,
              onPressed: () {
                Navigator.pop(ctx);
                _manualConnect(ctrl.text);
              },
            ),
          ],
        );
      },
    );
  }
}

// ── Active Transfer Card ──────────────────────────────────────────────────────

class _ActiveTransferCard extends ConsumerWidget {
  final ActiveTransferState state;

  const _ActiveTransferCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = state.name.contains('.') ? state.name.split('.').last : 'file';
    final kind = StorageResolver.classifyFileKind(state.name);

    return GlassSurface(
      child: Row(
        children: [
          FileGlyph(kind: kind, ext: ext, size: 44),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.name,
                  style: HsText.title.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatBytes(state.bytesDone)} / ${formatBytes(state.totalBytes)}'
                  '  •  ${formatBytes(state.speedBytesPerSec.round())}/s',
                  style: HsText.caption,
                ),
                const SizedBox(height: 10),
                TransferRing(
                  progress: state.progress,
                  size: 28,
                  strokeWidth: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Text(
                '${(state.progress * 100).toStringAsFixed(0)}%',
                style: HsText.headline.copyWith(
                  fontSize: 20,
                  color: HsColors.glowHot,
                ),
              ),
              Text(
                state.isSending ? 'Sending' : 'Receiving',
                style: HsText.micro,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => ref.read(engineProvider).send(CancelTransferCommand(state.id)),
                child: const Icon(Icons.cancel_outlined, size: 18, color: HsColors.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Recent Card ───────────────────────────────────────────────────────────────

class _RecentCard extends StatelessWidget {
  final AsyncValue<List<dynamic>> historyAsync;

  const _RecentCard({required this.historyAsync});

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (history) {
        if (history.isEmpty) return const SizedBox.shrink();
        final recent = history.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Floating file glyphs above card
            SizedBox(
              height: 64,
              child: Stack(
                children: [
                  for (int i = 0; i < math.min(recent.length, 3); i++)
                    Positioned(
                      left: 24.0 + i * 44,
                      top: i.isEven ? 4 : 16,
                      child: _BobbingGlyph(
                        delay: i * 0.35,
                        child: FileGlyph(
                          kind: (recent[i] as dynamic).kind as String,
                          ext: _extFromName((recent[i] as dynamic).name as String),
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent', style: HsText.headline),
                  const SizedBox(height: 12),
                  for (final item in recent) _HistoryRow(transfer: item),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _extFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '?';
    return name.substring(dot + 1);
  }
}

class _HistoryRow extends StatelessWidget {
  final dynamic transfer;

  const _HistoryRow({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final name = transfer.name as String;
    final size = transfer.size as int;
    final direction = transfer.direction as String;
    final status = transfer.status as String;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            direction == 'out' ? Icons.upload_rounded : Icons.download_rounded,
            size: 16,
            color: direction == 'out' ? HsColors.glowHot : HsColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: HsText.body.copyWith(
                    color: HsColors.textPrimary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formatBytes(size),
                  style: HsText.caption,
                ),
              ],
            ),
          ),
          _StatusChip(status: status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'done':
        color = HsColors.success;
        label = 'Done';
      case 'failed':
        color = HsColors.danger;
        label = 'Failed';
      case 'transferring':
        color = HsColors.warning;
        label = 'Active';
      default:
        color = HsColors.textTertiary;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(HsColors.radiusPill),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(label,
          style: HsText.micro.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )),
    );
  }
}

class _BobbingGlyph extends StatefulWidget {
  final Widget child;
  final double delay;

  const _BobbingGlyph({required this.child, this.delay = 0});

  @override
  State<_BobbingGlyph> createState() => _BobbingGlyphState();
}

class _BobbingGlyphState extends State<_BobbingGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _offset = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _offset.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
