import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _memberCheckInsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return [];

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return [];

  final memberId = member['id'] as String;

  // Last 30 days rather than the last 10 rows — the attendance card needs a
  // full fortnight of days to draw the strip and count the streak.
  final since = DateTime.now().subtract(const Duration(days: 30));
  return await client
      .from('check_ins')
      .select('id, checked_in_at')
      .eq('member_id', memberId)
      .gte('checked_in_at', since.toIso8601String())
      .order('checked_in_at', ascending: false);
});

/// Today's booked session, if the member has one — the first row of the
/// canvas "Today" card.
final _todayBookingProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return null;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final rows = await client
      .from('bookings')
      .select(
        'status, class_sessions!inner(starts_at, capacity, classes(name))',
      )
      .eq('member_id', member['id'] as String)
      .neq('status', 'cancelled')
      .gte('class_sessions.starts_at', startOfDay.toIso8601String())
      .lt('class_sessions.starts_at', endOfDay.toIso8601String())
      .limit(1);

  final list = (rows as List).cast<Map<String, dynamic>>();
  return list.isEmpty ? null : list.first;
});

/// Active workout plan (first row) — summarised as "N exercises".
final _portalWorkoutProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return null;

  final rows = await client
      .from('workout_plans')
      .select()
      .eq('member_id', member['id'] as String)
      .order('created_at', ascending: false)
      .limit(1);

  final list = (rows as List).cast<Map<String, dynamic>>();
  return list.isEmpty ? null : list.first;
});

/// Active diet plan — summarised as "N kcal · M meals planned".
final _portalDietProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return null;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return null;

  final rows = await client
      .from('diet_plans')
      .select()
      .eq('member_id', member['id'] as String)
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(1);

  final list = (rows as List).cast<Map<String, dynamic>>();
  return list.isEmpty ? null : list.first;
});

/// Remaining balance across the member's open/partial invoices.
final _memberOutstandingProvider = FutureProvider<double>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return 0;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return 0;

  final rows = await client
      .from('invoices')
      .select('amount, payments(amount, status)')
      .eq('member_id', member['id'] as String)
      .inFilter('status', ['open', 'partial']);

  var total = 0.0;
  for (final row in (rows as List).cast<Map<String, dynamic>>()) {
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final paid = ((row['payments'] as List?) ?? const [])
        .where((p) => (p as Map)['status'] == 'succeeded')
        .fold<double>(
          0,
          (s, p) => s + ((p as Map)['amount'] as num).toDouble(),
        );
    total += (amount - paid).clamp(0, amount);
  }
  return total;
});

