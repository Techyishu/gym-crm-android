import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class MemberShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MemberShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: _MemberBottomNav(shell: shell),
    );
  }
}

class _MemberBottomNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _MemberBottomNav({required this.shell});

  static const _tabs = [
    _Tab(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', index: 0),
    _Tab(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today, label: 'Bookings', index: 1),
    _Tab(icon: Icons.receipt_outlined, activeIcon: Icons.receipt, label: 'Billing', index: 2),
    _Tab(icon: Icons.fitness_center_outlined, activeIcon: Icons.fitness_center, label: 'Workout', index: 3),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 60 + bottomPadding,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: _tabs.map((tab) {
            final active = shell.currentIndex == tab.index;
            return _NavTab(
              icon: tab.icon,
              activeIcon: tab.activeIcon,
              label: tab.label,
              active: active,
              onTap: () => shell.goBranch(tab.index, initialLocation: tab.index == shell.currentIndex),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 22,
              color: active ? AppTheme.ink : AppTheme.inkHint,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppTheme.ink : AppTheme.inkHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  const _Tab({required this.icon, required this.activeIcon, required this.label, required this.index});
}
