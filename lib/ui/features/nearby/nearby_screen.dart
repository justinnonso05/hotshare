import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/network_constants.dart';
import '../../../core/engine/engine_api.dart';
import '../../../core/net/gateway_finder.dart';
import '../../../core/net/lan_discovery_service.dart';
import '../../../core/net/subnet_scanner.dart';
import '../../../core/storage/storage_resolver.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/settings/app_settings.dart';
import '../../../state/engine_provider.dart';
import '../../../state/transfer_queue_provider.dart';
import '../../../ui/design_system/design_system.dart';
import '../devices/pairing_dialogs.dart';
import 'connection_guide_modal.dart';
import 'radar_stage.dart';
import 'widgets/transfer_queue_card.dart';

/// Main "Nearby" screen — handles P2P discovery/server lifecycle, radar, and transfers.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  Timer? _gatewayProbeTimer;
  StreamSubscription? _discoverySub;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNetworking();
    });
  }

  void _initNetworking() {
    final engine = ref.read(engineProvider);
    final settings = ref.read(settingsProvider);

    final deviceName = settings.deviceName.isNotEmpty
        ? settings.deviceName
        : (Platform.isWindows ? 'Windows PC' : 'Android Phone');
    engine.setLocalDeviceName(deviceName);
    engine.setPauseReceiving(settings.pauseReceiving);
    engine.setAutoAccept(settings.autoAcceptTrusted);
    engine.send(SetAutoReconnectCommand(settings.autoReconnect));

    // Both platforms start listening as WebSocket servers on kPort
    engine.send(const StartServerCommand(port: kPort));

    // Start UDP broadcast discovery
    final myId = engine.identity?.deviceId ?? '';
    LanDiscoveryService.instance.start(
      deviceId: myId,
      deviceName: deviceName,
      serverPort: kPort,
    );

    // Listen for discovered peers
    _discoverySub?.cancel();
    _discoverySub = LanDiscoveryService.instance.peerDiscovered.listen((peer) {
      final conn = ref.read(peerConnectionProvider);
      final currentEngine = ref.read(engineProvider);
      if (!conn.isConnected && !currentEngine.isConnected) {
        final currentMyId = currentEngine.identity?.deviceId ?? '';
        // Deterministic initiator election: device with higher ID connects
        if (currentMyId.compareTo(peer.deviceId) > 0) {
          currentEngine.send(ConnectCommand(host: peer.host, port: peer.port));
        }
      }
    });

    // Active subnet sweep & gateway fallback: guarantees connection even across
    // 3rd-party mobile hotspots ("Coldspot 2.0") and routers that filter UDP broadcast.
    _runSubnetScan();
    _gatewayProbeTimer?.cancel();
    _gatewayProbeTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final conn = ref.read(peerConnectionProvider);
      final currentEngine = ref.read(engineProvider);
      if (!conn.isConnected && !currentEngine.isConnected && mounted) {
        _runSubnetScan();
      }
    });
  }

  Future<void> _runSubnetScan() async {
    final conn = ref.read(peerConnectionProvider);
    final engine = ref.read(engineProvider);
    if (conn.isConnected || engine.isConnected || !mounted) return;

    if (Platform.isWindows) {
      final gateways = await findWindowsGateways();
      if (gateways.isNotEmpty && mounted) {
        final host = gateways.first;
        engine.send(ConnectCommand(host: host, port: kPort));
      }
    }

    await SubnetScanner.scan(
      port: kPort,
      onFound: (host) {
        if (!mounted) return;
        final currentConn = ref.read(peerConnectionProvider);
        final currentEngine = ref.read(engineProvider);
        if (!currentConn.isConnected && !currentEngine.isConnected) {
          currentEngine.send(ConnectCommand(host: host, port: kPort));
        }
      },
    );
  }

  void _rescanPeers() {
    final settings = ref.read(settingsProvider);
    final engine = ref.read(engineProvider);
    final deviceName = settings.deviceName.isNotEmpty
        ? settings.deviceName
        : (Platform.isWindows ? 'Windows PC' : 'Android Phone');
    final myId = engine.identity?.deviceId ?? '';

    LanDiscoveryService.instance.updateIdentity(
      deviceId: myId,
      deviceName: deviceName,
    );
    LanDiscoveryService.instance.rescan();
    _runSubnetScan();

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scanning local network for HotShare devices...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _gatewayProbeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for settings changes to immediately synchronize with engine & discovery
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      final engine = ref.read(engineProvider);
      if (prev?.deviceName != next.deviceName && next.deviceName.isNotEmpty) {
        engine.setLocalDeviceName(next.deviceName);
        LanDiscoveryService.instance.updateIdentity(deviceName: next.deviceName);
      }
      if (prev?.pauseReceiving != next.pauseReceiving) {
        engine.setPauseReceiving(next.pauseReceiving);
      }
      if (prev?.autoAcceptTrusted != next.autoAcceptTrusted) {
        engine.setAutoAccept(next.autoAcceptTrusted);
      }
      if (prev?.autoReconnect != next.autoReconnect) {
        engine.send(SetAutoReconnectCommand(next.autoReconnect));
      }
    });

    // Listen for incoming transfer offers when Auto-Accept is disabled
    ref.listen<AsyncValue<EngineEvent>>(engineEventsStreamProvider, (_, asyncEvent) {
      final event = asyncEvent.value;
      if (event is IncomingTransferOfferEvent && mounted) {
        showIncomingTransferOfferDialog(context, ref, event);
      }
      if (event is PairingCompletedEvent && event.success && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paired with ${event.peerName} successfully!'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

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
                                    : 'Searching for nearby devices…',
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
                  IconButton(
                    tooltip: 'How to Connect',
                    icon: const Icon(Icons.help_outline_rounded, color: HsColors.glowHot),
                    onPressed: () => ConnectionGuideModal.show(context),
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

            if (!conn.isConnected) ...[
              const SizedBox(height: 14),
              Center(
                child: GestureDetector(
                  onTap: _rescanPeers,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: HsColors.glassFillStrong,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: HsColors.glassStroke),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 16, color: HsColors.glowHot),
                        const SizedBox(width: 8),
                        Text(
                          "Can't find device? Tap to scan",
                          style: HsText.caption.copyWith(color: HsColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Transfer Status & Queue Feedback ─────────────────────────────
            Builder(
              builder: (context) {
                final queue = ref.watch(transferQueueProvider);
                return AnimatedSwitcher(
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
                  child: queue.items.isNotEmpty
                      ? Padding(
                          key: const ValueKey('batch_transfer_queue'),
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: TransferQueueCard(queue: queue),
                        )
                      : (active.isActive
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
                              : const SizedBox.shrink(key: ValueKey('empty_transfer')))),
                );
              },
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
                      label: 'Searching for nearby devices… (Tap to scan)',
                      icon: Icons.search_rounded,
                      variant: GlassButtonVariant.secondary,
                      width: double.infinity,
                      onPressed: _rescanPeers,
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
        onDragDone: (details) async {
          setState(() => _dragging = false);
          if (!conn.isConnected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please connect to the device before sending files.')),
            );
            return;
          }
          if (!conn.isPaired) {
            showPairingRequiredPrompt(context, ref, conn.peerName);
            return;
          }
          final paths = details.files.map((f) => f.path).toList();
          if (paths.isNotEmpty) {
            await ref.read(transferQueueProvider.notifier).enqueueOutgoingFiles(paths);
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SendOptionsSheet(
        onPickFiles: () async {
          Navigator.pop(ctx);
          final result = await FilePicker.pickFiles();
          if (result.isEmpty) return;
          final paths =
              result.where((f) => f.path != null).map((f) => f.path!).toList();
          if (paths.isEmpty) return;
          await ref.read(transferQueueProvider.notifier).enqueueOutgoingFiles(paths);
          ref.read(engineProvider).send(SendFilesCommand(paths));
        },
        onPickFolder: () async {
          Navigator.pop(ctx);
          final folderPath = await FilePicker.getDirectoryPath();
          if (folderPath == null || folderPath.isEmpty) return;
          await ref
              .read(transferQueueProvider.notifier)
              .enqueueOutgoingFiles([folderPath]);
          ref.read(engineProvider).send(SendFilesCommand([folderPath]));
        },
      ),
    );
  }
}

class _SendOptionsSheet extends StatelessWidget {
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;

  const _SendOptionsSheet({
    required this.onPickFiles,
    required this.onPickFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 16,
        right: 16,
      ),
      child: GlassSurface(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: HsColors.glassStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share Content',
              style: HsText.title.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose whether to send individual files or an entire folder',
              style: HsText.caption,
            ),
            const SizedBox(height: 18),
            _OptionTile(
              icon: Icons.file_present_rounded,
              title: 'Send Files',
              subtitle: 'Pick one or multiple files to transfer',
              onTap: onPickFiles,
            ),
            const SizedBox(height: 10),
            _OptionTile(
              icon: Icons.folder_rounded,
              title: 'Send Folder',
              subtitle: 'Preserves the entire folder and its subdirectories',
              onTap: onPickFolder,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: HsColors.glassFillStrong,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HsColors.glassStroke),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: HsColors.emberGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: HsText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: HsText.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: HsColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
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
