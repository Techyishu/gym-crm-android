import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/access/role_access.dart';
import '../../core/billing/billing_access.dart';
import '../../core/providers/revenue_cat_provider.dart';
import '../../core/services/coachmark_service.dart';
import '../../core/services/onesignal_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_info.dart';
import '../../core/widgets/plan_expiry_banner.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/staff/notifications/notifications_screen.dart';
import '../../features/staff/paywall/paywall_screen.dart';

class StaffShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const StaffShell({super.key, required this.shell});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The staff_notifications row lands the moment the push is sent, but the
    // bell badge/list are cached FutureProviders — nothing tells them to
    // refetch. Foreground push arrival and app resume are the two moments a
    // new row is most likely to exist, so refresh on both.
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();
      ref.invalidate(unreadNotificationCountProvider);
      ref.invalidate(staffNotificationsProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(unreadNotificationCountProvider);
      ref.invalidate(staffNotificationsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final profileAsync = ref.watch(staffProfileProvider);

    ref.listen(staffProfileProvider, (previous, next) {
      final gym = next.valueOrNull?['gyms'] as Map<String, dynamic>?;
      if (gym != null) OneSignalService.syncGymTags(gym);
    });

    // First-time load: show a blank screen for the brief moment before data arrives.
    if (profileAsync.isLoading && !profileAsync.hasValue) {
      return const Scaffold(backgroundColor: AppTheme.background);
    }

    final profile = profileAsync.valueOrNull;
    final gym = profile?['gyms'] as Map<String, dynamic>?;

    // Billing gate — iOS uses RevenueCat entitlement; Android uses Supabase plan data.
    if (profileAsync.hasValue) {
      final hasAccess = isIOS
          ? ref.watch(iosProAccessProvider) ||
                hasActiveBillingAccess(gym, ignoreTrial: true)
          : hasActiveBillingAccess(gym);
      if (!hasAccess) return const PaywallScreen();
    }

    void onSignOut() => ref.read(authNotifierProvider.notifier).signOut();

    return ShowCaseWidget(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            if (gym != null) PlanExpiryBanner(gym: gym),
            Expanded(child: shell),
          ],
        ),
        bottomNavigationBar: _StaffBottomNav(
          shell: shell,
          profile: profile,
          onSignOut: onSignOut,
        ),
      ),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

class _StaffBottomNav extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  final Map<String, dynamic>? profile;
  final VoidCallback onSignOut;
  const _StaffBottomNav({
    required this.shell,
    required this.profile,
    required this.onSignOut,
  });

  String? get role => profile?['role'] as String?;

  @override
  ConsumerState<_StaffBottomNav> createState() => _StaffBottomNavState();
}

class _StaffBottomNavState extends ConsumerState<_StaffBottomNav> {
  final _membersTourKey = GlobalKey();
  final _checkInTourKey = GlobalKey();
  final _moreTourKey = GlobalKey();
  bool _tourTriggered = false;

  // Visual order: Home · Members · [Check-in center button] · Money · More.
  // Branch indices stay tied to router branches (0 home, 1 members, 2 billing, 3 check-in).
  static const _leftTabs = [
    _Tab(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
      index: 0,
    ),
    _Tab(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Members',
      index: 1,
    ),
  ];
  static const _moneyTab = _Tab(
    icon: Icons.credit_card_outlined,
    activeIcon: Icons.credit_card,
    label: 'Billing',
    index: 2,
  );
  static const int _checkInIndex = 3;

