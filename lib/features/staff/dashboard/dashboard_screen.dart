import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/billing/billing_access.dart';
import '../settings/gym_branches_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/services/offline_checkin_queue.dart';
import '../../../core/access/role_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../members/members_screen.dart' show showAddMemberSheet;
import '../notifications/notifications_screen.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

final _dashboardDataProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
  final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
  final lastMonthStart = DateTime(now.year, now.month - 1, 1).toIso8601String();
  final in7Days = now
      .add(const Duration(days: 7))
      .toIso8601String()
      .split('T')[0];
  final todayDate = now.toIso8601String().split('T')[0];
  final startOfWeek = now
      .subtract(Duration(days: now.weekday - 1))
      .toIso8601String();

  final results = await Future.wait([
    Future.wait<PostgrestResponse<List<Map<String, dynamic>>>>([
      client
          .from('members')
          .select('id')
          .eq('gym_id', gymId)
          .eq('status', 'active')
          .count(CountOption.exact),
      client
          .from('check_ins')
          .select('id')
          .eq('gym_id', gymId)
          .gte('checked_in_at', startOfDay)
          .count(CountOption.exact),
      client
          .from('members')
          .select('id')
          .eq('gym_id', gymId)
          .gte('created_at', startOfMonth)
          .count(CountOption.exact),
      client
          .from('check_ins')
          .select('id')
          .eq('gym_id', gymId)
          .count(CountOption.exact),
      client
          .from('membership_plans')
          .select('id')
          .eq('gym_id', gymId)
          .eq('is_active', true)
          .count(CountOption.exact),
      client
          .from('leads')
          .select('id')
          .eq('gym_id', gymId)
          .gte('created_at', startOfWeek)
          .count(CountOption.exact),
      client
          .from('members')
          .select('id')
          .eq('gym_id', gymId)
          .count(CountOption.exact),
    ]),
    Future.wait<List<Map<String, dynamic>>>([
      // Cash actually collected — read from `payments`, not `invoices.status
      // = 'paid'`, so a partial payment counts the moment it's collected
      // rather than only once its invoice is later fully settled.
      client
          .from('payments')
          .select('amount, created_at, invoices!inner(gym_id)')
          .eq('invoices.gym_id', gymId)
          .eq('status', 'succeeded')
          .gte('created_at', startOfDay),
      client
          .from('invoices')
          .select('amount, due_at, payments(amount, status)')
          .eq('gym_id', gymId)
          .inFilter('status', ['open', 'partial']),
      client
          .from('payments')
          .select('amount, created_at, invoices!inner(gym_id)')
          .eq('invoices.gym_id', gymId)
          .eq('status', 'succeeded')
          .gte('created_at', startOfMonth),
      client
          .from('payments')
          .select('amount, created_at, invoices!inner(gym_id)')
          .eq('invoices.gym_id', gymId)
          .eq('status', 'succeeded')
          .gte('created_at', lastMonthStart)
          .lt('created_at', startOfMonth),
      // Renewals due within 7 days (includes today — "Payment due today" splits those out client-side).
      client
          .from('members')
          .select(
            'id, first_name, last_name, phone, next_payment_date, avatar_url',
          )
          .eq('gym_id', gymId)
          .eq('status', 'active')
          .gte('next_payment_date', todayDate)
          .lte('next_payment_date', in7Days)
          .order('next_payment_date'),
      // Recent payments feed — individual payment transactions (so a partial
      // collection shows up immediately, not just once its invoice is fully paid).
      client
          .from('payments')
          .select(
            'amount, created_at, invoices!inner(gym_id, members(first_name, last_name, avatar_url))',
          )
          .eq('invoices.gym_id', gymId)
          .eq('status', 'succeeded')
          .order('created_at', ascending: false)
          .limit(4),
      // Today's check-in feed.
      client
          .from('check_ins')
          .select(
            'id, checked_in_at, members(first_name, last_name, avatar_url)',
          )
          .eq('gym_id', gymId)
          .gte('checked_in_at', startOfDay)
          .order('checked_in_at', ascending: false)
          .limit(5),
      // Latest leads.
      client
          .from('leads')
          .select(
            'id, first_name, last_name, phone, source, status, created_at',
          )
          .eq('gym_id', gymId)
          .order('created_at', ascending: false)
          .limit(4),
      // Leads whose follow-up date has already passed — the only lead signal
      // that genuinely needs action today.
      client
          .from('leads')
          .select('id')
          .eq('gym_id', gymId)
          .not('status', 'in', '(converted,lost)')
          .not('follow_up_at', 'is', null)
          .lt('follow_up_at', todayDate),
      // This month's logged expenses, for the profit figure below.
      client
          .from('expenses')
          .select('amount')
          .eq('gym_id', gymId)
          .gte('expense_date', startOfMonth.split('T')[0]),
    ]),
  ]);

  final counts =
      results[0] as List<PostgrestResponse<List<Map<String, dynamic>>>>;
  final rows = results[1] as List<List<Map<String, dynamic>>>;

  final todayPaid = rows[0];
  final dueInvoices = rows[1];
  final monthPaid = rows[2];
  final lastMonthPaid = rows[3];

  double sum(List<Map<String, dynamic>> l) =>
      l.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

  // Remaining balance per invoice — full amount minus whatever's already
  // been paid — not the raw invoice amount, which would overstate dues on
  // any invoice that's partially paid.
  double remainingDue(Map<String, dynamic> inv) {
    final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
    final invPayments = (inv['payments'] as List?) ?? const [];
    final paid = invPayments
        .where((p) => (p as Map)['status'] == 'succeeded')
        .fold<double>(
          0,
          (s, p) => s + ((p as Map)['amount'] as num).toDouble(),
        );
    return (amount - paid).clamp(0, amount);
  }

  // "Overdue" = an unsettled invoice whose due date has already passed.
  // Invoices with no due date are still owed, but they aren't late.
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final overdue = dueInvoices.where((inv) {
    if (remainingDue(inv) <= 0) return false;
    final due = DateTime.tryParse((inv['due_at'] as String?) ?? '');
    return due != null && due.isBefore(todayMidnight);
  }).toList();

  final collectedToday = sum(todayPaid);
  final pendingRevenue = dueInvoices.fold<double>(
    0,
    (s, inv) => s + remainingDue(inv),
  );
  final monthRevenue = sum(monthPaid);
  final lastMonthRevenue = sum(lastMonthPaid);
  final growthPct = lastMonthRevenue > 0
      ? ((monthRevenue - lastMonthRevenue) / lastMonthRevenue * 100).round()
      : null;

  // Recent payments feed comes from `payments` (flattened back to the shape
  // the UI expects: amount/paid_at/members) so partial collections show up
  // immediately, not only once their invoice is fully settled.
  final recentPaid = rows[5].map((p) {
    final invoice = p['invoices'] as Map<String, dynamic>?;
    return {
      'amount': p['amount'],
      'paid_at': p['created_at'],
      'members': invoice?['members'],
    };
  }).toList();

  return {
    'activeMembers': counts[0].count,
    'todayCheckins': counts[1].count,
    'newMembersMonth': counts[2].count,
    'allTimeCheckins': counts[3].count,
    'planCount': counts[4].count,
    'leadsThisWeek': counts[5].count,
    'memberCount': counts[6].count,
    'collectedToday': collectedToday,
    'todayPayments': todayPaid.length,
    'pendingRevenue': pendingRevenue,
    'monthRevenue': monthRevenue,
    'growthPct': growthPct,
    'renewals': rows[4],
    'recentPaid': recentPaid,
    'todayCheckinsList': rows[6],
    'recentLeads': rows[7],
    'monthExpenses': sum(rows[9]),
    'profit': monthRevenue - sum(rows[9]),
    'dueCount': dueInvoices.where((i) => remainingDue(i) > 0).length,
    'overdueCount': overdue.length,
    'overdueAmount': overdue.fold<double>(0, (s, i) => s + remainingDue(i)),
    'leadsToFollowUp': rows[8].length,
  };
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // These totals are cached, so a payment or check-in recorded on any other
    // screen used to leave stale numbers here until the app restarted.
    gymDataChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    gymDataChanged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) ref.invalidate(_dashboardDataProvider);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_dashboardDataProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(_dashboardDataProvider),
          child: data.when(
            loading: () => const _LoadingBody(),
            error: (e, _) => _ErrorBody(error: e.toString()),
            data: (d) => _DashboardBody(data: d),
          ),
        ),
      ),
    );
  }
}

