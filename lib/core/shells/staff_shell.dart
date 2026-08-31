import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/access/gym_permissions.dart';
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
import '../../features/staff/settings/gym_branches_sheet.dart';
import '../../features/staff/settings/gym_code_sheet.dart';
import '../../features/staff/settings/settings_screen.dart';
import '../../shared/widgets/redesign.dart';
import '../../shared/widgets/responsive_content.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../theme/app_icons.dart';

// Sheet-opening items use a non-route key (never matches a real
// GoRouterState.matchedLocation) so they're never highlighted as "active"
// and never intercepted by the route-based visibility switch below.
const _kMoreItems = [
  _MoreItem(
    icon: AppIcons.personAdd,
    label: 'Leads',
    route: '/staff/leads',
  ),
  _MoreItem(
    icon: AppIcons.calendarToday,
    label: 'Batches',
    route: '/staff/classes',
  ),
  _MoreItem(
    icon: AppIcons.fitness,
    label: 'Workout plans',
    route: '/staff/workout-plans',
  ),
  _MoreItem(
    icon: AppIcons.restaurant,
    label: 'Diet plans',
    route: '/staff/diet-plans',
  ),
  _MoreItem(
    icon: AppIcons.campaign,
    label: 'Reminders',
    route: '/staff/reminders',
  ),
  _MoreItem(
    icon: AppIcons.manageAccounts,
    label: 'Staff & roles',
    route: '/staff/staff',
  ),
  // Badge keys track whats_new.dart: a feature announced there gets one here,
  // and the previous release's keys get `enabled = false` in coachmark_config
  // at the same time. Retiring a badge is a SQL flip, never an app update —
  // which is how the Expenses badge outlived the feature by months.
  _MoreItem(
    icon: AppIcons.business,
    label: 'Gym branches',
    route: '#gym-branches',
    sheetBuilder: _buildGymBranchesSheet,
    newBadgeKey: 'feature_gym_branches',
  ),
  _MoreItem(
    icon: AppIcons.fingerprint,
    label: 'Biometric device',
    route: '#biometric-device',
    sheetBuilder: _buildBiometricDeviceSheet,
    newBadgeKey: 'feature_biometric_device',
  ),
  _MoreItem(
    icon: AppIcons.qrCode,
    label: 'Member signup code',
    route: '#gym-code',
    sheetBuilder: _buildGymCodeSheet,
    newBadgeKey: 'feature_member_signup_code',
  ),
  _MoreItem(
    icon: AppIcons.barChart,
    label: 'Reports',
    route: '/staff/reports',
  ),
  _MoreItem(
    icon: AppIcons.calendarMonth,
    label: 'Attendance calendar',
    route: '/staff/attendance-calendar',
  ),
  _MoreItem(
    icon: AppIcons.download,
    label: 'Export data',
    route: '/staff/exports',
  ),
  _MoreItem(
    icon: AppIcons.history,
    label: 'Activity log',
    route: '/staff/activity-log',
  ),
  _MoreItem(
    icon: AppIcons.receipt,
    label: 'Expenses',
    route: '/staff/expenses',
    newBadgeKey: 'feature_expenses',
  ),
  _MoreItem(
    icon: AppIcons.settings,
    label: 'Settings',
    route: '/staff/settings',
  ),
];

Widget _buildGymBranchesSheet(BuildContext context) => const GymBranchesSheet();
Widget _buildBiometricDeviceSheet(BuildContext context) =>
    const BiometricDeviceSheet();
Widget _buildGymCodeSheet(BuildContext context) => const GymCodeSheet();

List<_MoreItem> _visibleMoreItemsFor(
  GymPermissions permissions,
  String? role,
) => _kMoreItems.where((item) {
  bool can(GymModule module, [GymAction action = GymAction.view]) =>
      permissions.can(module, action);

  return switch (item.route) {
    '/staff/classes' => can(GymModule.batches),
    '/staff/leads' => can(GymModule.leads),
    '/staff/workout-plans' => can(GymModule.pt),
    '/staff/diet-plans' => can(GymModule.services),
    '/staff/reminders' => can(GymModule.settings),
    '/staff/staff' => can(GymModule.staff),
    '#gym-branches' ||
    '#biometric-device' ||
    '#gym-code' => can(GymModule.settings),
    '/staff/reports' => can(GymModule.reports),
    '/staff/attendance-calendar' => can(GymModule.attendance),
    '/staff/exports' => can(GymModule.reports, GymAction.export),
    '/staff/activity-log' =>
      (role == 'owner' || role == 'manager') && can(GymModule.reports),
    '/staff/expenses' => can(GymModule.expenses),
    '/staff/settings' => can(GymModule.settings),
    _ => true,
  };
}).toList();

class StaffShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const StaffShell({super.key, required this.shell});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell>
    with WidgetsBindingObserver {
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
    final role = profile?['role'] as String?;
    final permissions =
        ref.watch(staffPermissionsProvider).valueOrNull ??
        GymPermissions.roleDefaults(role);

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
      builder: (context) {
        final isWide = ResponsiveContent.isWide(context);
        final content = Column(
          children: [
            if (gym != null) PlanExpiryBanner(gym: gym),
            Expanded(child: ResponsiveContent(child: shell)),
          ],
        );

        return Scaffold(
          body: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StaffSideNav(
                      shell: shell,
                      profile: profile,
                      permissions: permissions,
                      onSignOut: onSignOut,
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: isWide
              ? null
              : _StaffBottomNav(
                  shell: shell,
                  profile: profile,
                  permissions: permissions,
                  onSignOut: onSignOut,
                ),
        );
      },
    );
  }
}

// ── Side nav (web, wide viewport) ───────────────────────────────────────────

class _StaffSideNav extends StatelessWidget {
  final StatefulNavigationShell shell;
  final Map<String, dynamic>? profile;
  final GymPermissions permissions;
  final VoidCallback onSignOut;
  const _StaffSideNav({
    required this.shell,
    required this.profile,
    required this.permissions,
    required this.onSignOut,
  });

  String? get role => profile?['role'] as String?;
  bool get _showMembers => permissions.can(GymModule.members, GymAction.view);
  bool get _showMoney => permissions.can(GymModule.payments, GymAction.view);
  bool get _showCheckIn =>
      permissions.can(GymModule.attendance, GymAction.view);

