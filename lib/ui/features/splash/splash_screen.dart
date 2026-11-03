import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';

/// Animated splash screen showing the HotShare icon with a breathing glow on an obsidian canvas.
class HotShareSplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const HotShareSplashScreen({
    super.key,
    required this.onFinish,
  });

  @override
  State<HotShareSplashScreen> createState() => _HotShareSplashScreenState();
}

class _HotShareSplashScreenState extends State<HotShareSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _glowAnim = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.1, 0.75, curve: Curves.easeInOut),
      ),
    );

    _fadeAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.85, 1.0, curve: Curves.easeIn),
      ),
    );

    _ctrl.forward().then((_) {
      if (mounted) {
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0808),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnim.value.clamp(0.0, 1.0),
            child: Center(
              child: Transform.scale(
                scale: _scaleAnim.value,
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: HsColors.glowHot.withAlpha((70 * _glowAnim.value).toInt()),
                        blurRadius: 36 * _glowAnim.value,
                        spreadRadius: 6 * _glowAnim.value,
                      ),
                      BoxShadow(
                        color: HsColors.glowMid.withAlpha((50 * _glowAnim.value).toInt()),
                        blurRadius: 60 * _glowAnim.value,
                        spreadRadius: 10 * _glowAnim.value,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/icon/icon_rounded_512.png',
                      width: 108,
                      height: 108,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