final _memberMonthCheckInsCountProvider = FutureProvider<int>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return 0;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return 0;

  final memberId = member['id'] as String;
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);

  final result = await client
      .from('check_ins')
      .select('id')
      .eq('member_id', memberId)
      .gte('checked_in_at', startOfMonth.toIso8601String())
      .count(CountOption.exact);

  return result.count;
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class PortalHomeScreen extends ConsumerWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(memberRecordProvider);
    final recentCheckins = ref.watch(_memberCheckInsProvider);
    final monthVisits = ref.watch(_memberMonthCheckInsCountProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async {
            ref.invalidate(memberRecordProvider);
            ref.invalidate(_memberCheckInsProvider);
            ref.invalidate(_memberMonthCheckInsCountProvider);
            ref.invalidate(_todayBookingProvider);
            ref.invalidate(_portalWorkoutProvider);
            ref.invalidate(_portalDietProvider);
            ref.invalidate(_memberOutstandingProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: member.when(
              loading: () => const _LoadingSkeleton(),
              error: (_, _) => StateMessage(
                icon: AppIcons.cloudOff,
                tint: AppTheme.statusDanger,
                tintBg: AppTheme.statusDangerBg,
                title: 'Could not load your profile',
                body: 'Check your connection, then pull down to retry.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(memberRecordProvider),
              ),
              data: (m) {
                if (m == null) {
                  return const StateMessage(
                    icon: AppIcons.personOff,
                    title: 'Profile not found',
                    body:
                        'Your gym has not linked this login to a member record '
                        'yet. Ask the front desk to check your details.',
                  );
                }

                final firstName = m['first_name'] as String? ?? 'Member';
                final status = m['status'] as String? ?? 'active';
                final memberships = (m['memberships'] as List?) ?? [];
                final currentMs = memberships.isNotEmpty
                    ? memberships.first as Map<String, dynamic>
                    : null;
                final plan =
                    currentMs?['membership_plans'] as Map<String, dynamic>?;

                final gymName =
                    (m['gyms'] as Map<String, dynamic>?)?['name'] as String? ??
                    '';
                final outstanding =
                    ref.watch(_memberOutstandingProvider).valueOrNull ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GreetingHeader(
                      firstName: firstName,
                      gymName: gymName,
                      onSignOut: () => _confirmSignOut(context, ref),
                    ),
                    const SizedBox(height: 16),
                    _MembershipStatusCard(
                      membership: currentMs,
                      plan: plan,
                      status: status,
                      outstanding: outstanding,
                    ),
                    const SizedBox(height: 16),
                    const _TodayCard(),
                    const SizedBox(height: 16),
                    _AttendanceCard(
                      monthVisitsAsync: monthVisits,
                      recentCheckinsAsync: recentCheckins,
                    ),
                    if (outstanding > 0) ...[
                      const SizedBox(height: 16),
                      _OutstandingAlert(amount: outstanding),
                    ],
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      body: 'You can sign back in anytime.',
      confirmLabel: 'Sign out',
      icon: AppIcons.logout,
    );
    if (ok == true) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
  }
}

// ─── Loading Skeleton ─────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (i) => Container(
          height: i == 0 ? 80 : 100,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ─── Greeting Header ──────────────────────────────────────────────────────────

class _GreetingHeader extends StatelessWidget {
  final String firstName;
  final String gymName;
  final VoidCallback onSignOut;

  const _GreetingHeader({
    required this.firstName,
    required this.gymName,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gymName.isNotEmpty)
                Text(
                  gymName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                'Hi $firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // The member shell has no Account tab, so the avatar carries sign-out.
        GestureDetector(
          onTap: onSignOut,
          behavior: HitTestBehavior.opaque,
          child: InitialsAvatar(name: firstName, size: 40),
        ),
      ],
    );
  }
}

// ─── Membership Status Card ───────────────────────────────────────────────────

class _MembershipStatusCard extends StatelessWidget {
  final Map<String, dynamic>? membership;
  final Map<String, dynamic>? plan;
  final String status;
  final double outstanding;

  const _MembershipStatusCard({
    required this.membership,
    required this.plan,
    required this.status,
    required this.outstanding,
  });

  @override
  Widget build(BuildContext context) {
    final planName = plan?['name'] as String? ?? 'Membership';
    final endsAt = membership?['ends_at'] as String?;
    final expiry = endsAt != null ? DateTime.tryParse(endsAt) : null;
    final daysLeft = expiry?.difference(DateTime.now()).inDays;

    final (pillBg, pillFg) = switch (status.toLowerCase()) {
      'active' => (AppTheme.darkCard2, AppTheme.mintOnDark),
      'expired' => (AppTheme.statusDangerBg, AppTheme.statusDanger),
      _ => (AppTheme.darkCard2, AppTheme.onDarkSoft),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.darkCardDecoration(radius: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status[0].toUpperCase() + status.substring(1),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: pillFg,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  membership == null ? 'No active membership' : planName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.onDark,
                  ),
                ),
                if (expiry != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    daysLeft != null && daysLeft >= 0
                        ? 'Valid till ${formatDateFromString(endsAt!)} · $daysLeft days left'
                        : 'Expired ${formatDateFromString(endsAt!)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.onDarkSoft,
                    ),
                  ),
                ],
                if (outstanding > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${formatCurrency(outstanding)} outstanding',
                    style: AppTheme.numberStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => context.push('/portal/qr'),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.onDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.qrCode, size: 46, color: AppTheme.darkCard),
                  SizedBox(height: 4),
                  Text(
                    'Show QR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkCard,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Today card (booking · workout · diet) ────────────────────────────────────

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(_todayBookingProvider).valueOrNull;
    final workout = ref.watch(_portalWorkoutProvider).valueOrNull;
    final diet = ref.watch(_portalDietProvider).valueOrNull;

    final rows = <Widget>[];

    if (booking != null) {
      final session = booking['class_sessions'] as Map<String, dynamic>?;
      final cls = session?['classes'] as Map<String, dynamic>?;
      final startsAt = DateTime.tryParse(
        session?['starts_at'] as String? ?? '',
      );
      rows.add(
        _TodayRow(
          icon: AppIcons.eventActive,
          iconBg: AppTheme.accentSoft,
          iconColor: AppTheme.accent,
          title: [
            cls?['name'] as String? ?? 'Class',
            if (startsAt != null)
              TimeOfDay.fromDateTime(startsAt.toLocal()).format(context),
          ].join(' · '),
          subtitle: 'Booked for today',
          trailing: const Text(
            'Booked',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.accent,
            ),
          ),
          // Informational only — the Bookings tab and its route are gone, so
          // there is nowhere for this to lead.
        ),
      );
    }

    if (workout != null) {
      final exercises = (workout['exercises'] as List?)?.length;
      rows.add(
        _TodayRow(
          icon: AppIcons.fitnessActive,
          iconBg: AppTheme.statusActiveBg,
          iconColor: AppTheme.statusActive,
          title: workout['name'] as String? ?? 'Workout plan',
          subtitle: exercises != null
              ? '$exercises exercise${exercises == 1 ? '' : 's'}'
              : 'Your plan',
          onTap: () => context.push('/portal/workout'),
        ),
      );
    }

    if (diet != null) {
      final kcal = diet['calories'];
      final protein = diet['protein_g'];
      final meals = (diet['meals'] as List?)?.length;
      final title = [
        if (kcal != null) '$kcal kcal',
        if (protein != null) '${protein}g protein',
      ].join(' · ');
      rows.add(
        _TodayRow(
          icon: AppIcons.restaurant,
          iconBg: AppTheme.statusWarnBg,
          iconColor: AppTheme.statusWarn,
          title: title.isEmpty
              ? (diet['name'] as String? ?? 'Diet plan')
              : title,
          subtitle: meals != null
              ? '$meals meal${meals == 1 ? '' : 's'} planned'
              : 'Your plan',
          onTap: () => context.push('/portal/diet'),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Today',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 10),
        CardList(children: rows),
      ],
    );
  }
}

