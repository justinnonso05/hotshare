import 'package:flutter/material.dart';
import 'hs_colors.dart';
import 'hs_text.dart';

/// Visual variant for a [GlassButton].
enum GlassButtonVariant { primary, secondary, ghost, danger }

/// An Ember Glass styled button:
/// - Primary: radial ember gradient fill, white bold label, glow shadow.
/// - Secondary: frosted glass with stroke border.
/// - Ghost: transparent with accent stroke.
/// - Danger: deep red fill.
///
/// Loading state shows a small spinner ring instead of a full-screen overlay.
class GlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final GlassButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;
  final double fontSize;

  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = GlassButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 52,
    this.fontSize = HsText.sizeBody,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) => _ctrl.forward();
  void _up(TapUpDetails _) {
    _ctrl.reverse();
    widget.onPressed?.call();
  }
  void _cancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null && !widget.isLoading;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _labelColor,
            ),
          )
        else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18, color: _labelColor),
          const SizedBox(width: 8),
        ],
        if (!widget.isLoading || widget.icon != null)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                style: HsText.labelBold.copyWith(
                  fontSize: widget.fontSize,
                  color: _labelColor,
                ),
                maxLines: 1,
              ),
            ),
          ),
      ],
    );

    Widget button = GestureDetector(
      onTapDown: disabled ? null : _down,
      onTapUp: disabled ? null : _up,
      onTapCancel: disabled ? null : _cancel,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: _decoration(disabled),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    return button;
  }

  Color get _labelColor {
    switch (widget.variant) {
      case GlassButtonVariant.primary:
      case GlassButtonVariant.danger:
        return HsColors.textPrimary;
      case GlassButtonVariant.secondary:
      case GlassButtonVariant.ghost:
        return HsColors.textPrimary;
    }
  }

  BoxDecoration _decoration(bool disabled) {
    final radius = BorderRadius.circular(HsColors.radiusPill);

    switch (widget.variant) {
      case GlassButtonVariant.primary:
        return BoxDecoration(
          borderRadius: radius,
          gradient: disabled
              ? const LinearGradient(
                  colors: [Color(0x40E5231B), Color(0x40FF7A1A)],
                )
              : HsColors.emberGradient,
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: HsColors.glowMid.withAlpha(77),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        );

      case GlassButtonVariant.secondary:
        return BoxDecoration(
          borderRadius: radius,
          color: HsColors.glassFillStrong,
          border: Border.all(color: HsColors.glassStroke),
        );

      case GlassButtonVariant.ghost:
        return BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: disabled
                ? HsColors.glassStroke
                : HsColors.accentPrimary.withAlpha(153),
          ),
        );

      case GlassButtonVariant.danger:
        return BoxDecoration(
          borderRadius: radius,
          color: HsColors.danger.withAlpha(disabled ? 64 : 204),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: HsColors.danger.withAlpha(64),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        );
    }
  }
}
