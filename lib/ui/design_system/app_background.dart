import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'hs_colors.dart';

/// Full-screen animated background — two slow-drifting radial glow blobs
/// layered on the [HsColors.bgBase] fill. Wrapped in a [RepaintBoundary]
/// so the animation never propagates invalidations into the content tree.
class AppBackground extends StatefulWidget {
  final Widget child;
  final bool reduceMotion;

  const AppBackground({
    super.key,
    required this.child,
    this.reduceMotion = false,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl1;
  late final AnimationController _ctrl2;

  @override
  void initState() {
    super.initState();
    _ctrl1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat(reverse: true);

    _ctrl2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 55),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AppBackground old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion != old.reduceMotion) {
      if (widget.reduceMotion) {
        _ctrl1.stop();
        _ctrl2.stop();
      } else {
        _ctrl1.repeat(reverse: true);
        _ctrl2.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _ctrl1.dispose();
    _ctrl2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base fill
          const ColoredBox(color: HsColors.bgBase),

          // Blob 1 — deep crimson, bottom-left drift
          _AnimatedBlob(
            controller: _ctrl1,
            baseAlignment: Alignment.bottomLeft,
            targetAlignment: const Alignment(-0.2, 0.2),
            color: HsColors.glowDeep.withAlpha(89), // 35 %
            radiusFraction: 0.65,
          ),

          // Blob 2 — warm orange, top-right drift
          _AnimatedBlob(
            controller: _ctrl2,
            baseAlignment: Alignment.topRight,
            targetAlignment: const Alignment(0.3, -0.3),
            color: HsColors.glowHot.withAlpha(51), // 20 %
            radiusFraction: 0.55,
          ),

          // Content
          widget.child,
        ],
      ),
    );
  }
}

class _AnimatedBlob extends AnimatedWidget {
  final Alignment baseAlignment;
  final Alignment targetAlignment;
  final Color color;
  final double radiusFraction;

  const _AnimatedBlob({
    required AnimationController controller,
    required this.baseAlignment,
    required this.targetAlignment,
    required this.color,
    required this.radiusFraction,
  }) : super(listenable: controller);

  AnimationController get controller => listenable as AnimationController;

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeInOut.transform(controller.value);
    final align = Alignment.lerp(baseAlignment, targetAlignment, t)!;
    final size = MediaQuery.sizeOf(context);
    final radius = math.min(size.width, size.height) * radiusFraction;

    return Align(
      alignment: align,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
