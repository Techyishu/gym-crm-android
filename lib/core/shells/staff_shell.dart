import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/access/role_access.dart';
import '../../core/billing/billing_access.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/staff/paywall/paywall_screen.dart';

class StaffShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const StaffShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(staffProfileProvider);

    // First-time load: show a blank screen for the brief moment before data arrives.
    if (profileAsync.isLoading && !profileAsync.hasValue) {
      return const Scaffold(backgroundColor: AppTheme.background);
    }

    final profile = profileAsync.valueOrNull;
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final role = profile?['role'] as String?;

    // Only gate when we have a definitive answer.
    if (profileAsync.hasValue && !hasActiveBillingAccess(gym)) {
      return const PaywallScreen();
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: _StaffBottomNav(shell: shell, role: role),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

class _StaffBottomNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  final String? role;
  const _StaffBottomNav({required this.shell, required this.role});

  static const _allPrimaryTabs = [
    _Tab(icon: Icons.home_outlined,            activeIcon: Icons.home,              label: 'Home',     index: 0),
    _Tab(icon: Icons.people_outline,           activeIcon: Icons.people,            label: 'Members',  index: 1),
    _Tab(icon: Icons.receipt_long_outlined,    activeIcon: Icons.receipt_long,      label: 'Billing',  index: 2),
    _Tab(icon: Icons.qr_code_scanner_outlined, activeIcon: Icons.qr_code_scanner,  label: 'Check-in', index: 3),
  ];

  static const _allMoreItems = [
    _MoreItem(icon: Icons.person_add_outlined,      label: 'Leads',    route: '/staff/leads'),
    _MoreItem(icon: Icons.calendar_today_outlined,  label: 'Batches',  route: '/staff/classes'),
    _MoreItem(icon: Icons.chat_bubble_outline,      label: 'Messages', route: '/staff/communications'),
    _MoreItem(icon: Icons.manage_accounts_outlined, label: 'Staff',    route: '/staff/staff'),
    _MoreItem(icon: Icons.bar_chart_outlined,       label: 'Reports',  route: '/staff/reports'),
    _MoreItem(icon: Icons.settings_outlined,        label: 'Settings', route: '/staff/settings'),
  ];

  List<_Tab> get _visibleTabs => _allPrimaryTabs.where((tab) {
    if (tab.index == 2) return RoleAccess.canSeeBilling(role);
    if (tab.index == 3) return RoleAccess.canCheckIn(role);
    return true;
  }).toList();

  List<_MoreItem> get _visibleMoreItems => _allMoreItems.where((item) {
    if (item.route == '/staff/classes') return RoleAccess.canSeeBatches(role);
    if (item.route == '/staff/leads') return RoleAccess.canSeeLeads(role);
    if (item.route == '/staff/communications') return RoleAccess.canSeeCommunications(role);
    if (item.route == '/staff/staff') return RoleAccess.canSeeStaff(role);
    if (item.route == '/staff/reports') return RoleAccess.canSeeReports(role);
    if (item.route == '/staff/settings') return RoleAccess.canSeeSettings(role);
    return true;
  }).toList();

  bool _moreActive(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    return _visibleMoreItems.any((m) => loc.startsWith(m.route));
  }

  void _openMoreSheet(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final items = _visibleMoreItems;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        items: items,
        currentRoute: currentRoute,
        onTap: (route) {
          Navigator.of(context).pop();
          context.push(route);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final moreActive = _moreActive(context);
    final tabs = _visibleTabs;
    final moreItems = _visibleMoreItems;

    return Container(
      height: 60 + bottomPadding,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: [
            ...tabs.map((tab) {
              final active = shell.currentIndex == tab.index && !moreActive;
              return _NavTab(
                icon: tab.icon,
                activeIcon: tab.activeIcon,
                label: tab.label,
                active: active,
                onTap: () => shell.goBranch(
                  tab.index,
                  initialLocation: tab.index == shell.currentIndex,
                ),
              );
            }),
            if (moreItems.isNotEmpty)
              _NavTab(
                icon: Icons.more_horiz,
                activeIcon: Icons.more_horiz,
                label: 'More',
                active: moreActive,
                onTap: () => _openMoreSheet(context),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Nav tab ───────────────────────────────────────────────────────────────────

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

// ── More bottom sheet ─────────────────────────────────────────────────────────

class _MoreSheet extends StatelessWidget {
  final List<_MoreItem> items;
  final String currentRoute;
  final void Function(String route) onTap;

  const _MoreSheet({
    required this.items,
    required this.currentRoute,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Text(
                  'More',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20, color: AppTheme.inkSoft),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          // 3-column grid
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + bottomPadding),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: items.map((item) {
                final active = currentRoute.startsWith(item.route);
                return GestureDetector(
                  onTap: () => onTap(item.route),
                  child: Container(
                    decoration: BoxDecoration(
                      color: active ? AppTheme.activeBg : const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 24,
                          color: active ? AppTheme.ink : AppTheme.statusNeutral,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? AppTheme.ink : AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _Tab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  const _Tab({required this.icon, required this.activeIcon, required this.label, required this.index});
}

class _MoreItem {
  final IconData icon;
  final String label;
  final String route;
  const _MoreItem({required this.icon, required this.label, required this.route});
}
