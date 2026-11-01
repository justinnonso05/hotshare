import 'package:flutter/material.dart';

import 'hs_colors.dart';

/// Connection status indicator dot.
///
/// - [StatusDotState.online]: solid green, no pulse
/// - [StatusDotState.reconnecting]: amber with pulsing opacity
/// - [StatusDotState.offline]: muted grey
enum StatusDotState { online, reconnecting, offline }

class StatusDot extends StatefulWidget {
  final StatusDotState state;
  final double size;

  const StatusDot({super.key, required this.state, this.size = 8});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _startIfNeeded();
  }

  void _startIfNeeded() {
    if (widget.state == StatusDotState.reconnecting) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.state) {
      case StatusDotState.online:
        return HsColors.success;
      case StatusDotState.reconnecting:
        return HsColors.warning;
      case StatusDotState.offline:
        return const Color(0x61FFFFFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _color.withAlpha(
            widget.state == StatusDotState.reconnecting
                ? (100 + (_pulse.value * 155).round())
                : 255,
          ),
          boxShadow: widget.state != StatusDotState.offline
              ? [
                  BoxShadow(
                    color: _color.withAlpha(120),
                    blurRadius: widget.size * 1.5,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
