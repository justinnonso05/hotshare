import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/engine_api.dart';
import '../../../state/engine_provider.dart';
import '../../../ui/design_system/design_system.dart';

/// Opens the pairing bottom sheet displaying the 6-digit PIN with a ticking
/// countdown that auto-refreshes every 60 seconds.
void showPairingSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PairingSheetModal(),
  );
}

class _PairingSheetModal extends ConsumerStatefulWidget {
  const _PairingSheetModal();

  @override
  ConsumerState<_PairingSheetModal> createState() => _PairingSheetModalState();
}

class _PairingSheetModalState extends ConsumerState<_PairingSheetModal> {
  int _remainingSeconds = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Request initial pairing window from engine
    ref.read(engineProvider).send(const OpenPairingWindowCommand());

    // Start 1-second countdown timer
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 1) {
          _remainingSeconds--;
        } else {
          // Time expired: auto-refresh code from engine and restart timer
          _remainingSeconds = 60;
          ref.read(engineProvider).send(const OpenPairingWindowCommand());
        }
      });
    });
  }

  void _refreshManually() {
    setState(() {
      _remainingSeconds = 60;
    });
    ref.read(engineProvider).send(const OpenPairingWindowCommand());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(pairingUiStateProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 16,
        right: 16,
      ),
      child: GlassSurface(
        padding: const EdgeInsets.all(24),
        borderRadius: BorderRadius.circular(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle
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
              'Enter this 6-digit PIN on your other device:',
              style: HsText.body.copyWith(color: HsColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Hero 6-digit PIN Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: HsColors.glassFillStrong,
                borderRadius: BorderRadius.circular(HsColors.radiusInput),
                border: Border.all(color: HsColors.glowMid.withAlpha(140), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: HsColors.glowHot.withAlpha(35),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(
                pairing.code ?? '------',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                  color: HsColors.glowHot,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Live countdown & Refresh action
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: _remainingSeconds <= 10 ? HsColors.glowHot : HsColors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Code expires in ${_remainingSeconds}s',
                  style: HsText.caption.copyWith(
                    color: _remainingSeconds <= 10 ? HsColors.glowHot : HsColors.textSecondary,
                    fontWeight: _remainingSeconds <= 10 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _refreshManually,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 14, color: HsColors.accentPrimary),
                        const SizedBox(width: 4),
                        Text(
                          'Refresh',
                          style: HsText.caption.copyWith(
                            color: HsColors.accentPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Done Button
            GlassButton(
              label: 'Done',
              variant: GlassButtonVariant.secondary,
              width: double.infinity,
              height: 44,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for manually entering a 6-digit PIN code displayed on the peer device.
void showEnterPinDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();

  void submit(BuildContext ctx) {
    final code = controller.text.trim();
    if (code.length == 6) {
      ref.read(engineProvider).send(SubmitPairingCodeCommand(code));
      Navigator.pop(ctx);
    }
  }

  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: HsColors.bgRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HsColors.glassStroke),
        ),
        title: Text('Enter Pairing PIN', style: HsText.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the 6-digit PIN displayed on your second device:',
              style: HsText.body.copyWith(color: HsColors.textSecondary),
            ),
            const SizedBox(height: 16),
            GlassTextField(
              controller: controller,
              keyboardType: TextInputType.number,
              hint: '000000',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(ctx),
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
                  label: 'Verify PIN',
                  variant: GlassButtonVariant.primary,
                  height: 42,
                  fontSize: 14,
                  onPressed: () => submit(ctx),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// Dialog for SAS 4-word confirmation match.
void showSasVerificationDialog(
  BuildContext context,
  WidgetRef ref,
  List<String> words,
  String peerName,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: HsColors.bgRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HsColors.glassStroke),
        ),
        title: Text('Verify Security Match', style: HsText.headline),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm that these 4 security words match identically on $peerName:',
              style: HsText.body.copyWith(color: HsColors.textSecondary),
            ),
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
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Reject',
                  variant: GlassButtonVariant.danger,
                  height: 42,
                  fontSize: 14,
                  onPressed: () {
                    ref.read(engineProvider).send(const ConfirmPairingCommand(false));
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  label: 'Confirm Match',
                  variant: GlassButtonVariant.primary,
                  height: 42,
                  fontSize: 14,
                  onPressed: () {
                    ref.read(engineProvider).send(const ConfirmPairingCommand(true));
                    Navigator.pop(ctx);
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

/// Prompt dialog when user attempts to send files to an unpaired connected peer.
void showPairingRequiredPrompt(
  BuildContext context,
  WidgetRef ref,
  String peerName,
) {
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: HsColors.bgRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HsColors.glassStroke),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: HsColors.glowHot, size: 24),
            const SizedBox(width: 10),
            Text('Pairing Required', style: HsText.headline),
          ],
        ),
        content: Text(
          'Before transferring files with $peerName, pair your devices once with a 6-digit PIN. One device displays the PIN, and the other enters it.',
          style: HsText.body.copyWith(color: HsColors.textSecondary),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Show PIN',
                  variant: GlassButtonVariant.secondary,
                  height: 42,
                  fontSize: 13,
                  onPressed: () {
                    Navigator.pop(ctx);
                    showPairingSheet(context);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  label: 'Enter PIN',
                  variant: GlassButtonVariant.primary,
                  height: 42,
                  fontSize: 13,
                  onPressed: () {
                    Navigator.pop(ctx);
                    showEnterPinDialog(context, ref);
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
