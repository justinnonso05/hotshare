import 'dart:async';
import 'dart:io';

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
import '../devices/pairing_dialogs.dart';
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
        _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
      if (_ipController.text.isEmpty || !gateways.contains(_ipController.text.trim())) {
        _ipController.text = gateways.first;
      }
      final host = _ipController.text.trim();
      final conn = ref.read(peerConnectionProvider);
      if (!conn.isConnected) {
        ref.read(engineProvider).send(ConnectCommand(host: host, port: kPort));
      }
    }
  }

  void _manualConnect(String host) {
    if (host.trim().isEmpty) return;
    _ipController.text = host.trim();
    ref.read(engineProvider).send(ConnectCommand(host: host.trim(), port: kPort));
  }

  @override
  Widget build(BuildContext context) {
    // Listen for SAS verification events so security prompts pop up smoothly on this screen
    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords != null && prev?.sasWords != next.sasWords) {
        showSasVerificationDialog(
          context,
          ref,
          next.sasWords!,
          next.peerName ?? 'Device',
        );
      }
    });

    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(peerConnectionProvider);
    final active = ref.watch(activeTransferProvider);
    final lastTransfer = ref.watch(lastCompletedTransferProvider);

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
                                    ? (conn.isPaired
                                        ? 'Connected to ${conn.peerName}'
                                        : 'Connected to ${conn.peerName} • Pairing required')
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
                ],
              ),
            ),

            // ── Proactive Pairing Card (When connected but not yet paired) ───
            if (conn.isConnected && !conn.isPaired)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: GlassSurface(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: HsColors.glowMid.withAlpha(40),
                              border: Border.all(color: HsColors.glowMid.withAlpha(80)),
                            ),
                            child: const Icon(Icons.shield_outlined, color: HsColors.glowHot, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pairing Required to Transfer',
                                  style: HsText.title.copyWith(fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pair with ${conn.peerName} using a 6-digit PIN to enable instant secure transfers.',
                                  style: HsText.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              label: 'Show PIN',
                              icon: Icons.key_rounded,
                              height: 42,
                              fontSize: 13,
                              variant: GlassButtonVariant.secondary,
                              onPressed: () => showPairingSheet(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GlassButton(
                              label: 'Enter PIN',
                              icon: Icons.dialpad_rounded,
                              height: 42,
                              fontSize: 13,
                              variant: GlassButtonVariant.primary,
                              onPressed: () => showEnterPinDialog(context, ref),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // ── Radar stage ──────────────────────────────────────────────────
            Center(
              child: RadarStage(
                reduceMotion: settings.reduceMotion,
                isTransferring: active.isActive,
                transferProgress: active.progress,
                isSending: active.isSending,
                speedBytesPerSec: active.speedBytesPerSec,
                localDeviceName: deviceName,
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

            const SizedBox(height: 24),

            // ── Transfer Status & Transitions (Active & Completed Feedback) ───
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    child: child,
                  ),
                );
              },
              child: active.isActive
                  ? Padding(
                      key: ValueKey('active_${active.id}'),
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: _ActiveTransferCard(state: active),
                    )
                  : (lastTransfer != null
                      ? Padding(
                          key: ValueKey('completed_${lastTransfer.id}_${lastTransfer.success}'),
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: _CompletedTransferCard(
                            summary: lastTransfer,
                            onDismiss: () => ref.read(lastCompletedTransferProvider.notifier).clear(),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty_transfer'))),
            ),

            // ── Send / Choose files button / Drop Zone ───────────────────────
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
          if (!conn.isConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please connect to the phone before sending files.')),
            );
            return;
          }
          if (!conn.isPaired) {
            showPairingRequiredPrompt(context, ref, conn.peerName);
            return;
          }
          final paths = details.files.map((f) => f.path).toList();
          if (paths.isNotEmpty) {
            ref.read(engineProvider).send(SendFilesCommand(paths));
          }
        },
        child: content,
      );
    }

    return content;
  }

  Future<void> _pickAndSend() async {
    final conn = ref.read(peerConnectionProvider);
    if (!conn.isConnected) return;
    if (!conn.isPaired) {
      showPairingRequiredPrompt(context, ref, conn.peerName);
      return;
    }
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
          backgroundColor: HsColors.bgRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: HsColors.glassStroke),
          ),
          title: Text('Phone Hotspot IP', style: HsText.headline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your phone\'s hotspot gateway IP address (typically 192.168.43.1):',
                style: HsText.body.copyWith(color: HsColors.textSecondary),
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
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    variant: GlassButtonVariant.ghost,
                    height: 42,
                    fontSize: 14,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Connect',
                    variant: GlassButtonVariant.primary,
                    height: 42,
                    fontSize: 14,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _manualConnect(ctrl.text);
                    },
                  ),
                ),
              ],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FileGlyph(kind: kind, ext: ext, size: 40),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(state.bytesDone)} of ${formatBytes(state.totalBytes)}'
                      '  •  ${formatBytes(state.speedBytesPerSec.round())}/s',
                      style: HsText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(state.progress * 100).toInt()}%',
                        style: HsText.headline.copyWith(
                          fontSize: 18,
                          color: HsColors.glowHot,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => ref.read(engineProvider).send(CancelTransferCommand(state.id)),
                        child: const Icon(Icons.cancel_outlined, size: 18, color: HsColors.danger),
                      ),
                    ],
                  ),
                  Text(
                    state.isSending ? 'Sending…' : 'Receiving…',
                    style: HsText.micro.copyWith(color: HsColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: HsColors.glassFillStrong,
              valueColor: const AlwaysStoppedAnimation<Color>(HsColors.accentPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Completed Transfer Card ───────────────────────────────────────────────────

class _CompletedTransferCard extends StatelessWidget {
  final LastTransferSummary summary;
  final VoidCallback onDismiss;

  const _CompletedTransferCard({
    required this.summary,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = summary.success;

    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: Border.all(
        color: (isSuccess ? HsColors.success : HsColors.danger).withAlpha(140),
        width: 1,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isSuccess ? HsColors.success : HsColors.danger).withAlpha(35),
              border: Border.all(
                color: (isSuccess ? HsColors.success : HsColors.danger).withAlpha(90),
              ),
            ),
            child: Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: isSuccess ? HsColors.success : HsColors.danger,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isSuccess
                          ? (summary.isSending ? 'File Sent Successfully' : 'File Received Successfully')
                          : (summary.isSending ? 'Failed to Send File' : 'Transfer Failed'),
                      style: HsText.title.copyWith(
                        fontSize: 14,
                        color: isSuccess ? HsColors.success : HsColors.danger,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSuccess ? HsColors.success : HsColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary.name,
                  style: HsText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isSuccess
                      ? '${formatBytes(summary.size)}  •  ${summary.isSending ? 'Delivered & SHA-256 Verified' : (Platform.isAndroid ? 'Saved to Download/HotShare' : 'Saved to Downloads\\HotShare')}'
                      : (summary.error ?? 'Connection error'),
                  style: HsText.caption.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close_rounded, size: 18, color: HsColors.textTertiary),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