class _TodayRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  /// Null for rows that are purely informational — InkWell renders them
  /// unpressable rather than navigating somewhere that no longer exists.
  final VoidCallback? onTap;
  const _TodayRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(
                  AppIcons.chevronRight,
                  size: 20,
                  color: AppTheme.inkHint,
                ),
          ],
        ),
      ),
    );
  }
}

// ─── Attendance card ──────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final AsyncValue<int> monthVisitsAsync;
  final AsyncValue<List<Map<String, dynamic>>> recentCheckinsAsync;
  const _AttendanceCard({
    required this.monthVisitsAsync,
    required this.recentCheckinsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final visits = monthVisitsAsync.valueOrNull ?? 0;
    final checkIns = recentCheckinsAsync.valueOrNull ?? const [];

    // Distinct local days the member checked in, newest first.
    final days = <DateTime>{};
    for (final c in checkIns) {
      final t = DateTime.tryParse(c['checked_in_at'] as String? ?? '');
      if (t == null) continue;
      final local = t.toLocal();
      days.add(DateTime(local.year, local.month, local.day));
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Streak counts back from today (or yesterday, so an early-morning visit
    // gap doesn't look like a broken streak).
    var streak = 0;
    var cursor = days.contains(todayDate)
        ? todayDate
        : todayDate.subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final monthName = _monthNames[today.month - 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your attendance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/portal/heatmap'),
              behavior: HitTestBehavior.opaque,
              child: const Text(
                'History',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$visits',
                    style: AppTheme.numberStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      streak > 0
                          ? 'visits in $monthName · $streak-day streak'
                          : 'visits in $monthName',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Last 14 days, oldest on the left.
              Row(
                children: List.generate(14, (i) {
                  final day = todayDate.subtract(Duration(days: 13 - i));
                  final visited = days.contains(day);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 13 ? 0 : 4),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: visited
                                ? AppTheme.statusActive
                                : AppTheme.surface2,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// ─── Outstanding alert ────────────────────────────────────────────────────────

class _OutstandingAlert extends StatelessWidget {
  final double amount;
  const _OutstandingAlert({required this.amount});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/portal/billing'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.statusDangerBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              AppIcons.error,
              size: 19,
              color: AppTheme.statusDanger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${formatCurrency(amount)} pending from your last payment',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E2F1B),
                ),
              ),
            ),
            const Text(
              'View',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.statusDanger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
