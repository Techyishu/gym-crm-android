import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/access/gym_permissions.dart';
import 'add_fab.dart';
import '../../core/billing/billing_access.dart';
import '../../core/providers/revenue_cat_provider.dart';
import '../../core/services/coachmark_service.dart';
import '../../core/services/onesignal_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/platform_info.dart';
import '../../core/widgets/plan_expiry_banner.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/staff/home/home_screen.dart';
import '../../features/staff/notifications/notifications_screen.dart';
import '../../features/staff/paywall/paywall_screen.dart';
import '../../shared/widgets/responsive_content.dart';
import '../theme/app_icons.dart';

// Branch indices — must match the StatefulShellRoute order in router.dart.
const _homeIndex = 0;
const _dashboardIndex = 1;
const _membersIndex = 2;
const _billingIndex = 3;
const _checkInIndex = 4;

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
      // Re-read the gym row so an expiry that happened while the app sat in
      // the background raises the paywall on resume. Android keeps processes
      // alive for days — without this the billing gate below only re-runs on
      // a cold start, so a lapsed gym could keep full access for a week.
      ref.invalidate(staffProfileProvider);
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

    final authNotifier = ref.read(authNotifierProvider.notifier);
    void onSignOut() => authNotifier.signOut();

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
          // One floating Add for the whole staff portal. It adapts to the
          // screen you are on (see AddFab); on wide layouts the side nav
          // already exposes everything, so it stays a phone affordance.
          floatingActionButton: isWide ? null : const AddFab(),
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
              : _StaffBottomNav(shell: shell, permissions: permissions),
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
    // Members already has its own nav row above.
    final moreItems = visibleStaffFeatures(
      permissions,
      role,
    ).where((f) => f.route != '/staff/members').toList();
    final moreActive = moreItems.any(
      (m) => GoRouterState.of(context).matchedLocation.startsWith(m.route),
    );
    Widget branchItem(
      int index,
      IconData icon,
      IconData activeIcon,
      String label,
    ) => _SideNavItem(
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      active: shell.currentIndex == index && !moreActive,
      onTap: () =>
          shell.goBranch(index, initialLocation: shell.currentIndex == index),
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
                  branchItem(
                    _homeIndex,
                    AppIcons.home,
                    AppIcons.homeActive,
                    'Home',
                  ),
                  branchItem(
                    _dashboardIndex,
                    AppIcons.showChart,
                    AppIcons.showChart,
                    'Dashboard',
                  ),
                  if (_showMembers)
                    branchItem(
                      _membersIndex,
                      AppIcons.people,
                      AppIcons.peopleActive,
                      'Members',
                    ),
                  if (_showCheckIn)
                    branchItem(
                      _checkInIndex,
                      AppIcons.qrScanner,
                      AppIcons.qrScanner,
                      'Check-in',
                    ),
                  if (_showMoney)
                    branchItem(
                      _billingIndex,
                      AppIcons.payments,
                      AppIcons.paymentsActive,
                      'Money',
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
                      onTap: () => openStaffFeature(context, item),
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
// Home · Dashboard · Members. Money, Check-in and everything the old More
// sheet held open from Home cards instead.

class _StaffBottomNav extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  final GymPermissions permissions;
  const _StaffBottomNav({required this.shell, required this.permissions});

  @override
  ConsumerState<_StaffBottomNav> createState() => _StaffBottomNavState();
}

class _StaffBottomNavState extends ConsumerState<_StaffBottomNav> {
  final _membersTourKey = GlobalKey();
  bool _tourTriggered = false;

  bool get _showMembers =>
      widget.permissions.can(GymModule.members, GymAction.view);

  // One-step spotlight on Members, once per user. Marks it seen right away so
  // a killed app mid-tour won't re-show it.
  void _maybeStartTour(CoachmarkService service) {
    if (_tourTriggered) return;
    _tourTriggered = true;

    try {
      if (!_showMembers || !service.shouldShow('staff_nav_members')) return;
      service.markSeen('staff_nav_members');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          ShowCaseWidget.of(context).startShowCase([_membersTourKey]);
        } catch (_) {
          // Never let the tour break the dashboard.
        }
      });
    } catch (_) {
      // Never let the tour break the dashboard.
    }
  }

  Widget _tab(int index, IconData icon, IconData activeIcon, String label) {
    final current = widget.shell.currentIndex;
    // Money and Check-in are opened from Home, so Home stays lit there.
    final active = index == _homeIndex
        ? current == _homeIndex ||
              current == _billingIndex ||
              current == _checkInIndex
        : current == index;
    return _NavTab(
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      active: active,
      onTap: () =>
          widget.shell.goBranch(index, initialLocation: index == current),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(coachmarkServiceProvider).whenData(_maybeStartTour);

    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
            _tab(_homeIndex, AppIcons.home, AppIcons.homeActive, 'Home'),
            _tab(
              _dashboardIndex,
              AppIcons.showChart,
              AppIcons.showChart,
              'Dashboard',
            ),
            if (_showMembers)
              Expanded(
                child: Showcase(
                  key: _membersTourKey,
                  description: 'See and manage all your gym members here.',
                  child: Row(
                    children: [
                      _tab(
                        _membersIndex,
                        AppIcons.people,
                        AppIcons.peopleActive,
                        'Members',
                      ),
                    ],
                  ),
                ),
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
