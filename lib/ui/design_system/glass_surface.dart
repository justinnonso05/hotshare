import 'dart:ui';

import 'package:flutter/material.dart';

import 'hs_colors.dart';

/// Visual style for a [GlassSurface].
enum GlassStyle {
  /// Blurred frosted glass with full backdrop filter.
  frosted,

  /// Solid dark fill — used when the user has "reduce transparency" enabled.
  opaque,
}

/// A frosted-glass card/container following the Ember Glass spec:
/// - Backdrop blur (sigma 18)
/// - Gradient border: top-left 28 % white → bottom-right 8 % white
/// - Top specular highlight line (1 dp, 22 % white)
/// - Drop shadow: black 35 %, blur 30, y +12
///
/// Supports an optional [onTap] with a spring-back press scale animation.
class GlassSurface extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final GlassStyle style;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? fillColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.style = GlassStyle.frosted,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.fillColor,
  });

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTapDown(TapDownDetails _) async {
    if (widget.onTap == null) return;
    await _scaleCtrl.forward();
  }

  Future<void> _onTapUp(TapUpDetails _) async {
    await _scaleCtrl.reverse();
    widget.onTap?.call();
  }

  Future<void> _onTapCancel() async {
    await _scaleCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(HsColors.radiusCard);
    final fillColor = widget.fillColor ??
        (widget.style == GlassStyle.opaque
            ? HsColors.bgRaised
            : HsColors.glassFill);

    Widget surface = ClipRRect(
      borderRadius: radius,
      child: widget.style == GlassStyle.frosted
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: _buildInner(radius, fillColor),
            )
          : _buildInner(radius, fillColor),
    );

    if (widget.onTap != null) {
      surface = GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: ScaleTransition(scale: _scaleAnim, child: surface),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: surface,
    );
  }

  Widget _buildInner(BorderRadius radius, Color fillColor) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: fillColor,
        border: Border.all(
          color: HsColors.glassStroke,
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000), // 35 %
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top specular highlight
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: radius,
              child: Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x38FFFFFF), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: widget.padding,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