// ─── Loading / Error ──────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (i) => Container(
            height: i == 0 ? 56 : (i == 1 ? 170 : 100),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends ConsumerWidget {
  final String error;
  const _ErrorBody({required this.error});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              AppIcons.cloudOff,
              size: 52,
              color: AppTheme.inkHint,
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load dashboard',
              style: TextStyle(fontSize: 14, color: AppTheme.inkHint),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 140,
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.invalidate(_dashboardDataProvider);
                  ref.invalidate(gymIdProvider);
                },
                icon: const Icon(AppIcons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Body ───────────────────────────────────────────────────────────

class _DashboardBody extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canBilling = RoleAccess.canSeeBilling(role);
    final canCollect = RoleAccess.canRecordPayment(role);
    final canLeads = RoleAccess.canSeeLeads(role);

    final profile = ref.watch(staffProfileProvider).valueOrNull;
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final gymName = gym?['name'] as String? ?? 'My Gym';
    final memberCount = (data['memberCount'] as int?) ?? 0;
    final planCount = (data['planCount'] as int?) ?? 0;
    final allTimeCheckins = (data['allTimeCheckins'] as int?) ?? 0;
    final showChecklist =
        memberCount < 3 || planCount == 0 || allTimeCheckins == 0;

    final header = [
      // Trial/plan status moved into the header itself as a small pill under
      // the gym name (see _Header) — it used to be a full-width card here,
      // competing with the checklist for the most valuable spot on a new
      // gym's dashboard. The member-signup code moved to the Members screen,
      // where it's contextually relevant (inviting members) instead of
      // permanently occupying the home screen.
      _Header(gymName: gymName, gym: gym, showBilling: canBilling),
      const SizedBox(height: 12),
      if (showChecklist) ...[
        _SetupChecklist(
          gym: gym,
          memberCount: memberCount,
          planCount: planCount,
          allTimeCheckins: allTimeCheckins,
        ),
        const SizedBox(height: 12),
      ],
    ];

    // Action first, then the numbers. Anything that needs a decision today
    // (money owed, memberships about to lapse, leads past their follow-up,
    // check-ins still queued offline) sits above the passive "Today" counts.
    final leftColumn = [
      if (canBilling) ...[
        _CollectedHero(data: data),
        const SizedBox(height: 10),
      ],
      _QuickActions(canCollect: canCollect, canLeads: canLeads),
      const SizedBox(height: 16),
      _NeedsAttention(
        data: data,
        canBilling: canBilling,
        canLeads: canLeads,
        canCheckIn: RoleAccess.canCheckIn(role),
      ),
      const SizedBox(height: 16),
      _TodayStats(
        checkins: (data['todayCheckins'] as int?) ?? 0,
        payments: (data['todayPayments'] as int?) ?? 0,
        active: (data['activeMembers'] as int?) ?? 0,
        joined: (data['newMembersMonth'] as int?) ?? 0,
        canReports: RoleAccess.canSeeReports(role),
      ),
    ];

    final rightColumn = [
      _PaymentDueToday(data: data, canCollect: canCollect),
      const SizedBox(height: 16),
      _TodayCheckins(
        checkins: (data['todayCheckinsList'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
        todayCount: (data['todayCheckins'] as int?) ?? 0,
      ),
      if (canBilling) ...[
        const SizedBox(height: 16),
        _RecentPayments(
          invoices: (data['recentPaid'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        ),
      ],
      if (canLeads) ...[
        const SizedBox(height: 16),
        _NewLeads(
          leads: (data['recentLeads'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
          leadsThisWeek: (data['leadsThisWeek'] as int?) ?? 0,
        ),
      ],
    ];

    final isWide = ResponsiveContent.isWide(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...header,
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: leftColumn,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rightColumn,
                  ),
                ),
              ],
            )
          else ...[
            ...leftColumn,
            const SizedBox(height: 16),
            ...rightColumn,
          ],
        ],
      ),
    );
  }
}

