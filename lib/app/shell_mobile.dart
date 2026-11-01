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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        borderRadius: BorderRadius.circular(HsColors.radiusPill),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (int i = 0; i < _navItems.length; i++)
              _NavBarItem(
                item: _navItems[i],
                isSelected: i == selectedIndex,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(HsColors.radiusPill),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withAlpha(60),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: Icon(
          isSelected ? item.activeIcon : item.icon,
          size: 22,
          color: isSelected ? HsColors.bgBase : HsColors.textTertiary,
        ),
      ),
    );
  }
}
