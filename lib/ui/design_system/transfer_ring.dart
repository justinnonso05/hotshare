import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hs_colors.dart';

/// A circular progress ring with an ember gradient stroke.
///
/// Animates between [progress] values (0.0–1.0) using a 200 ms ease curve.
/// The background track uses [HsColors.glassStroke].
class TransferRing extends StatefulWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final bool showTrack;

  const TransferRing({
    super.key,
    required this.progress,
    this.size = 64,
    this.strokeWidth = 4,
    this.showTrack = true,
  });

  @override
  State<TransferRing> createState() => _TransferRingState();
}

class _TransferRingState extends State<TransferRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _progressAnim;
  double _previousProgress = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _progressAnim =
        Tween<double>(begin: 0, end: widget.progress).animate(_ctrl);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(TransferRing old) {
    super.didUpdateWidget(old);
    if ((old.progress - widget.progress).abs() > 0.001) {
      _previousProgress = _progressAnim.value;
      _progressAnim = Tween<double>(
        begin: _previousProgress,
        end: widget.progress,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _RingPainter(
          progress: _progressAnim.value,
          strokeWidth: widget.strokeWidth,
          showTrack: widget.showTrack,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final bool showTrack;

  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.showTrack,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    if (showTrack) {
      final trackPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = HsColors.glassStroke;
      canvas.drawCircle(center, radius, trackPaint);
    }

    if (progress <= 0) return;

    // Gradient arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: -math.pi / 2 + 2 * math.pi,
      colors: const [HsColors.glowMid, HsColors.glowHot, HsColors.glowMid],
      stops: const [0.0, 0.5, 1.0],
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.strokeWidth != strokeWidth;
}
