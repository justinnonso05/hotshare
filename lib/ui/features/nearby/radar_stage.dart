import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../ui/design_system/design_system.dart';

/// Interactive topology radar stage.
///
/// Topologies:
/// 1. Initial State: Local device bubble sits in the center with scanning radar rings.
/// 2. 1 Peer Connected: Local device slides smoothly to the left, peer device animates
///    in on the right, connected by an interactive holographic bridge.
/// 3. Active Transfer: The bridge acts as a liquid progress bar, filling from sender to
///    receiver with flowing photon pulses and live speed/progress badge.
/// 4. 2+ Peers: Arranged in a sleek triangle topology with the active transfer beam
///    illuminating between the transmitting nodes.
class RadarStage extends StatefulWidget {
  final List<DeviceBubble> devices;
  final bool isTransferring;
  final double transferProgress;
  final bool isSending;
  final double speedBytesPerSec;
  final String? localDeviceName;
  final bool reduceMotion;

  const RadarStage({
    super.key,
    this.devices = const [],
    this.isTransferring = false,
    this.transferProgress = 0.0,
    this.isSending = false,
    this.speedBytesPerSec = 0.0,
    this.localDeviceName,
    this.reduceMotion = false,
  });

  @override
  State<RadarStage> createState() => _RadarStageState();
}

