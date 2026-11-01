import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/engine/engine_api.dart';
import '../../../data/db/app_database.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';

/// Devices screen: lists paired trusted devices and handles pairing handshakes.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _listenPairingEvents() {
    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords != null && prev?.sasWords != next.sasWords) {
        _showSasVerificationDialog(next.sasWords!, next.peerName ?? 'Device');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenPairingEvents();
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
                children: [
                  Expanded(
                    child: Text('Devices', style: HsText.display),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Enter Code',
                        onPressed: _showEnterCodeDialog,
                        icon: const Icon(Icons.pin_rounded, color: HsColors.textPrimary),
                      ),
                      const SizedBox(width: 8),
                      GlassButton(
                        label: 'Pair Device',
                        icon: Icons.qr_code_rounded,
                        height: 42,
                        fontSize: 13,
                        onPressed: _openPairingSheet,
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
                        Text('Mutual Cryptographic Trust', style: HsText.title.copyWith(fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'Paired devices authenticate via Ed25519 signatures. Transfers are direct and encrypted.',
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
                      onRevoke: () => _confirmRevoke(device),
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

  void _openPairingSheet() {
    ref.read(engineProvider).send(const OpenPairingWindowCommand());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final pairing = ref.watch(pairingUiStateProvider);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 16,
                right: 16,
              ),
              child: GlassSurface(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: HsColors.glassStroke,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Pair New Device', style: HsText.headline),
                    const SizedBox(height: 8),
                    Text(
                      'Enter this 6-digit code or scan the QR code on your second device:',
                      style: HsText.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: HsColors.glassFillStrong,
                        borderRadius: BorderRadius.circular(HsColors.radiusInput),
                        border: Border.all(color: HsColors.glowMid.withAlpha(100)),
                      ),
                      child: Text(
                        pairing.code ?? '------',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: HsColors.glowHot,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (pairing.qrPayload != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(60),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: pairing.qrPayload!,
                          version: QrVersions.auto,
                          size: 140,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: HsColors.textTertiary),
                        const SizedBox(width: 6),
                        Text('Code active for 60 seconds', style: HsText.caption),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: 'Done',
                      variant: GlassButtonVariant.secondary,
                      width: double.infinity,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEnterCodeDialog() {
    _codeController.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Enter Pairing Code', style: HsText.headline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter the 6-digit code displayed on the other device:', style: HsText.body),
              const SizedBox(height: 16),
              GlassTextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                hint: '000000',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitCode(ctx),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: HsColors.textTertiary)),
            ),
            GlassButton(
              label: 'Verify',
              height: 40,
              fontSize: 14,
              onPressed: () => _submitCode(ctx),
            ),
          ],
        );
      },
    );
  }

  void _submitCode(BuildContext ctx) {
    final code = _codeController.text.trim();
    if (code.length == 6) {
      ref.read(engineProvider).send(SubmitPairingCodeCommand(code));
      Navigator.pop(ctx);
    }
  }

  void _showSasVerificationDialog(List<String> words, String peerName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Verify Device Match', style: HsText.headline),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Confirm that these 4 security words match identically on $peerName:', style: HsText.body),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final w in words)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: HsColors.glowMid.withAlpha(40),
                        borderRadius: BorderRadius.circular(HsColors.radiusSmall),
                        border: Border.all(color: HsColors.glowMid.withAlpha(100)),
                      ),
                      child: Text(
                        w.toUpperCase(),
                        style: const TextStyle(
                          color: HsColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
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
              child: const Text('Reject', style: TextStyle(color: HsColors.danger)),
            ),
            GlassButton(
              label: 'Words Match',
              height: 40,
              fontSize: 14,
              onPressed: () {
                ref.read(engineProvider).send(const ConfirmPairingCommand(true));
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmRevoke(Device device) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Forget Device?', style: HsText.headline),
          content: Text(
            'Remove "${device.name}" from your trusted list? You will need to pair again to transfer files.',
            style: HsText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: HsColors.textTertiary)),
            ),
            GlassButton(
              label: 'Forget',
              variant: GlassButtonVariant.danger,
              height: 40,
              fontSize: 14,
              onPressed: () {
                ref.read(engineProvider).send(RevokeDeviceCommand(device.id));
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onRevoke;

  const _DeviceCard({required this.device, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final isWin = device.platform.toLowerCase().contains('win');
    final lastSeen = device.lastSeenAt != null
        ? 'Seen ${device.lastSeenAt!.month}/${device.lastSeenAt!.day} ${device.lastSeenAt!.hour}:${device.lastSeenAt!.minute.toString().padLeft(2, '0')}'
        : 'Paired ${device.pairedAt.month}/${device.pairedAt.day}';

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
                        device.name,
                        style: HsText.title.copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const StatusDot(state: StatusDotState.online, size: 6),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$lastSeen  •  ID: ${device.id.substring(0, 8)}…',
                  style: HsText.caption,
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.devices_other_rounded, size: 48, color: HsColors.textTertiary),
            const SizedBox(height: 12),
            Text('No Paired Devices', style: HsText.headline.copyWith(fontSize: 18)),
            const SizedBox(height: 6),
            Text(
              'Pair with your PC or phone using a 6-digit PIN to enable instant auto-accept transfers.',
              style: HsText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
