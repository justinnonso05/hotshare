import 'package:flutter/material.dart';

import '../ui/design_system/design_system.dart';

/// Bottom navigation item descriptor.
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

const _navItems = [
  _NavItem(
    icon: Icons.wifi_tethering_rounded,
    activeIcon: Icons.wifi_tethering_rounded,
    label: 'Nearby',
  ),
  _NavItem(
    icon: Icons.history_rounded,
    activeIcon: Icons.history_rounded,
    label: 'History',
  ),
  _NavItem(
    icon: Icons.devices_rounded,
    activeIcon: Icons.devices_rounded,
    label: 'Devices',
  ),
  _NavItem(
    icon: Icons.settings_rounded,
    activeIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];

/// Mobile shell wrapping the 4 main screens with a floating glass pill nav bar.
class MobileShell extends StatefulWidget {
  final List<Widget> pages;

  const MobileShell({super.key, required this.pages});

  @override
  State<MobileShell> createState() => MobileShellState();
}

class MobileShellState extends State<MobileShell> {
  int _index = 0;

  void navigateTo(int index) {
    if (index >= 0 && index < widget.pages.length) {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: widget.pages,
      ),
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: bottomPadding + 16,
      ),
      child: GlassSurface(
        padding: const EdgeInsets.all(6),
        borderRadius: BorderRadius.circular(HsColors.radiusPill),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final count = _navItems.length;
            final itemWidth = totalWidth / count;
            final pillWidth = itemWidth * 0.84;

            return SizedBox(
              height: 48,
              child: Stack(
                children: [
                  // Smooth sliding liquid bubble
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.fastOutSlowIn,
                    left: selectedIndex * itemWidth + (itemWidth - pillWidth) / 2,
                    top: 2,
                    bottom: 2,
                    width: pillWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(HsColors.radiusPill),
                      ),
                    ),
                  ),

                  // Interactive navigation items
                  Row(
                    children: [
                      for (int i = 0; i < count; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => onTap(i),
                            behavior: HitTestBehavior.opaque,
                            child: Center(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 200),
                                scale: i == selectedIndex ? 1.05 : 0.95,
                                child: Icon(
                                  i == selectedIndex
                                      ? _navItems[i].activeIcon
                                      : _navItems[i].icon,
                                  size: 22,
                                  color: i == selectedIndex
                                      ? HsColors.bgBase
                                      : HsColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
