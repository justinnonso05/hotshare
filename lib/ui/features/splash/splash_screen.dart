import 'dart:async';
import 'package:flutter/material.dart';

/// Clean, flat splash screen showing the HotShare icon momentarily on an obsidian canvas.
class HotShareSplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const HotShareSplashScreen({
    super.key,
    required this.onFinish,
  });

  @override
  State<HotShareSplashScreen> createState() => _HotShareSplashScreenState();
}

class _HotShareSplashScreenState extends State<HotShareSplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Display cleanly for 800ms, then proceed to the main interface
    _timer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0808),
      body: Center(
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
    );
  }
}
