import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// Modal dialog explaining first-time connection steps and reassuring users
/// that subsequent connections are instant and automatic.
class ConnectionGuideModal extends StatelessWidget {
  const ConnectionGuideModal({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const ConnectionGuideModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GlassSurface(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
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
                    child: const Icon(
                      Icons.wifi_tethering_rounded,
                      color: HsColors.glowHot,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How HotShare Connects',
                          style: HsText.title.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Quick setup • 100% automatic after pairing',
                          style: HsText.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: HsColors.textTertiary, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: HsColors.glassStroke),
              const SizedBox(height: 16),
              _buildStep(
                stepNumber: '1',
                title: 'Same Network or Hotspot',
                description:
                    'Connect both devices to the same Wi-Fi / MiFi, or turn on Hotspot on one device and connect the other to it.',
                icon: Icons.router_rounded,
              ),
              const SizedBox(height: 14),
              _buildStep(
                stepNumber: '2',
                title: 'Pair with 6-Digit PIN (First Time Only)',
                description:
                    'When connected for the first time, tap Enter PIN or Show PIN to pair. This verifies your devices securely.',
                icon: Icons.pin_rounded,
              ),
              const SizedBox(height: 14),
              _buildStep(
                stepNumber: '3',
                title: 'Instant & Automatic Thereafter',
                description:
                    'Once paired, connections happen automatically whenever both devices open HotShare. No typing IPs, no passwords.',
                icon: Icons.bolt_rounded,
                isHighlight: true,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GlassButton(
                  label: 'Got it',
                  variant: GlassButtonVariant.primary,
                  height: 44,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String stepNumber,
    required String title,
    required String description,
    required IconData icon,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isHighlight ? HsColors.glowHot.withAlpha(50) : HsColors.glassFillStrong,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHighlight ? HsColors.glowHot.withAlpha(120) : HsColors.glassStroke,
            ),
          ),
          child: Text(
            stepNumber,
            style: TextStyle(
              color: isHighlight ? HsColors.glowHot : HsColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isHighlight ? HsColors.glowHot : HsColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: HsText.title.copyWith(
                        fontSize: 13.5,
                        color: isHighlight ? HsColors.glowHot : HsColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: HsText.caption.copyWith(
                  color: HsColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