  @override
  Widget build(BuildContext context) {
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final gymName = (gym?['name'] as String?) ?? 'Gym';
    final moreItems = _visibleMoreItemsFor(permissions, role);
    final moreActive = moreItems.any(
      (m) => GoRouterState.of(context).matchedLocation.startsWith(m.route),
    );

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                gymName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SideNavItem(
                    icon: AppIcons.home,
                    activeIcon: AppIcons.homeActive,
                    label: 'Home',
                    active: shell.currentIndex == 0 && !moreActive,
                    onTap: () => shell.goBranch(
                      0,
                      initialLocation: shell.currentIndex == 0,
                    ),
                  ),
                  if (_showMembers)
                    _SideNavItem(
                      icon: AppIcons.people,
                      activeIcon: AppIcons.peopleActive,
                      label: 'Members',
                      active: shell.currentIndex == 1 && !moreActive,
                      onTap: () => shell.goBranch(
                        1,
                        initialLocation: shell.currentIndex == 1,
                      ),
                    ),
                  if (_showCheckIn)
                    _SideNavItem(
                      icon: AppIcons.qrScanner,
                      activeIcon: AppIcons.qrScanner,
                      label: 'Check-in',
                      active: shell.currentIndex == 3 && !moreActive,
                      onTap: () => shell.goBranch(
                        3,
                        initialLocation: shell.currentIndex == 3,
                      ),
                    ),
                  if (_showMoney)
                    _SideNavItem(
                      icon: AppIcons.payments,
                      activeIcon: AppIcons.paymentsActive,
                      label: 'Money',
                      active: shell.currentIndex == 2 && !moreActive,
                      onTap: () => shell.goBranch(
                        2,
                        initialLocation: shell.currentIndex == 2,
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Divider(height: 1, color: AppTheme.border),
                  ),
                  for (final item in moreItems)
                    _SideNavItem(
                      icon: item.icon,
                      activeIcon: item.icon,
                      label: item.label,
                      active:
                          item.sheetBuilder == null &&
                          GoRouterState.of(
                            context,
                          ).matchedLocation.startsWith(item.route),
                      onTap: () {
                        if (item.sheetBuilder != null) {
                          showAdaptiveSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: item.sheetBuilder!,
                          );
                        } else {
                          context.push(item.route);
                        }
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _SideNavItem(
                icon: AppIcons.logout,
                activeIcon: AppIcons.logout,
                label: 'Sign out',
                active: false,
                onTap: onSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SideNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              active ? activeIcon : icon,
              size: 19,
              color: active ? AppTheme.accent : AppTheme.inkSoft,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppTheme.accent : AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────────────────────

class _StaffBottomNav extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  final Map<String, dynamic>? profile;
  final GymPermissions permissions;
  final VoidCallback onSignOut;
  const _StaffBottomNav({
    required this.shell,
    required this.profile,
    required this.permissions,
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
      icon: AppIcons.home,
      activeIcon: AppIcons.homeActive,
      label: 'Home',
      index: 0,
    ),
    _Tab(
      icon: AppIcons.people,
      activeIcon: AppIcons.peopleActive,
      label: 'Members',
      index: 1,
    ),
  ];
  static const _moneyTab = _Tab(
    icon: AppIcons.payments,
    activeIcon: AppIcons.paymentsActive,
    label: 'Money',
    index: 2,
  );
  static const int _checkInIndex = 3;

  bool get _showMembers =>
      widget.permissions.can(GymModule.members, GymAction.view);
  bool get _showMoney =>
      widget.permissions.can(GymModule.payments, GymAction.view);
  bool get _showCheckIn =>
      widget.permissions.can(GymModule.attendance, GymAction.view);

  List<_MoreItem> get _visibleMoreItems =>
      _visibleMoreItemsFor(widget.permissions, widget.role);

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
        if (key == 'staff_nav_members' && !_showMembers) continue;
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

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      body: 'You can sign back in anytime.',
      confirmLabel: 'Sign out',
      icon: AppIcons.logout,
    );
    if (ok == true) widget.onSignOut();
  }

  bool _moreActive(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    return _visibleMoreItems.any((m) => loc.startsWith(m.route));
  }

  void _openMoreSheet(BuildContext context) {
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final items = _visibleMoreItems;
    showAdaptiveSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        items: items,
        currentRoute: currentRoute,
        profile: widget.profile,
        onTap: (item) {
          Navigator.of(context).pop();
          if (item.sheetBuilder != null) {
            showAdaptiveSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: item.sheetBuilder!,
            );
          } else {
            context.push(item.route);
          }
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
            ..._leftTabs
                .where((tab) => tab.index != 1 || _showMembers)
                .map((tab) => _branchTab(context, tab, moreActive)),
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
                icon: AppIcons.menu,
                activeIcon: AppIcons.menu,
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

  /// It used to be a 54px disc raised out of the bar via an OverflowBox. That
  /// looked like a bump sitting on the content behind it, and worse: Flutter
  /// doesn't hit-test outside a parent's bounds, so the protruding top half was
  /// dead to taps — on the most-used button in the app. It now sits inside the
  /// bar and shares the row's width like every other tab.
  // No Expanded here — the call site already wraps this in one (via Showcase),
  // and a second would not be a direct child of a Flex.
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
              color: active ? AppTheme.accentDark : AppTheme.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              AppIcons.qrScanner,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 3),
          // The tile stays teal because check-in is a standing action, but
          // the label follows the same active/inactive rule as every other
          // tab — otherwise two tabs read as selected at once.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Check-in',
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
  final void Function(_MoreItem item) onTap;
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
    // Grouped by what the owner is trying to do, in the order they think
    // about it — bring people in, run the day, program members, set up, look
    // back — instead of one flat list of every feature.
    final groups = <String, List<_MoreItem>>{
      'Grow': [],
      'Run the gym': [],
      'Member programs': [],
      'Setup': [],
      'Insights': [],
    };
    for (final item in items) {
      final group = switch (item.route) {
        '/staff/leads' || '/staff/reminders' => 'Grow',
        '/staff/classes' ||
        '/staff/staff' ||
        '/staff/expenses' ||
        '/staff/attendance-calendar' => 'Run the gym',
        '/staff/workout-plans' || '/staff/diet-plans' => 'Member programs',
        '/staff/reports' ||
        '/staff/exports' ||
        '/staff/activity-log' => 'Insights',
        _ => 'Setup',
      };
      groups[group]!.add(item);
    }

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
                      AppIcons.logout,
                      size: 18,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Group management tools by the owner's intent instead of making one
          // long, equally weighted list.
          if (items.isNotEmpty)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: 8 + bottomPadding),
                children: [
                  for (final entry in groups.entries)
                    if (entry.value.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: AppTheme.kicker,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: AppTheme.cardDecoration(radius: 14),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < entry.value.length;
                              index++
                            ) ...[
                              if (index > 0)
                                const Divider(
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                  color: AppTheme.border,
                                ),
                              _MoreRow(
                                item: entry.value[index],
                                onTap: () => onTap(entry.value[index]),
                              ),
                            ],
                          ],
                        ),
                      ),
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
            const Icon(AppIcons.chevronRight, size: 20, color: AppTheme.inkHint),
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

  /// A real go_router route for pushed items, or a non-route `#key` for
  /// items that open a bottom sheet instead (see [sheetBuilder]) — a `#`
  /// prefix never matches GoRouterState.matchedLocation, so it's never
  /// highlighted as active and never intercepted by go_router.
  final String route;

  /// When set, tapping this item opens this builder in a bottom sheet
  /// instead of pushing [route].
  final WidgetBuilder? sheetBuilder;

  /// Coachmark key gating a "NEW" badge — reuses the same per-user "seen"
  /// tracking as the tour tooltips. Null = no badge for this item.
  final String? newBadgeKey;
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.route,
    this.sheetBuilder,
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