class _RadarStageState extends State<RadarStage> with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _beamCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _beamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _glowCtrl.dispose();
    _beamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageWidth = constraints.maxWidth > 0
            ? math.min(constraints.maxWidth, 380.0)
            : 320.0;
        const stageHeight = 250.0;
        const bubbleSize = 72.0;

        final hasPeers = widget.devices.isNotEmpty;
        final peerCount = widget.devices.length;

        // Calculate positions
        Offset localCenter;
        List<Offset> peerCenters = [];

        if (peerCount == 0) {
          // Centered single device
          localCenter = Offset(stageWidth / 2, stageHeight / 2);
        } else if (peerCount == 1) {
          // Horizontal pairing: Left (Local) <---> Right (Peer)
          localCenter = Offset(stageWidth * 0.24, stageHeight / 2);
          peerCenters.add(Offset(stageWidth * 0.76, stageHeight / 2));
        } else {
          // Triangle arrangement
          localCenter = Offset(stageWidth * 0.24, stageHeight * 0.72);
          peerCenters.add(Offset(stageWidth * 0.76, stageHeight * 0.72)); // Peer 1: bottom-right
          peerCenters.add(Offset(stageWidth * 0.50, stageHeight * 0.28)); // Peer 2: top-center
        }

        final isWin = Platform.isWindows;
        final localName = widget.localDeviceName ?? (isWin ? 'Windows PC' : 'My Phone');

        return SizedBox(
          width: stageWidth,
          height: stageHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // ── Background Scanning Rings (when looking for peers) ────────
              if (!hasPeers && !widget.reduceMotion) ...[
                _PulsingRing(controller: _ringCtrl, delay: 0.0, maxRadius: stageHeight * 0.48),
                _PulsingRing(controller: _ringCtrl, delay: 0.33, maxRadius: stageHeight * 0.48),
                _PulsingRing(controller: _ringCtrl, delay: 0.66, maxRadius: stageHeight * 0.48),
              ],

              // ── Holographic Connection Bridges & Progress Beam ────────────
              if (hasPeers)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_beamCtrl, _glowCtrl]),
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _BridgeProgressPainter(
                          localCenter: localCenter,
                          peerCenters: peerCenters,
                          isTransferring: widget.isTransferring,
                          progress: widget.transferProgress,
                          isSending: widget.isSending,
                          beamAnimation: _beamCtrl.value,
                          glowValue: _glowCtrl.value,
                        ),
                      );
                    },
                  ),
                ),

              // ── Floating Transfer Speed & Progress Badge ──────────────────
              if (widget.isTransferring && hasPeers)
                _buildTransferPill(localCenter, peerCenters.first),

              // ── This Device Bubble (Slides left when connected) ───────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeInOutCubic,
                left: localCenter.dx - (bubbleSize / 2),
                top: localCenter.dy - (bubbleSize / 2),
                child: _LocalDeviceBubble(
                  name: localName,
                  isWindows: isWin,
                  size: bubbleSize,
                  glowController: _glowCtrl,
                  reduceMotion: widget.reduceMotion,
                  isTransferring: widget.isTransferring,
                ),
              ),

              // ── Peer Device Bubbles (Animates in from right/top) ──────────
              for (int i = 0; i < peerCenters.length; i++)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeInOutCubic,
                  left: peerCenters[i].dx - (bubbleSize / 2),
                  top: peerCenters[i].dy - (bubbleSize / 2),
                  child: widget.devices[i],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransferPill(Offset start, Offset end) {
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final speed = formatBytes(widget.speedBytesPerSec.round());
    final pct = (widget.transferProgress * 100).toInt();

    return Positioned(
      left: mid.dx - 54,
      top: mid.dy - 34,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: HsColors.bgRaised.withAlpha(220),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HsColors.accentPrimary.withAlpha(180), width: 1),
          boxShadow: [
            BoxShadow(
              color: HsColors.glowHot.withAlpha(50),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isSending ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              size: 13,
              color: HsColors.accentPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              '$pct% • $speed/s',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: HsColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws the connection bridge and active liquid progress beam.
class _BridgeProgressPainter extends CustomPainter {
  final Offset localCenter;
  final List<Offset> peerCenters;
  final bool isTransferring;
  final double progress;
  final bool isSending;
  final double beamAnimation;
  final double glowValue;

  _BridgeProgressPainter({
    required this.localCenter,
    required this.peerCenters,
    required this.isTransferring,
    required this.progress,
    required this.isSending,
    required this.beamAnimation,
    required this.glowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peerCenters.isEmpty) return;

    // Connect mesh lines if more than 1 peer (triangle)
    if (peerCenters.length >= 2) {
      final meshPaint = Paint()
        ..color = HsColors.glassStroke.withAlpha(60)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(peerCenters[0], peerCenters[1], meshPaint);
      canvas.drawLine(localCenter, peerCenters[1], meshPaint);
    }

    // Active primary link between local and primary peer
    final p1 = localCenter;
    final p2 = peerCenters.first;

    // Background track line
    final trackPaint = Paint()
      ..color = HsColors.glassStroke.withAlpha(80)
      ..strokeWidth = isTransferring ? 4.0 : 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(p1, p2, trackPaint);

    if (!isTransferring) {
      // Idle pulse beam
      final idleGlowPaint = Paint()
        ..color = HsColors.accentPrimary.withAlpha((40 + glowValue * 60).toInt())
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawLine(p1, p2, idleGlowPaint);
      return;
    }

    // ── Active Transfer Liquid Progress Bar ───────────────────────────────
    final from = isSending ? p1 : p2;
    final to = isSending ? p2 : p1;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final clampedProgress = progress.clamp(0.01, 1.0);
    final fillEnd = Offset(from.dx + dx * clampedProgress, from.dy + dy * clampedProgress);

    // Glowing outer bloom
    final bloomPaint = Paint()
      ..color = HsColors.glowHot.withAlpha(110)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(from, fillEnd, bloomPaint);

    // Core liquid beam with gradient
    final beamPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          HsColors.accentPrimary,
          HsColors.glowHot,
          Colors.white,
        ],
        stops: const [0.0, 0.85, 1.0],
      ).createShader(Rect.fromPoints(from, to))
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(from, fillEnd, beamPaint);

    // Flowing energy particle/bead along the line
    final pulsePos = (beamAnimation % 1.0);
    if (pulsePos <= clampedProgress) {
      final beadOffset = Offset(from.dx + dx * pulsePos, from.dy + dy * pulsePos);
      final beadPaint = Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(beadOffset, 4.0, beadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BridgeProgressPainter old) => true;
}

/// The local device orb ("This one")
class _LocalDeviceBubble extends StatelessWidget {
  final String name;
  final bool isWindows;
  final double size;
  final AnimationController glowController;
  final bool reduceMotion;
  final bool isTransferring;

  const _LocalDeviceBubble({
    required this.name,
    required this.isWindows,
    required this.size,
    required this.glowController,
    required this.reduceMotion,
    required this.isTransferring,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: glowController,
          builder: (context, child) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isTransferring ? HsColors.glowHot : HsColors.glowMid).withAlpha(
                      reduceMotion ? 40 : (35 + glowController.value * 50).round(),
                    ),
                    blurRadius: reduceMotion ? 16 : 16 + glowController.value * 16,
                    spreadRadius: isTransferring ? 2 : 0,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: GlassSurface(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(size / 2),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  isWindows ? Icons.laptop_windows_rounded : Icons.phone_android_rounded,
                  color: HsColors.textPrimary,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 85,
          child: Text(
            name,
            style: HsText.caption.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A single remote device bubble on the stage.
class DeviceBubble extends StatelessWidget {
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
  Widget build(BuildContext context) {
    const bubbleSize = 72.0;
    final dotState = isConnected ? StatusDotState.online : StatusDotState.offline;

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
                    color: isConnected ? HsColors.textPrimary : HsColors.textTertiary,
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
          width: 85,
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
