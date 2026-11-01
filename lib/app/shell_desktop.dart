import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../state/engine_provider.dart';
import '../ui/design_system/design_system.dart';

/// Desktop shell for Windows: custom title bar + left navigation rail.
class DesktopShell extends ConsumerStatefulWidget {
  final List<Widget> pages;
  final List<RailItem> railItems;

  const DesktopShell({
    super.key,
    required this.pages,
    required this.railItems,
  });

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class RailItem {
  final IconData icon;
  final String label;

  const RailItem({required this.icon, required this.label});
}

const desktopRailItems = [
  RailItem(icon: Icons.wifi_tethering_rounded, label: 'Nearby'),
  RailItem(icon: Icons.history_rounded, label: 'History'),
  RailItem(icon: Icons.devices_rounded, label: 'Devices'),
  RailItem(icon: Icons.settings_rounded, label: 'Settings'),
];

class _DesktopShellState extends ConsumerState<DesktopShell>
    with WindowListener {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(peerConnectionProvider);
    final dotState = connState.isConnected
        ? StatusDotState.online
        : StatusDotState.offline;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Custom title bar ──────────────────────────────────────────────
          _TitleBar(dotState: dotState),

          // ── Main content: rail + page ─────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                _NavRail(
                  items: widget.railItems,
                  selectedIndex: _index,
                  onTap: (i) => setState(() => _index = i),
                ),
                // Page content — max width 960, centered
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: IndexedStack(
                        index: _index,
                        children: widget.pages,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  final StatusDotState dotState;

  const _TitleBar({required this.dotState});

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        height: 44,
        color: HsColors.bgBase.withAlpha(220),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            StatusDot(state: dotState, size: 8),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/icon/icon_rounded_512.png',
                width: 18,
                height: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'HotShare',
              style: HsText.title.copyWith(fontSize: 14),
            ),
            const Spacer(),
            // Window controls
            _WindowButton(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 8),
            _WindowButton(
              icon: Icons.crop_square_rounded,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            const SizedBox(width: 8),
            _WindowButton(
              icon: Icons.close_rounded,
              isDanger: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDanger;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? (widget.isDanger
                    ? HsColors.danger.withAlpha(200)
                    : HsColors.glassFillStrong)
                : HsColors.glassFill,
          ),
          child: Icon(widget.icon,
              size: 14,
              color: _hovered ? HsColors.textPrimary : HsColors.textTertiary),
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  final List<RailItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _NavRail({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: HsColors.bgBase.withAlpha(180),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++)
            _RailButton(
              item: items[i],
              isSelected: i == selectedIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  final RailItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _RailButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.item.label,
          preferBelow: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HsColors.radiusPill),
              color: widget.isSelected
                  ? HsColors.glassFillStrong
                  : _hovered
                      ? HsColors.glassFill
                      : Colors.transparent,
              border: widget.isSelected
                  ? Border.all(
                      color: HsColors.glassStroke,
                      width: 0.5,
                    )
                  : null,
            ),
            child: Icon(
              widget.item.icon,
              size: 22,
              color: widget.isSelected
                  ? HsColors.accentPrimary
                  : HsColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
