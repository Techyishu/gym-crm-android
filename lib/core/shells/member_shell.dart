import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/responsive_content.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';

class MemberShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MemberShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ResponsiveContent(child: shell),
      bottomNavigationBar: _MemberBottomNav(shell: shell),
    );
  }
}

class _MemberBottomNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _MemberBottomNav({required this.shell});

  // One tab per shell branch, in branch order — the QR code is a raised
  // action in the middle, not a tab, because it opens a pushed page rather
  // than switching branches. Mapping tabs 1:1 to branches is what keeps the
  // highlight honest: exactly one tab is ever active.
  static const _tabs = [
    _Tab(
      icon: AppIcons.home,
      activeIcon: AppIcons.homeActive,
      label: 'Home',
      index: 0,
    ),
    _Tab(
      icon: AppIcons.receipt,
      activeIcon: AppIcons.receiptActive,
      label: 'Payments',
      index: 1,
    ),
    _Tab(
      icon: AppIcons.fitness,
      activeIcon: AppIcons.fitnessActive,
      label: 'Workout',
      index: 2,
    ),
    _Tab(
      icon: AppIcons.restaurant,
      activeIcon: AppIcons.restaurant,
      label: 'Diet',
      index: 3,
    ),
  ];

  /// The QR button sits after this many tabs — the middle of the row. These
  /// indices are shell branch indices, so they shifted down by one when the
  /// Bookings branch was removed from the router.
  static const _qrSlot = 2;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final children = <Widget>[];
    for (var i = 0; i < _tabs.length; i++) {
      if (i == _qrSlot)
        children.add(_QrButton(onTap: () => context.push('/portal/qr')));
      final tab = _tabs[i];
      children.add(
        _NavTab(
          icon: tab.icon,
          activeIcon: tab.activeIcon,
          label: tab.label,
          active: shell.currentIndex == tab.index,
          onTap: () => shell.goBranch(
            tab.index,
            initialLocation: tab.index == shell.currentIndex,
          ),
        ),
      );
    }

    return Container(
      height: 66 + bottomPadding,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(children: children),
      ),
    );
  }
}

/// Teal tile for "show my QR". Always teal — it is a standing action, never a
/// destination — and it carries no active state, so it can't read as selected
/// while another tab is.
///
/// It used to be a 54px disc raised out of the bar via an OverflowBox. That
/// looked like a bump sitting on the content behind it, and worse: Flutter
/// doesn't hit-test outside a parent's bounds, so the protruding top half of
/// the disc was dead to taps — only the sliver still inside the bar responded.
/// It now sits inside the bar and shares the row's width like every other tab,
/// so the whole thing is tappable and it flexes with the screen.
class _QrButton extends StatelessWidget {
  final VoidCallback onTap;
  const _QrButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(AppIcons.qrCode, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 3),
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'My QR',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkHint,
                ),
              ),
            ),
          ],
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
              color: active ? AppTheme.accent : AppTheme.inkHint,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppTheme.accent : AppTheme.inkHint,
                ),
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
  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
  });
}