  static const _allMoreItems = [
    _MoreItem(
      icon: Icons.person_add_outlined,
      label: 'Leads',
      route: '/staff/leads',
    ),
    _MoreItem(
      icon: Icons.calendar_today_outlined,
      label: 'Batches',
      route: '/staff/classes',
    ),
    _MoreItem(
      icon: Icons.fitness_center_outlined,
      label: 'Workout plans',
      route: '/staff/workout-plans',
    ),
    _MoreItem(
      icon: Icons.restaurant_menu_outlined,
      label: 'Diet plans',
      route: '/staff/diet-plans',
    ),
    _MoreItem(
      icon: Icons.notifications_outlined,
      label: 'Reminders',
      route: '/staff/reminders',
    ),
    _MoreItem(
      icon: Icons.manage_accounts_outlined,
      label: 'Staff & roles',
      route: '/staff/staff',
    ),
    _MoreItem(
      icon: Icons.bar_chart_outlined,
      label: 'Reports',
      route: '/staff/reports',
    ),
    _MoreItem(
      icon: Icons.receipt_long_outlined,
      label: 'Expenses',
      route: '/staff/expenses',
      newBadgeKey: 'feature_expenses',
    ),
    _MoreItem(
      icon: Icons.settings_outlined,
      label: 'Settings',
      route: '/staff/settings',
    ),
  ];

  bool get _showMoney => RoleAccess.canSeeBilling(widget.role);
  bool get _showCheckIn => RoleAccess.canCheckIn(widget.role);

  List<_MoreItem> get _visibleMoreItems => _allMoreItems.where((item) {
    if (item.route == '/staff/classes')
      return RoleAccess.canSeeBatches(widget.role);
    if (item.route == '/staff/leads')
      return RoleAccess.canSeeLeads(widget.role);
    if (item.route == '/staff/workout-plans')
      return RoleAccess.canManageWorkoutPlans(widget.role);
    if (item.route == '/staff/diet-plans')
      return RoleAccess.canManageDietPlans(widget.role);
    if (item.route == '/staff/reminders')
      return RoleAccess.canSeeCommunications(widget.role);
    if (item.route == '/staff/staff')
      return RoleAccess.canSeeStaff(widget.role);
    if (item.route == '/staff/reports')
      return RoleAccess.canSeeReports(widget.role);
    if (item.route == '/staff/expenses')
      return RoleAccess.canSeeExpenses(widget.role);
    if (item.route == '/staff/settings')
      return RoleAccess.canSeeSettings(widget.role);
    return true;
  }).toList();

