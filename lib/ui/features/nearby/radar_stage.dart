import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/design_system/design_system.dart';

/// Animated radar stage showing concentric pulsing rings and peer bubbles.
///
/// [peerCount] controls how many placeholder orbit bubbles are shown while
/// no real peers are connected.  Real [DeviceBubble] widgets are injected
/// via [devices].
class RadarStage extends StatefulWidget {
  final int peerCount;
  final List<Widget> devices;
  final bool reduceMotion;

  const RadarStage({
    super.key,
    this.peerCount = 0,
    this.devices = const [],
    this.reduceMotion = false,
  });

  @override
  State<RadarStage> createState() => _RadarStageState();
}

class _RadarStageState extends State<RadarStage> with TickerProviderStateMixin {
  late final AnimationController _ring;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ring.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const stageSize = 280.0;
    const orbSize = 80.0;
    const orbitR = 100.0;

    return SizedBox(
      width: stageSize,
      height: stageSize,
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing rings
            if (!widget.reduceMotion) ...[
              _PulsingRing(controller: _ring, delay: 0.0, maxRadius: stageSize / 2),
              _PulsingRing(
                  controller: _ring, delay: 0.33, maxRadius: stageSize / 2),
              _PulsingRing(
                  controller: _ring, delay: 0.66, maxRadius: stageSize / 2),
            ] else ...[
              _StaticRing(radius: stageSize * 0.3),
              _StaticRing(radius: stageSize * 0.45),
            ],

            // Orbit device bubbles
            for (int i = 0; i < widget.devices.length; i++)
              _OrbitPosition(
                index: i,
                total: math.max(widget.devices.length, 1),
                orbitRadius: orbitR,
                stageSize: stageSize,
                child: widget.devices[i],
              ),

            // Centre "You" orb
            AnimatedBuilder(
              animation: _glow,
              builder: (context, child) => Container(
                width: orbSize,
                height: orbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: HsColors.glowMid.withAlpha(
                        widget.reduceMotion
                            ? 60
                            : (30 + (_glow.value * 60)).round(),
                      ),
                      blurRadius: widget.reduceMotion
                          ? 20
                          : 20 + _glow.value * 20,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: child,
              ),
              child: GlassSurface(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(orbSize / 2),
                child: SizedBox(
                  width: orbSize,
                  height: orbSize,
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: HsColors.textPrimary,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingRing extends AnimatedWidget {
  final double delay;
  final double maxRadius;

  const _PulsingRing({
    required AnimationController controller,
    required this.delay,
    required this.maxRadius,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final ctrl = listenable as AnimationController;
    final t = ((ctrl.value + delay) % 1.0);
    final radius = t * maxRadius;
    final opacity = (1.0 - t) * 0.25;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: HsColors.accentPrimary.withAlpha((opacity * 255).round()),
          width: 1,
        ),
      ),
    );
  }
}

class _StaticRing extends StatelessWidget {
  final double radius;
  const _StaticRing({required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: HsColors.accentPrimary.withAlpha(30),
          width: 1,
        ),
      ),
    );
  }
}

class _OrbitPosition extends StatelessWidget {
  final int index;
  final int total;
  final double orbitRadius;
  final double stageSize;
  final Widget child;

  const _OrbitPosition({
    required this.index,
    required this.total,
    required this.orbitRadius,
    required this.stageSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final angle = (2 * math.pi / total) * index - math.pi / 2;
    final cx = stageSize / 2 + orbitRadius * math.cos(angle);
    final cy = stageSize / 2 + orbitRadius * math.sin(angle);

    return Positioned(
      left: cx - 36,
      top: cy - 36,
      child: child,
    );
  }
}

/// A single device bubble on the radar orbit.
class DeviceBubble extends ConsumerWidget {
  final String name;
  final String platform; // 'android' | 'windows'
  final bool isConnected;
  final bool isTransferring;
  final double transferProgress;
  final String? transferFileName;
  final double speedBytesPerSec;
  final VoidCallback? onTap;

  const DeviceBubble({
    super.key,
    required this.name,
    required this.platform,
    this.isConnected = false,
    this.isTransferring = false,
    this.transferProgress = 0,
    this.transferFileName,
    this.speedBytesPerSec = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const bubbleSize = 72.0;
    final dotState = isConnected
        ? StatusDotState.online
        : StatusDotState.offline;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: bubbleSize,
          height: bubbleSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Transfer ring
              if (isTransferring)
                TransferRing(
                  progress: transferProgress,
                  size: bubbleSize,
                  strokeWidth: 3,
                ),

              // Glass bubble
              GlassSurface(
                width: bubbleSize - (isTransferring ? 8 : 0),
                height: bubbleSize - (isTransferring ? 8 : 0),
                borderRadius: BorderRadius.circular(bubbleSize),
                padding: EdgeInsets.zero,
                onTap: onTap,
                child: Center(
                  child: Icon(
                    platform == 'windows'
                        ? Icons.laptop_windows_rounded
                        : Icons.phone_android_rounded,
                    color: isConnected
                        ? HsColors.textPrimary
                        : HsColors.textTertiary,
                    size: 26,
                  ),
                ),
              ),

              // Status dot
              Positioned(
                bottom: isTransferring ? 7 : 2,
                right: isTransferring ? 7 : 2,
                child: StatusDot(state: dotState, size: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 80,
          child: Text(
            name,
            style: HsText.caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
