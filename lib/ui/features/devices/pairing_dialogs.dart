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
  bool _hasPopped = false;

  void _safePop() {
    if (!_hasPopped && mounted && Navigator.of(context).canPop()) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    ref.read(engineProvider).send(const OpenPairingWindowCommand());
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

    // Auto-dismiss the 6-digit PIN sheet when SAS verification begins or pairing completes
    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords != null || next.isWindowOpen == false) {
        _safePop();
      }
    });

    ref.listen<PeerConnectionState>(peerConnectionProvider, (prev, next) {
      if (next.isPaired) {
        _safePop();
      }
    });

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
  showDialog(
    context: context,
    builder: (ctx) => const _EnterPinDialog(),
  );
}

class _EnterPinDialog extends ConsumerStatefulWidget {
  const _EnterPinDialog();

  @override
  ConsumerState<_EnterPinDialog> createState() => _EnterPinDialogState();
}

class _EnterPinDialogState extends ConsumerState<_EnterPinDialog> {
  final _controller = TextEditingController();
  bool _hasPopped = false;

  void _safePop() {
    if (!_hasPopped && mounted && Navigator.of(context).canPop()) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.length == 6) {
      ref.read(engineProvider).send(SubmitPairingCodeCommand(code));
      _safePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-dismiss if SAS starts or pairing completes
    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords != null) {
        _safePop();
      }
    });

    ref.listen<PeerConnectionState>(peerConnectionProvider, (prev, next) {
      if (next.isPaired) {
        _safePop();
      }
    });

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
            Text('Enter Pairing PIN', style: HsText.headline),
            const SizedBox(height: 12),
            Text(
              'Enter the 6-digit PIN displayed on your second device:',
              style: HsText.body.copyWith(color: HsColors.textSecondary),
            ),
            const SizedBox(height: 18),
            GlassTextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              hint: '000000',
              prefixIcon: Icons.pin_rounded,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    variant: GlassButtonVariant.secondary,
                    height: 42,
                    fontSize: 14,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Connect',
                    variant: GlassButtonVariant.primary,
                    height: 42,
                    fontSize: 14,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
    builder: (ctx) => _SasVerificationDialog(words: words, peerName: peerName),
  );
}

class _SasVerificationDialog extends ConsumerStatefulWidget {
  final List<String> words;
  final String peerName;

  const _SasVerificationDialog({
    required this.words,
    required this.peerName,
  });

  @override
  ConsumerState<_SasVerificationDialog> createState() => _SasVerificationDialogState();
}

class _SasVerificationDialogState extends ConsumerState<_SasVerificationDialog> {
  bool _hasPopped = false;

  void _safePop() {
    if (!_hasPopped && mounted && Navigator.of(context).canPop()) {
      _hasPopped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // When pairing finishes (either confirmed locally or by the peer), auto-dismiss safely!
    ref.listen<PeerConnectionState>(peerConnectionProvider, (prev, next) {
      if (next.isPaired) {
        _safePop();
      }
    });

    ref.listen<PairingUiState>(pairingUiStateProvider, (prev, next) {
      if (next.sasWords == null) {
        _safePop();
      }
    });

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
            Text('Verify Security Match', style: HsText.headline),
            const SizedBox(height: 12),
            Text(
              'Confirm that these 4 security words match identically on ${widget.peerName}:',
              style: HsText.body.copyWith(color: HsColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Center(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final w in widget.words)
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
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Reject',
                    variant: GlassButtonVariant.danger,
                    height: 44,
                    fontSize: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () {
                      ref.read(engineProvider).send(const ConfirmPairingCommand(false));
                      _safePop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassButton(
                    label: 'Confirm Match',
                    variant: GlassButtonVariant.primary,
                    height: 44,
                    fontSize: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () {
                      ref.read(engineProvider).send(const ConfirmPairingCommand(true));
                      _safePop();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: HsColors.glowMid.withAlpha(40),
                      shape: BoxShape.circle,
                      border: Border.all(color: HsColors.glowMid.withAlpha(80)),
                    ),
                    child: const Icon(Icons.shield_outlined, color: HsColors.glowHot, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('Pairing Required', style: HsText.headline),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Before transferring files with $peerName, pair your devices once with a 6-digit PIN. One device displays the PIN, and the other enters it.',
                style: HsText.body.copyWith(color: HsColors.textSecondary),
              ),
              const SizedBox(height: 22),
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
          ),
        ),
      );
    },
  );
}

/// Prompt dialog when Auto-Accept is disabled and a peer offers a file transfer.
void showIncomingTransferOfferDialog(
  BuildContext context,
  WidgetRef ref,
  IncomingTransferOfferEvent offer,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
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
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: HsColors.glowMid.withAlpha(40),
                      shape: BoxShape.circle,
                      border: Border.all(color: HsColors.glowMid.withAlpha(80)),
                    ),
                    child: const Icon(Icons.download_rounded, color: HsColors.glowHot, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incoming Transfer Offer', style: HsText.title.copyWith(fontSize: 16)),
                        const SizedBox(height: 2),
                        Text('From ${offer.peerName}', style: HsText.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HsColors.glassFillStrong,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HsColors.glassStroke),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined, color: HsColors.glowHot, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(offer.fileName, style: HsText.body.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${(offer.size / (1024 * 1024)).toStringAsFixed(2)} MB', style: HsText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Decline',
                      variant: GlassButtonVariant.danger,
                      height: 44,
                      fontSize: 14,
                      onPressed: () {
                        ref.read(engineProvider).send(RespondToTransferOfferCommand(
                          transferId: offer.transferId,
                          accept: false,
                        ));
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: 'Accept',
                      variant: GlassButtonVariant.primary,
                      height: 44,
                      fontSize: 14,
                      onPressed: () {
                        ref.read(engineProvider).send(RespondToTransferOfferCommand(
                          transferId: offer.transferId,
                          accept: true,
                        ));
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
