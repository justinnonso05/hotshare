import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/engine_api.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/db/app_database.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';
import 'pairing_dialogs.dart';

/// Devices screen: lists paired trusted devices and handles pairing handshakes.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for SAS verification events globally on this screen
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

    final pairedDevicesAsync = ref.watch(pairedDevicesStreamProvider);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Devices',
                        style: HsText.display,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Enter PIN Code',
                        onPressed: () => showEnterPinDialog(context, ref),
                        icon: const Icon(
                          Icons.dialpad_rounded,
                          color: HsColors.textPrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GlassButton(
                        label: 'Pair Device',
                        icon: Icons.shield_outlined,
                        height: 40,
                        fontSize: 13,
                        onPressed: () => showPairingSheet(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Instructions Card ─────────────────────────────────────────────
            GlassSurface(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HsColors.glowMid.withAlpha(40),
                      border: Border.all(color: HsColors.glowMid.withAlpha(80)),
                    ),
                    child: const Icon(Icons.shield_outlined, color: HsColors.glowHot, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Direct Device Trust', style: HsText.title.copyWith(fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'Transfers are direct and encrypted.',
                          style: HsText.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Paired Devices Section ────────────────────────────────────────
            Text('Trusted Devices', style: HsText.title),
            const SizedBox(height: 12),

            pairedDevicesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                    color: HsColors.accentPrimary,
                    strokeWidth: 2,
                  ),
                ),
              ),
              error: (err, _) => GlassSurface(
                child: Text('Error loading devices: $err', style: HsText.caption),
              ),
              data: (devices) {
                if (devices.isEmpty) {
                  return const _EmptyDevicesCard();
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final device = devices[index];
                    return _DeviceCard(
                      device: device,
                      onRevoke: () => _confirmRevoke(context, ref, device),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRevoke(BuildContext context, WidgetRef ref, Device device) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: GlassSurface(
            padding: const EdgeInsets.all(22),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Forget Device?', style: HsText.headline),
                const SizedBox(height: 12),
                Text(
                  'Remove "${device.name}" from your trusted list? You will need to pair again to transfer files.',
                  style: HsText.body.copyWith(color: HsColors.textSecondary),
                ),
                const SizedBox(height: 22),
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
                        label: 'Forget',
                        variant: GlassButtonVariant.danger,
                        height: 42,
                        fontSize: 14,
                        onPressed: () {
                          ref.read(engineProvider).send(RevokeDeviceCommand(device.id));
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  final Device device;
  final VoidCallback onRevoke;

  const _DeviceCard({required this.device, required this.onRevoke});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(peerConnectionProvider);
    final isWin = device.platform.toLowerCase().contains('win');

    final isConnectedToThis = conn.isConnected &&
        (conn.peerName == device.name ||
         (isWin && conn.peerName.toLowerCase().contains('pc')) ||
         (!isWin && (conn.peerName.toLowerCase().contains('phone') ||
                     conn.peerName.toLowerCase().contains('xiaomi') ||
                     conn.peerName.toLowerCase().contains('pixel') ||
                     conn.peerName.toLowerCase().contains('redmi') ||
                     conn.peerName.toLowerCase().contains('samsung'))));

    final displayName = (isConnectedToThis && conn.peerName.isNotEmpty)
        ? conn.peerName
        : (device.name.isNotEmpty && device.name != 'Android Phone' && device.name != 'Windows PC'
            ? device.name
            : (conn.isConnected && conn.peerName.isNotEmpty
                ? conn.peerName
                : (device.name.isNotEmpty ? device.name : (isWin ? 'Windows PC' : 'Android Phone'))));

    final timeStr = isConnectedToThis
        ? 'Connected • just now'
        : (device.lastSeenAt != null
            ? 'Seen ${formatTimeAgo(device.lastSeenAt!)}'
            : 'Paired ${formatTimeAgo(device.pairedAt)}');

    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HsColors.glassFillStrong,
              border: Border.all(color: HsColors.glassStroke),
            ),
            child: Icon(
              isWin ? Icons.laptop_windows_rounded : Icons.phone_android_rounded,
              color: HsColors.textPrimary,
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
                    Flexible(
                      child: Text(
                        displayName,
                        style: HsText.title.copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isConnectedToThis) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: HsColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$timeStr  •  ID: ${device.id.substring(0, 8)}…',
                  style: HsText.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Forget Device',
            icon: const Icon(Icons.delete_outline_rounded, color: HsColors.textTertiary, size: 20),
            onPressed: onRevoke,
          ),
        ],
      ),
    );
  }
}

class _EmptyDevicesCard extends StatelessWidget {
  const _EmptyDevicesCard();

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HsColors.glassFillStrong,
                border: Border.all(color: HsColors.glassStroke),
              ),
              child: const Icon(Icons.devices_other_rounded, color: HsColors.textTertiary, size: 28),
            ),
            const SizedBox(height: 16),
            Text('No Trusted Devices Yet', style: HsText.title.copyWith(fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              'Pair your Android phone and Windows PC once using a 6-digit PIN. Once paired, you can instantly transfer files.',
              style: HsText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
