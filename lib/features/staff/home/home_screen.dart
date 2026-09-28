import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/access/role_access.dart';
import '../../../core/billing/billing_access.dart';
import '../../../core/services/coachmark_service.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/services/review_prompt.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/new_design_back_button.dart';
import '../../../shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import '../dashboard/money_dashboard_screen.dart'
    show dashboardDataProvider, SetupChecklist, BirthdaysToday;
import '../members/members_screen.dart' show showAddMemberSheet;
import '../notifications/notifications_screen.dart';
import '../settings/gym_branches_sheet.dart';
import '../settings/gym_code_sheet.dart';
import '../settings/settings_screen.dart';

// ── Feature list ──────────────────────────────────────────────────────────────
// Everything the old More sheet held, plus Plans. Home shows these as cards;
// the wide-layout side nav lists them too.

/// One feature a staff member can open from Home.
class StaffFeature {
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

  /// Home section this card sits under.
  final String group;

  const StaffFeature({
    required this.icon,
    required this.label,
    required this.route,
    required this.group,
    this.sheetBuilder,
    this.newBadgeKey,
  });
}

// Badge keys track whats_new.dart: a feature announced there gets one here,
// and the previous release's keys get `enabled = false` in coachmark_config
// at the same time. Retiring a badge is a SQL flip, never an app update —
// which is how the Expenses badge outlived the feature by months.
const kStaffFeatures = [
  StaffFeature(
    icon: AppIcons.people,
    label: 'Members',
    route: '/staff/members',
    group: 'Run the gym',
  ),
  StaffFeature(
    icon: AppIcons.cardMembership,
    label: 'Plans',
    route: '/staff/plans',
    group: 'Run the gym',
  ),
  StaffFeature(
    icon: AppIcons.receipt,
    label: 'Expenses',
    route: '/staff/expenses',
    group: 'Run the gym',
    newBadgeKey: 'feature_expenses',
  ),
  StaffFeature(
    icon: AppIcons.fingerprint,
    label: 'Biometric device',
    route: '#biometric-device',
    group: 'Run the gym',
    sheetBuilder: _buildBiometricDeviceSheet,
    newBadgeKey: 'feature_biometric_device',
  ),
  StaffFeature(
    icon: AppIcons.calendarMonth,
    label: 'Attendance calendar',
    route: '/staff/attendance-calendar',
    group: 'Run the gym',
  ),
  StaffFeature(
    icon: AppIcons.manageAccounts,
    label: 'Staff & roles',
    route: '/staff/staff',
    group: 'Run the gym',
  ),
  StaffFeature(
    icon: AppIcons.personAdd,
    label: 'Leads',
    route: '/staff/leads',
    group: 'Grow',
  ),
  StaffFeature(
    icon: AppIcons.campaign,
    label: 'Reminders',
    route: '/staff/reminders',
    group: 'Grow',
  ),
  StaffFeature(
    icon: AppIcons.qrCode,
    label: 'Member signup code',
    route: '#gym-code',
    group: 'Grow',
    sheetBuilder: _buildGymCodeSheet,
    newBadgeKey: 'feature_member_signup_code',
  ),
  StaffFeature(
    icon: AppIcons.calendarToday,
    label: 'Batches',
    route: '/staff/classes',
    group: 'Member programs',
  ),
  StaffFeature(
    icon: AppIcons.fitness,
    label: 'Workout plans',
    route: '/staff/workout-plans',
    group: 'Member programs',
  ),
  StaffFeature(
    icon: AppIcons.restaurant,
    label: 'Diet plans',
    route: '/staff/diet-plans',
    group: 'Member programs',
  ),
  StaffFeature(
    icon: AppIcons.barChart,
    label: 'Reports',
    route: '/staff/reports',
    group: 'Insights',
  ),
  StaffFeature(
    icon: AppIcons.download,
    label: 'Export data',
    route: '/staff/exports',
    group: 'Insights',
  ),
  StaffFeature(
    icon: AppIcons.history,
    label: 'Activity log',
    route: '/staff/activity-log',
    group: 'Insights',
  ),
  StaffFeature(
    icon: AppIcons.business,
    label: 'Gym branches',
    route: '#gym-branches',
    group: 'Setup',
    sheetBuilder: _buildGymBranchesSheet,
    newBadgeKey: 'feature_gym_branches',
  ),
  StaffFeature(
    icon: AppIcons.settings,
    label: 'Settings',
    route: '/staff/settings',
    group: 'Setup',
  ),
];