  // Shows the 3-step spotlight tour once per user, the first time this nav
  // bar builds after the coach-mark data has loaded. Marks steps as seen
  // right away so a killed app mid-tour won't re-show it.
  void _maybeStartTour(CoachmarkService service) {
    if (_tourTriggered) return;
    _tourTriggered = true;

    try {
      const stepOrder = [
        'staff_nav_members',
        'staff_nav_checkin',
        'staff_nav_more',
      ];
      final keys = <GlobalKey>[];
      for (final key in stepOrder) {
        if (key == 'staff_nav_checkin' && !_showCheckIn) continue;
        if (!service.shouldShow(key)) continue;
        if (key == 'staff_nav_members') keys.add(_membersTourKey);
        if (key == 'staff_nav_checkin') keys.add(_checkInTourKey);
        if (key == 'staff_nav_more') keys.add(_moreTourKey);
        service.markSeen(key);
      }
      if (keys.isEmpty) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          ShowCaseWidget.of(context).startShowCase(keys);
        } catch (_) {
          // Never let the tour break the dashboard.
        }
      });
    } catch (_) {
      // Never let the tour break the dashboard.
    }
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onSignOut();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.statusDanger),
            ),
          ),
        ],
      ),
    );
  }

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
        profile: widget.profile,
        onTap: (route) {
          Navigator.of(context).pop();
          context.push(route);
        },
        onSignOut: () {
          Navigator.of(context).pop();
          _confirmSignOut(context);
        },
      ),
    );
  }

  Widget _branchTab(BuildContext context, _Tab tab, bool moreActive) {
    final active = widget.shell.currentIndex == tab.index && !moreActive;
    Widget tabWidget = _NavTab(
      icon: tab.icon,
      activeIcon: tab.activeIcon,
      label: tab.label,
      active: active,
      onTap: () => widget.shell.goBranch(
        tab.index,
        initialLocation: tab.index == widget.shell.currentIndex,
      ),
    );
    if (tab.index == 1) {
      tabWidget = Showcase(
        key: _membersTourKey,
        description: 'See and manage all your gym members here.',
        child: tabWidget,
      );
    }
    return tabWidget;
  }

  @override
  Widget build(BuildContext context) {
    final coachmarkAsync = ref.watch(coachmarkServiceProvider);
    coachmarkAsync.whenData(_maybeStartTour);

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final moreActive = _moreActive(context);
    final checkInActive =
        widget.shell.currentIndex == _checkInIndex && !moreActive;

    return Container(
      height: 66 + bottomPadding,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: [
            ..._leftTabs.map((tab) => _branchTab(context, tab, moreActive)),
            if (_showCheckIn)
              Expanded(
                child: Showcase(
                  key: _checkInTourKey,
                  description: 'Tap here to check in a member with QR scan.',
                  child: _CheckInButton(
                    active: checkInActive,
                    onTap: () => widget.shell.goBranch(
                      _checkInIndex,
                      initialLocation:
                          _checkInIndex == widget.shell.currentIndex,
                    ),
                  ),
                ),
              ),
            if (_showMoney) _branchTab(context, _moneyTab, moreActive),
            Showcase(
              key: _moreTourKey,
              description:
                  'Find Leads, Classes, Staff, Reports and Settings here.',
              child: _NavTab(
                icon: Icons.menu,
                activeIcon: Icons.menu,
                label: 'More',
                active: moreActive,
                onTap: () => _openMoreSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Center raised check-in button ─────────────────────────────────────────────

class _CheckInButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _CheckInButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: OverflowBox(
        maxHeight: 96,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: active ? AppTheme.accentDark : AppTheme.accent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33DF5B34),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check-in',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 6),
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
              color: active ? AppTheme.accent : AppTheme.inkHint,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppTheme.accent : AppTheme.inkHint,
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
  final Map<String, dynamic>? profile;
  final void Function(String route) onTap;
  final VoidCallback onSignOut;

  const _MoreSheet({
    required this.items,
    required this.currentRoute,
    required this.profile,
    required this.onTap,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final gymName = (gym?['name'] as String?) ?? 'Gym';
    final firstName = (profile?['first_name'] as String?) ?? '';
    final lastName = (profile?['last_name'] as String?) ?? '';
    final fullName = '$firstName $lastName'.trim();
    final role = (profile?['role'] as String?) ?? '';
    final roleLabel = role.isEmpty
        ? ''
        : role[0].toUpperCase() + role.substring(1);
    final initials = _initials(fullName.isEmpty ? gymName : fullName);

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
          // Header row: avatar, gym name + owner/role, sign-out
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mintOnDark,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gymName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          fullName,
                          roleLabel,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.inkSoft,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSignOut,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.logout,
                      size: 18,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Menu list
          if (items.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 8 + bottomPadding),
              child: Column(
                children: [
                  for (final item in items) ...[
                    const Divider(height: 1, color: AppTheme.border),
                    _MoreRow(item: item, onTap: () => onTap(item.route)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

class _MoreRow extends ConsumerWidget {
  final _MoreItem item;
  final VoidCallback onTap;
  const _MoreRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = item.newBadgeKey;
    final coachmark = ref.watch(coachmarkServiceProvider).valueOrNull;
    final showBadge = key != null && (coachmark?.shouldShow(key) ?? false);

    return InkWell(
      onTap: () {
        if (key != null) coachmark?.markSeen(key);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(item.icon, size: 22, color: AppTheme.ink),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 8),
                    const _NewBadge(),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppTheme.inkHint),
          ],
        ),
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
  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
  });
}

class _MoreItem {
  final IconData icon;
  final String label;
  final String route;

  /// Coachmark key gating a "NEW" badge — reuses the same per-user "seen"
  /// tracking as the tour tooltips. Null = no badge for this item.
  final String? newBadgeKey;
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.route,
    this.newBadgeKey,
  });
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}