// ─── Setup checklist (getting started) ────────────────────────────────────────

class _SetupChecklist extends ConsumerWidget {
  final Map<String, dynamic>? gym;
  final int memberCount, planCount, allTimeCheckins;
  const _SetupChecklist({
    required this.gym,
    required this.memberCount,
    required this.planCount,
    required this.allTimeCheckins,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatsappOn = gym?['whatsapp_reminder_enabled'] == true;

    // Labels name the outcome, not the mechanic — "Add 3 members" tells you
    // what to do, "see your dashboard come alive" tells you why it's worth
    // doing. "Add members" opens the sheet directly instead of routing to the
    // members list first — one less stop between intent and the first value.
    final steps = [
      (
        label: 'Add 3 members — see your dashboard come alive',
        done: memberCount >= 3,
        onTap: () => showAddMemberSheet(
          context,
        ).then((_) => ref.invalidate(_dashboardDataProvider)),
      ),
      (
        label: 'Set your monthly fee',
        done: planCount > 0,
        onTap: () => context.push('/staff/billing'),
      ),
      (
        label: 'Try a check-in',
        done: allTimeCheckins > 0,
        onTap: () => context.push('/staff/check-in'),
      ),
      (
        label: 'Turn on WhatsApp reminders',
        done: whatsappOn,
        onTap: () => context.push('/staff/reminders'),
      ),
    ];
    final doneCount = steps.where((s) => s.done).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Getting started',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const Spacer(),
              Text(
                '$doneCount / ${steps.length}',
                style: AppTheme.numberStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: doneCount / steps.length,
              minHeight: 5,
              backgroundColor: AppTheme.surface2,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 14),
          ...steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: s.onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: s.done
                            ? AppTheme.statusActive
                            : AppTheme.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: s.done
                          ? const Icon(
                              AppIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: s.done ? AppTheme.inkSoft : AppTheme.ink,
                          decoration: s.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (!s.done)
                      const Icon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: AppTheme.inkHint,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick actions ────────────────────────────────────────────────────────────

class _QuickActions extends ConsumerWidget {
  final bool canCollect;
  final bool canLeads;
  const _QuickActions({required this.canCollect, required this.canLeads});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final items = [
      // Opens the add-member sheet directly instead of routing to the
      // members list first — same shortcut the dashboard checklist uses.
      (
        icon: AppIcons.personAdd,
        label: 'Add\nmember',
        accent: true,
        onTap: () => showAddMemberSheet(
          context,
        ).then((_) => ref.invalidate(_dashboardDataProvider)),
      ),
      if (canCollect)
        (
          icon: AppIcons.payments,
          label: 'Collect\npayment',
          accent: false,
          onTap: () => context.push('/staff/billing'),
        ),
      if (RoleAccess.canCheckIn(role))
        (
          icon: AppIcons.qrScanner,
          label: 'Check\nin',
          accent: false,
          onTap: () => context.push('/staff/check-in'),
        ),
      if (canLeads)
        (
          icon: AppIcons.personSearch,
          label: 'Add\nlead',
          accent: false,
          onTap: () => context.push('/staff/leads'),
        ),
    ];

    // One teal tile — the action a front desk reaches for most — and the rest
    // on white, so the row has a clear first choice instead of four equals.
    // A 2-column grid (rather than squeezing every tile into one row) gives
    // each tile enough width for icon + label side by side without wrapping.
    Widget tile(_QuickAction item) => GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: item.accent
            ? BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(14),
              )
            : AppTheme.cardDecoration(radius: 14),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 20,
              color: item.accent ? Colors.white : AppTheme.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: item.accent ? Colors.white : AppTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      final second = i + 1 < items.length;
      rows.add(
        Row(
          children: [
            Expanded(child: tile(items[i])),
            if (second) ...[
              const SizedBox(width: 8),
              Expanded(child: tile(items[i + 1])),
            ],
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

typedef _QuickAction = ({
  IconData icon,
  String label,
  bool accent,
  VoidCallback onTap,
});

// ─── Today's check-ins ────────────────────────────────────────────────────────

class _TodayCheckins extends StatelessWidget {
  final List<Map<String, dynamic>> checkins;
  final int todayCount;
  const _TodayCheckins({required this.checkins, required this.todayCount});

  static String _fmtTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final dh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$dh:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Checked in today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$todayCount',
              style: AppTheme.numberStyle(fontSize: 15, color: AppTheme.accent),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/staff/check-in'),
              child: const Text(
                'See all',
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
        if (checkins.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: AppTheme.cardDecoration(),
            child: const Center(
              child: Text(
                'No check-ins yet today',
                style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ),
          )
        else
          CardList(
            children: checkins.map((ci) {
              final member = ci['members'] as Map<String, dynamic>?;
              final name =
                  '${member?['first_name'] ?? ''} ${member?['last_name'] ?? ''}'
                      .trim();
              final label = name.isEmpty ? 'Member' : name;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: label,
                      size: 36,
                      photo: member?['avatar_url'] as String?,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    Text(
                      _fmtTime(ci['checked_in_at'] as String?),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppTheme.statusActiveBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.check,
                        size: 14,
                        color: AppTheme.statusActive,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─── Recent payments ──────────────────────────────────────────────────────────

class _RecentPayments extends StatelessWidget {
  final List<Map<String, dynamic>> invoices;
  const _RecentPayments({required this.invoices});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Recent payments',
          actionLabel: 'See all',
          onAction: () => context.push('/staff/billing'),
        ),
        const SizedBox(height: 10),
        if (invoices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: AppTheme.cardDecoration(),
            child: const Center(
              child: Text(
                'No payments yet',
                style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ),
          )
        else
          CardList(
            children: invoices.map((inv) {
              final member = inv['members'] as Map<String, dynamic>?;
              final name =
                  '${member?['first_name'] ?? ''} ${member?['last_name'] ?? ''}'
                      .trim();
              final label = name.isEmpty ? 'Member' : name;
              final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
              final paidAt = inv['paid_at'] as String?;
              String when = '';
              if (paidAt != null) {
                final dt = DateTime.tryParse(paidAt)?.toLocal();
                if (dt != null) {
                  final days = DateTime.now().difference(dt).inDays;
                  when = days == 0
                      ? 'Today'
                      : days == 1
                      ? 'Yesterday'
                      : '$days days ago';
                }
              }
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    InitialsAvatar(
                      name: label,
                      size: 36,
                      photo: member?['avatar_url'] as String?,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink,
                            ),
                          ),
                          if (when.isNotEmpty)
                            Text(
                              when,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _rupees(amount),
                          style: AppTheme.numberStyle(
                            fontSize: 15,
                            color: AppTheme.statusActive,
                          ),
                        ),
                        const SizedBox(height: 3),
                        StatusPill.active(label: 'Paid'),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─── New leads ────────────────────────────────────────────────────────────────

class _NewLeads extends StatelessWidget {
  final List<Map<String, dynamic>> leads;
  final int leadsThisWeek;
  const _NewLeads({required this.leads, required this.leadsThisWeek});

  static StatusPill _pillFor(String status) => switch (status.toLowerCase()) {
    'converted' => StatusPill.active(label: 'Converted'),
    'lost' => StatusPill.danger(label: 'Lost'),
    'trial' => StatusPill.warn(label: 'Trial'),
    'contacted' => StatusPill.neutral(label: 'Contacted'),
    _ => StatusPill(
      label: 'New',
      color: AppTheme.statusDanger,
      bg: AppTheme.statusDangerBg,
    ),
  };

  Future<void> _call(String phone) async {
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Enquiries',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$leadsThisWeek this week',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/staff/leads'),
              child: const Text(
                'See all',
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
        if (leads.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: AppTheme.cardDecoration(),
            child: const Center(
              child: Text(
                'No enquiries yet',
                style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ),
          )
        else
          CardList(
            children: leads.map((lead) {
              final name =
                  '${lead['first_name'] ?? ''} ${lead['last_name'] ?? ''}'
                      .trim();
              final label = name.isEmpty ? 'Enquiry' : name;
              final source = (lead['source'] as String? ?? '').trim();
              final status = lead['status'] as String? ?? 'new';
              final phone = lead['phone'] as String?;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    InitialsAvatar(name: label, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink,
                            ),
                          ),
                          if (source.isNotEmpty)
                            Text(
                              source[0].toUpperCase() + source.substring(1),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _pillFor(status),
                    if (phone != null && phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      RoundIconButton(
                        icon: AppIcons.call,
                        size: 36,
                        onTap: () => _call(phone),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─── Header (date · gym name · bell · avatar) ─────────────────────────────────

class _Header extends ConsumerWidget {
  final String gymName;
  final Map<String, dynamic>? gym;
  final bool showBilling;
  const _Header({required this.gymName, this.gym, this.showBilling = false});

  // Same label logic the old full-width _SubscriptionBanner card used —
  // just rendered as a compact pill under the gym name instead of a
  // separate card, so it stays visible every time the dashboard opens
  // without competing with the checklist for space.
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
    final unreadCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The chevron is the branch switcher the canvas draws — it opens
              // the same sheet the shell's branch control uses.
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
        // Canvas 1a keeps one control up here. What's-new moved into Settings,
        // and the profile avatar is redundant with More → Settings.
        GestureDetector(
          onTap: () => context.push('/staff/notifications'),
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
                child: const Icon(
                  AppIcons.notifications,
                  size: 21,
                  color: AppTheme.ink,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppTheme.statusDanger,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.background,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Collected today hero (dark card) ─────────────────────────────────────────

String _rupees(double v) {
  if (currencyCode != 'INR') return formatCurrency(v);
  if (v >= 100000) return '$currencySymbol${(v / 100000).toStringAsFixed(2)}L';
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    buf.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && ((left - 3) % 2 == 0 || left == 3) && left >= 3) {
      // Indian grouping: 12,34,567
      if (left == 3 || (left > 3 && (left - 3) % 2 == 0)) buf.write(',');
    }
  }
  return '$currencySymbol${buf.toString()}';
}

/// Canvas 1a hero: one kicker, one big figure with a trend pill, a rule, and
/// the single row that asks for an action. Collected-today, expenses and
/// profit deliberately live in Reports now — the artboard keeps this card to
/// one decision.
class _CollectedHero extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CollectedHero({required this.data});

  static const _months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  @override
  Widget build(BuildContext context) {
    final month = (data['monthRevenue'] as double?) ?? 0;
    final growth = data['growthPct'] as int?;
    final pending = (data['pendingRevenue'] as double?) ?? 0;
    final dueCount = (data['dueCount'] as int?) ?? 0;
    final up = growth == null || growth >= 0;

    return GestureDetector(
      onTap: () => context.push('/staff/billing'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: AppTheme.darkCardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COLLECTED IN ${_months[DateTime.now().month - 1]}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppTheme.onDarkSoft,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _rupees(month),
                      style: AppTheme.numberStyle(
                        fontSize: 34,
                        color: AppTheme.onDark,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                if (growth != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          up ? AppIcons.trendingUp : AppIcons.trendingDown,
                          size: 14,
                          color: up
                              ? AppTheme.mintOnDark
                              : AppTheme.statusDanger,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${growth.abs()}%',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: up
                                ? AppTheme.mintOnDark
                                : AppTheme.statusDanger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Outstanding dues',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onDarkSoft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dueCount > 0
                              ? '${_rupees(pending)} · $dueCount member${dueCount == 1 ? '' : 's'}'
                              : _rupees(pending),
                          style: AppTheme.numberStyle(
                            fontSize: 18,
                            color: AppTheme.onDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Collect',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onDark,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        AppIcons.chevronRight,
                        size: 16,
                        color: AppTheme.onDark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Needs attention ──────────────────────────────────────────────────────────

/// Check-ins recorded while offline and still waiting to sync. Read straight
/// from the same queue the check-in screen flushes; QR check-ins are the only
/// thing this app queues offline.
final _pendingSyncProvider = FutureProvider<int>(
  (_) => OfflineCheckInQueue.pendingCount(),
);

/// One card holding everything that needs a decision today. Each row is only
/// built from data the backend already returns, and the whole card disappears
/// when there is nothing to act on.
class _NeedsAttention extends ConsumerWidget {
  final Map<String, dynamic> data;
  final bool canBilling;
  final bool canLeads;
  final bool canCheckIn;
  const _NeedsAttention({
    required this.data,
    required this.canBilling,
    required this.canLeads,
    required this.canCheckIn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueCount = (data['overdueCount'] as int?) ?? 0;
    final overdueAmount = (data['overdueAmount'] as double?) ?? 0;
    final renewals = (data['renewals'] as List<dynamic>? ?? const []).length;
    final leads = (data['leadsToFollowUp'] as int?) ?? 0;
    final pendingSync = canCheckIn
        ? (ref.watch(_pendingSyncProvider).valueOrNull ?? 0)
        : 0;

    final rows = <Widget>[
      if (canBilling && overdueCount > 0)
        AttentionTile.danger(
          icon: AppIcons.error,
          title: '$overdueCount overdue payment${overdueCount == 1 ? '' : 's'}',
          subtitle: '${formatCurrency(overdueAmount)} pending',
          // Expiring soon opens on its Overdue tab — the per-member list with
          // Collect and WhatsApp on each row, not the Money ledger.
          onTap: () => context.push('/staff/upcoming-payments'),
        ),
      if (renewals > 0)
        AttentionTile.warn(
          icon: AppIcons.schedule,
          title:
              '$renewals membership${renewals == 1 ? '' : 's'} due in 7 days',
          subtitle: 'Renew before they lapse',
          onTap: () => context.push('/staff/upcoming-payments?tab=expiring'),
        ),
      if (canLeads && leads > 0)
        AttentionTile.info(
          icon: AppIcons.personSearch,
          title: '$leads lead${leads == 1 ? '' : 's'} need follow-up',
          subtitle: 'Follow-up date has passed',
          onTap: () => context.push('/staff/leads'),
        ),
      if (pendingSync > 0)
        AttentionTile.neutral(
          icon: AppIcons.cloudOff,
          title:
              '$pendingSync check-in${pendingSync == 1 ? '' : 's'} waiting to sync',
          subtitle: 'Saved offline · syncs when back online',
          onTap: () => context.push('/staff/check-in'),
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Needs attention', style: AppTheme.sectionTitle),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.statusDangerBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${rows.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.statusDanger,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        CardList(children: rows),
      ],
    );
  }
}

// ─── Today ────────────────────────────────────────────────────────────────────

class _TodayStats extends StatelessWidget {
  final int checkins, payments, active, joined;
  final bool canReports;
  const _TodayStats({
    required this.checkins,
    required this.payments,
    required this.active,
    required this.joined,
    required this.canReports,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Today',
          actionLabel: canReports ? 'Reports' : null,
          onAction: canReports ? () => context.push('/staff/reports') : null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MiniStat(
                label: 'Check-ins',
                value: '$checkins',
                onTap: () => context.push('/staff/check-in'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniStat(
                label: 'Payments',
                value: '$payments',
                onTap: () => context.push('/staff/billing'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniStat(
                label: 'Active',
                value: '$active',
                onTap: () => context.push('/staff/members'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MiniStat(
                label: 'Joined',
                value: '$joined',
                onTap: () => context.push('/staff/members'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Payment due today ──────────────────────────────────────────────────────────

class _PaymentDueToday extends ConsumerWidget {
  final Map<String, dynamic> data;
  final bool canCollect;
  const _PaymentDueToday({required this.data, required this.canCollect});

  Future<void> _showCollect(
    BuildContext ctx,
    WidgetRef ref,
    Map<String, dynamic> member,
  ) async {
    await showAdaptiveSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CollectPaymentSheet(
        member: member,
        onPaid: () => ref.invalidate(_dashboardDataProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final renewals = (data['renewals'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    // "renewals" is due-within-7-days; a member is due today when their
    // next_payment_date falls on (or before, still-active grace) today.
    final dueToday = renewals.where((m) {
      final npd = m['next_payment_date'] as String?;
      if (npd == null) return false;
      final d = DateTime.parse(npd);
      return !DateTime(d.year, d.month, d.day).isAfter(today);
    }).toList();

    if (dueToday.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Payment due today'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: AppTheme.cardDecoration(),
            child: const Center(
              child: Text(
                'No payments due today',
                style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Payment due today',
          actionLabel: 'See all',
          onAction: () => context.push('/staff/upcoming-payments'),
        ),
        const SizedBox(height: 10),
        CardList(
          children: dueToday.map((m) {
            final npd = m['next_payment_date'] as String?;
            var subtitle = 'Due today';
            if (npd != null) {
              final days = today
                  .difference(
                    DateTime(
                      DateTime.parse(npd).year,
                      DateTime.parse(npd).month,
                      DateTime.parse(npd).day,
                    ),
                  )
                  .inDays;
              if (days > 0)
                subtitle = '$days day${days == 1 ? '' : 's'} overdue';
            }
            return _AttentionRow(
              member: m,
              subtitle: subtitle,
              subColor: AppTheme.statusDanger,
              canCollect: canCollect,
              collectLabel: 'Collect',
              onCollect: () => _showCollect(context, ref, m),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Shared attention/upcoming row ─────────────────────────────────────────────

class _AttentionRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final String subtitle;
  final Color subColor;
  final bool canCollect;
  final String collectLabel;
  final VoidCallback onCollect;

  const _AttentionRow({
    required this.member,
    required this.subtitle,
    required this.subColor,
    required this.canCollect,
    required this.collectLabel,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'
        .trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          InitialsAvatar(
            name: name,
            size: 40,
            photo: member['avatar_url'] as String?,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => context.push('/staff/members/${member['id']}'),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (canCollect) PillButton(label: collectLabel, onTap: onCollect),
        ],
      ),
    );
  }
}

// ─── Collect Payment Sheet ────────────────────────────────────────────────────

class _CollectPaymentSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> member;
  final VoidCallback onPaid;
  const _CollectPaymentSheet({required this.member, required this.onPaid});
  @override
  ConsumerState<_CollectPaymentSheet> createState() =>
      _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends ConsumerState<_CollectPaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;
  String? _planHint;
  String? _nextPaymentDate;
  double? _due;
  bool _partlyPaid = false;

  /// Balance still owed on a real open/partial invoice — 0 when there is no
  /// such invoice. Deliberately not `_due`, which falls back to the plan price
  /// when nothing is invoiced yet; that fallback would disable the duplicate
  /// guard on the very retry it exists to catch.
  double _outstanding = 0;

  static const _methods = [
    ('cash', 'Cash', AppIcons.payments),
    ('upi', 'UPI', AppIcons.qrCode),
    ('bank_transfer', 'Bank Transfer', AppIcons.accountBalance),
    ('card', 'Card', AppIcons.creditCard),
  ];

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _autofill() async {
    final memberId = widget.member['id'] as String?;
    if (memberId == null) return;
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('members')
          .select(
            'next_payment_date, memberships(status, discount_amount, membership_plans(price, name))',
          )
          .eq('id', memberId)
          .maybeSingle();
      if (data == null || !mounted) return;
      final memberships = (data['memberships'] as List?) ?? [];
      Map<String, dynamic>? active;
      for (final m in memberships) {
        if ((m as Map)['status'] == 'active') {
          active = m.cast<String, dynamic>();
          break;
        }
      }
      final plan = active?['membership_plans'] as Map?;
      final discount = (active?['discount_amount'] as num?)?.toDouble() ?? 0;
      double? finalPrice;
      setState(() {
        if (plan != null && plan['price'] != null) {
          final listPrice = (plan['price'] as num).toDouble();
          finalPrice = (listPrice - discount).clamp(0, listPrice);
          _amountCtrl.text = finalPrice!.toStringAsFixed(0);
          _planHint = discount > 0
              ? '${plan['name']} — $currencySymbol${listPrice.toStringAsFixed(0)} − $currencySymbol${discount.toStringAsFixed(0)} discount'
              : '${plan['name']} — $currencySymbol${listPrice.toStringAsFixed(0)}';
        }
        final npd = data['next_payment_date'] as String?;
        if (npd != null) _nextPaymentDate = npd.split('T').first;
      });

      // If there's already an open/partial invoice for this member, its
      // amount (not the plan price) is the real total owed — pre-fill the
      // remaining balance instead of the full plan price.
      final existing = await client
          .from('invoices')
          .select('id, amount')
          .eq('member_id', memberId)
          .inFilter('status', ['open', 'partial'])
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      if (existing != null && mounted) {
        final invoiceAmount = (existing['amount'] as num).toDouble();
        final due = await invoiceDue(existing['id'] as String, invoiceAmount);
        if (!mounted) return;
        setState(() {
          _due = due;
          _partlyPaid = due < invoiceAmount;
          _outstanding = due;
          _amountCtrl.text = due.toStringAsFixed(0);
        });
      } else {
        _due = finalPrice;
        _outstanding = 0;
      }
    } catch (e) {
      debugPrint('[GymCRM] autofill error: $e');
    }
  }

  Future<void> _collect() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    final memberIdForCheck = widget.member['id'] as String;
    // Only a genuine duplicate is worth stopping. If the member still owes
    // money on an open bill, a second collection today is the rest of that
    // bill, not an accidental re-tap.
    final prior = _outstanding > 0
        ? null
        : await LocalPaymentGuard.check(memberIdForCheck);
    if (prior != null && mounted) {
      final firstName = widget.member['first_name'] as String? ?? '';
      final lastName = widget.member['last_name'] as String? ?? '';
      final name = '$firstName $lastName'.trim();
      await showInfoDialog(
        context,
        title: 'Already collected today',
        body:
            '$currencySymbol${prior.amount.toStringAsFixed(0)} was already collected '
            'from $name today at '
            '${prior.at.hour.toString().padLeft(2, '0')}:${prior.at.minute.toString().padLeft(2, '0')}. '
            'Refresh the member before collecting another renewal.',
        icon: AppIcons.history,
      );
      return;
    }

    if (!mounted) return;
    final early = await confirmEarlyRenewalIfNeeded(
      context,
      nextPaymentDate: _nextPaymentDate,
      settlingPartialInvoice: _partlyPaid,
    );
    if (!early) return;
    if (_nextPaymentDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renewal date is missing. Refresh and try again.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final ok = await confirmPartialIfNeeded(
      context,
      enteredAmount: amount,
      dueAmount: _due ?? amount,
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      final memberId = widget.member['id'] as String;
      await collectMembershipRenewal(
        memberId: memberId,
        expectedNextPaymentDate: _nextPaymentDate!,
        amount: amount,
        method: _method,
        referenceNo: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      await LocalPaymentGuard.record(memberId, amount);

      if (mounted) {
        Navigator.pop(context);
        widget.onPaid();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment collected'),
            backgroundColor: AppTheme.statusActive,
          ),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] collect error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(paymentFailureMessage(e))));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.member['first_name'] as String? ?? '';
    final lastName = widget.member['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Collect Payment',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.activeBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.person,
                    size: 16,
                    color: AppTheme.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount ($currencySymbol) *',
                prefixText: '$currencySymbol ',
              ),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text(
                'Auto-filled: $_planHint',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              partialPaymentHint,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment method',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.map((m) {
                final selected = _method == m.$1;
                return GestureDetector(
                  onTap: () => setState(() => _method = m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.ink : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppTheme.ink : AppTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m.$3,
                          size: 16,
                          color: selected ? Colors.white : AppTheme.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: switch (_method) {
                  'upi' => 'UPI Transaction ID (optional)',
                  'bank_transfer' => 'UTR number (optional)',
                  _ => 'Reference / Receipt no. (optional)',
                },
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _collect,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Collect Payment'),
            ),
          ],
        ),
      ),
    );
  }
}