Widget _buildGymBranchesSheet(BuildContext context) => const GymBranchesSheet();
Widget _buildBiometricDeviceSheet(BuildContext context) =>
    const BiometricDeviceSheet();
Widget _buildGymCodeSheet(BuildContext context) => const GymCodeSheet();

List<StaffFeature> visibleStaffFeatures(
  GymPermissions permissions,
  String? role,
) => kStaffFeatures.where((item) {
  bool can(GymModule module, [GymAction action = GymAction.view]) =>
      permissions.can(module, action);

  return switch (item.route) {
    '/staff/members' => can(GymModule.members),
    '/staff/plans' => can(GymModule.memberships),
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

/// Opens [item] the same way the old More sheet did: a sheet for `#` items,
/// a pushed route otherwise. Members is a nav tab, so it switches to it.
void openStaffFeature(BuildContext context, StaffFeature item) {
  if (item.sheetBuilder != null) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: item.sheetBuilder!,
    );
  } else if (item.route == '/staff/members') {
    context.go(item.route);
  } else {
    context.push(item.route);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Checklist and birthdays read the dashboard's cached data; refetch when
    // anything is added or collected elsewhere.
    gymDataChanged.addListener(_refresh);
    // Home is the first screen of every staff session, so this is "on app
    // open" — ReviewPrompt itself decides whether asking is due.
    unawaited(ReviewPrompt.maybeAskOnLaunch());
  }

  @override
  void dispose() {
    gymDataChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) ref.invalidate(dashboardDataProvider);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(staffProfileProvider).valueOrNull;
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    // Never blocks Home: sections below just appear once this loads.
    final data = ref.watch(dashboardDataProvider).valueOrNull;
    final birthdays = (data?['birthdays'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final memberCount = (data?['memberCount'] as int?) ?? 0;
    final planCount = (data?['planCount'] as int?) ?? 0;
    final allTimeCheckins = (data?['allTimeCheckins'] as int?) ?? 0;
    final showChecklist =
        data != null &&
        (memberCount < 3 || planCount == 0 || allTimeCheckins == 0);
    final role = profile?['role'] as String?;
    final permissions =
        ref.watch(staffPermissionsProvider).valueOrNull ??
        GymPermissions.roleDefaults(role);
    bool can(GymModule m, [GymAction a = GymAction.view]) =>
        permissions.can(m, a);

    final features = visibleStaffFeatures(permissions, role);
    final groups = <String, List<StaffFeature>>{};
    for (final f in features) {
      (groups[f.group] ??= []).add(f);
    }

    // Same four actions the dashboard's quick-action row opens.
    final canAddMember = can(GymModule.members, GymAction.add);
    final canCollect = can(GymModule.payments, GymAction.add);
    final canMoney = can(GymModule.payments);
    final canCheckIn = can(GymModule.attendance);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(dashboardDataProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom room for the shell's floating Add button.
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
            children: [
              _HomeHeader(
                profile: profile,
                showBilling: RoleAccess.canSeeBilling(role),
              ),
              const SizedBox(height: 16),
              if (showChecklist) ...[
                SetupChecklist(
                  gym: gym,
                  memberCount: memberCount,
                  planCount: planCount,
                  allTimeCheckins: allTimeCheckins,
                ),
                const SizedBox(height: 12),
              ],
              if (birthdays.isNotEmpty) ...[
                BirthdaysToday(members: birthdays),
                const SizedBox(height: 12),
              ],
              if (canMoney || canCheckIn) ...[
                Row(
                  children: [
                    if (canMoney)
                      Expanded(
                        child: _BigCard(
                          icon: AppIcons.payments,
                          label: 'Money',
                          hint: 'Dues, payments, invoices',
                          dark: true,
                          onTap: () => openWithReturn(context, '/staff/billing'),
                        ),
                      ),
                    if (canMoney && canCheckIn) const SizedBox(width: 10),
                    if (canCheckIn)
                      Expanded(
                        child: _BigCard(
                          icon: AppIcons.qrScanner,
                          label: 'Check-in',
                          hint: 'Scan or mark attendance',
                          onTap: () => openWithReturn(context, '/staff/check-in'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (canAddMember || canCollect) ...[
                Row(
                  children: [
                    if (canAddMember)
                      Expanded(
                        child: _ActionTile(
                          icon: AppIcons.personAdd,
                          label: 'Add member',
                          accent: true,
                          onTap: () => showAddMemberSheet(context),
                        ),
                      ),
                    if (canAddMember && canCollect) const SizedBox(width: 10),
                    if (canCollect)
                      Expanded(
                        child: _ActionTile(
                          icon: AppIcons.payments,
                          label: 'Collect payment',
                          onTap: () => openWithReturn(context, '/staff/billing'),
                        ),
                      ),
                  ],
                ),
              ],
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
                  child: Text(entry.key.toUpperCase(), style: AppTheme.kicker),
                ),
                _FeatureGrid(items: entry.value),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header (gym name · role · bell · sign out) ────────────────────────────────

class _HomeHeader extends ConsumerWidget {
  final Map<String, dynamic>? profile;
  final bool showBilling;
  const _HomeHeader({required this.profile, required this.showBilling});

  // Moved from the dashboard header: trial/plan status as a small tappable
  // line under the gym name, opening the subscription screen.
  static String _planLabel(Map<String, dynamic>? gym) {
    final plan = gym?['plan'] as String?;
    final daysLeft = planExpiryDaysRemaining(gym);
    final isTrial =
        gym?['trial_ends_at'] != null && gym?['plan_expires_at'] == null;

    if (isTrial) {
      return daysLeft != null
          ? (daysLeft <= 0
                ? 'Trial ends today'
                : 'Trial ends in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}')
          : 'Trial active';
    }
    final planName = plan != null && plan.isNotEmpty
        ? plan[0].toUpperCase() + plan.substring(1)
        : 'Free';
    return daysLeft != null
        ? '$planName plan · renews in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}'
        : '$planName plan';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final gymName = (gym?['name'] as String?) ?? 'My Gym';
    final fullName =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    final role = (profile?['role'] as String?) ?? '';
    final roleLabel = role.isEmpty
        ? ''
        : role[0].toUpperCase() + role.substring(1);
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    Widget squareButton({
      required IconData icon,
      required VoidCallback onTap,
      bool dot = false,
    }) => GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 21, color: AppTheme.ink),
          ),
          if (dot)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: AppTheme.statusDanger,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Same branch switcher the dashboard header opens.
              GestureDetector(
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const GymBranchesSheet(),
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        gymName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      AppIcons.expandMore,
                      size: 20,
                      color: AppTheme.inkSoft,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [fullName, roleLabel].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
              if (showBilling && gym != null) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => context.push('/staff/subscription'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        AppIcons.sell,
                        size: 13,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _planLabel(gym),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                      const Icon(
                        AppIcons.chevronRight,
                        size: 14,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        squareButton(
          icon: AppIcons.notifications,
          dot: unread > 0,
          onTap: () => context.push('/staff/notifications'),
        ),
        const SizedBox(width: 8),
        // Sign out used to live in the More sheet header. Settings is
        // permission-gated, so this is the one place every role can reach it.
        squareButton(
          icon: AppIcons.logout,
          onTap: () async {
            final ok = await showConfirmDialog(
              context,
              title: 'Sign out?',
              body: 'You can sign back in anytime.',
              confirmLabel: 'Sign out',
              icon: AppIcons.logout,
            );
            if (ok == true) {
              ref.read(authNotifierProvider.notifier).signOut();
            }
          },
        ),
      ],
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

class _BigCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool dark;
  final VoidCallback onTap;
  const _BigCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AppTheme.onDark : AppTheme.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 124,
        padding: const EdgeInsets.all(14),
        decoration: dark
            ? BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
              )
            : AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: dark ? AppTheme.darkInset : AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: dark ? AppTheme.mintOnDark : AppTheme.accent,
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: dark ? AppTheme.onDarkSoft : AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Same tile look as the dashboard's quick actions.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: accent
            ? BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(14),
              )
            : AppTheme.cardDecoration(radius: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: accent ? Colors.white : AppTheme.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent ? Colors.white : AppTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final List<StaffFeature> items;
  const _FeatureGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3 across on a phone; more on tablets/web so cards stay ~card-sized.
        final columns = (constraints.maxWidth / 130).floor().clamp(3, 6);
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _FeatureCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureCard extends ConsumerWidget {
  final StaffFeature item;
  const _FeatureCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = item.newBadgeKey;
    final coachmark = ref.watch(coachmarkServiceProvider).valueOrNull;
    final showBadge = key != null && (coachmark?.shouldShow(key) ?? false);

    return GestureDetector(
      onTap: () {
        if (key != null) coachmark?.markSeen(key);
        openStaffFeature(context, item);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 104,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
        decoration: AppTheme.cardDecoration(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(item.icon, size: 19, color: AppTheme.accent),
                ),
                const Spacer(),
                if (showBadge) const _NewBadge(),
              ],
            ),
            const Spacer(),
            Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Colors.white,
        ),
      ),
    );
  }
}
