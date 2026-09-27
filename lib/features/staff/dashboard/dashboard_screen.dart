import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/day_pass.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/billing/payment_dates.dart';
import '../../../core/billing/to_collect.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/services/offline_checkin_queue.dart';
import '../../../core/access/role_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../expenses/expenses_screen.dart' show showAddExpenseSheet;
import '../members/members_screen.dart' show showAddMemberSheet;
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────

/// Also read by Home (checklist, birthdays, alerts) so the two stay in sync.
final dashboardDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
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
          .select('member_id, amount, status, due_at, payments(amount, status)')
          .eq('gym_id', gymId)
          .inFilter('status', ['open', 'partial']),
      client
          .from('payments')
          .select('amount, method, created_at, invoices!inner(gym_id)')
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
            'id, first_name, last_name, phone, next_payment_date, avatar_url, memberships(status, billing_interval_days)',
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
          .select('amount, category')
          .eq('gym_id', gymId)
          .gte('expense_date', startOfMonth.split('T')[0]),
      // Birthdays: PostgREST can't filter on month+day of a date column, so
      // the day match happens below in Dart.
      // ponytail: fetches every member with a DOB — fine at gym scale
      // (hundreds), move to an RPC if a chain ever runs tens of thousands.
      client
          .from('members')
          .select('id, first_name, last_name, phone, avatar_url, dob')
          .eq('gym_id', gymId)
          .eq('status', 'active')
          .not('dob', 'is', null),
      // Renewals with no invoice yet — part of "To collect" (same as Money).
      renewingMembersQuery(client, gymId),
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

  // "Overdue" = an unsettled invoice whose due date passed within the same
  // window Payments Due lists (older ones are old dues, not today's chase).
  // Invoices with no due date are still owed, but they aren't late.
  final todayMidnight = DateTime(now.year, now.month, now.day);
  final overdueSince = todayMidnight.subtract(
    const Duration(days: collectWindowDays),
  );
  final overdue = dueInvoices.where((inv) {
    if (remainingDue(inv) <= 0) return false;
    final due = DateTime.tryParse((inv['due_at'] as String?) ?? '');
    return due != null &&
        due.isBefore(todayMidnight) &&
        !due.isBefore(overdueSince);
  }).toList();

  final collectedToday = sum(todayPaid);
  // Was the sum of every open invoice, due date ignored — an advance bill due
  // in 2028 showed as owed today while Money said ₹0. Now Money's exact rule.
  final toCollect = computeToCollect(
    invoices: dueInvoices,
    renewingMembers: rows[10],
    now: now,
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

  // Totals grouped by a text column, largest first.
  Map<String, double> totalsBy(List<Map<String, dynamic>> l, String key) {
    final m = <String, double>{};
    for (final r in l) {
      final k = (r[key] as String?) ?? 'other';
      m[k] = (m[k] ?? 0) + ((r['amount'] as num?)?.toDouble() ?? 0);
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  return {
    'activeMembers': counts[0].count,
    'todayCheckins': counts[1].count,
    'newMembersMonth': counts[2].count,
    'allTimeCheckins': counts[3].count,
    'planCount': counts[4].count,
    'memberCount': counts[5].count,
    'collectedToday': collectedToday,
    'todayPayments': todayPaid.length,
    'pendingRevenue': toCollect.total,
    'monthRevenue': monthRevenue,
    'lastMonthRevenue': lastMonthRevenue,
    'growthPct': growthPct,
    'monthByMethod': totalsBy(monthPaid, 'method'),
    'expensesByCategory': totalsBy(rows[8], 'category'),
    // A day pass ends instead of renewing, so it isn't a renewal due.
    'renewals': rows[4].where((m) => !hasActiveDayPass(m)).toList(),
    'recentPaid': recentPaid,
    'todayCheckinsList': rows[6],
    'monthExpenses': sum(rows[8]),
    'profit': monthRevenue - sum(rows[8]),
    // Members, not invoices — one member with 3 bills is "1 member".
    'dueCount': toCollect.members,
    // Members, like the Payments Due rows this tile opens.
    'overdueCount': overdue.map((i) => i['member_id']).toSet().length,
    'overdueAmount': overdue.fold<double>(0, (s, i) => s + remainingDue(i)),
    'leadsToFollowUp': rows[7].length,
    'birthdays': rows[9].where((m) {
      final dob = DateTime.tryParse(m['dob'] as String? ?? '');
      return dob != null && dob.month == now.month && dob.day == now.day;
    }).toList(),
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
    if (mounted) ref.invalidate(dashboardDataProvider);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dashboardDataProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(dashboardDataProvider),
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
            const Icon(AppIcons.cloudOff, size: 52, color: AppTheme.inkHint),
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
                  ref.invalidate(dashboardDataProvider);
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
    final canExpenses = RoleAccess.canSeeExpenses(role);

    // Money only. Shortcuts, the setup checklist, birthdays, the plan pill and
    // non-money alerts live on Home now.
    final header = [
      const Text(
        'Dashboard',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppTheme.ink,
          letterSpacing: -0.4,
        ),
      ),
      const SizedBox(height: 2),
      const Text(
        'Collections, dues, expenses and profit',
        style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      ),
      const SizedBox(height: 14),
    ];

    // Same card and rows the dashboard always had; hides itself when empty.
    final attention = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NeedsAttention(
        data: data,
        canBilling: canBilling,
        canLeads: RoleAccess.canSeeLeads(role),
        canCheckIn: RoleAccess.canCheckIn(role),
      ),
    );

    if (!canBilling) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
        children: [
          ...header,
          attention,
          _PaymentDueToday(data: data, canCollect: canCollect),
        ],
      );
    }

    final leftColumn = [
      _CollectedHero(data: data),
      const SizedBox(height: 10),
      _DueStats(data: data),
      const SizedBox(height: 16),
      attention,
      if (canExpenses) ...[
        _ProfitLossCard(data: data),
        const SizedBox(height: 16),
      ],
      _PaymentDueToday(data: data, canCollect: canCollect),
    ];

    final rightColumn = [
      _BreakdownCard(
        title: 'Collected by payment mode',
        subtitle: 'This month',
        totals: (data['monthByMethod'] as Map<String, double>?) ?? const {},
        labelFor: _methodLabel,
        color: AppTheme.accent,
        emptyText: 'No payments this month yet',
        onTap: () => context.push('/staff/billing'),
      ),
      const SizedBox(height: 16),
      if (canExpenses) ...[
        _BreakdownCard(
          title: 'Expenses by category',
          subtitle: 'This month',
          totals:
              (data['expensesByCategory'] as Map<String, double>?) ?? const {},
          labelFor: (k) => k,
          color: AppTheme.statusDanger,
          emptyText: 'No expenses logged this month',
          onTap: () => context.push('/staff/expenses'),
        ),
        const SizedBox(height: 16),
      ],
      _RecentPayments(
        invoices: (data['recentPaid'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
      ),
    ];

    final isWide = ResponsiveContent.isWide(context);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      // Bottom room for the shell's floating Add button.
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
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

class SetupChecklist extends ConsumerWidget {
  final Map<String, dynamic>? gym;
  final int memberCount, planCount, allTimeCheckins;
  const SetupChecklist({
    super.key,
    required this.gym,
    required this.memberCount,
    required this.planCount,
    required this.allTimeCheckins,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final whatsappOn = gym?['whatsapp_reminder_enabled'] == true;
    final container = ProviderScope.containerOf(context, listen: false);

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
        ).then((_) => container.invalidate(dashboardDataProvider)),
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

// ─── Birthdays ────────────────────────────────────────────────────────────────

/// Renders only on days someone actually has a birthday, so it costs nothing
/// on the other 300-odd days. Each row opens WhatsApp with the wish already
/// typed — the whole point is that it takes one tap at the front desk.
class BirthdaysToday extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  const BirthdaysToday({super.key, required this.members});

  static String _name(Map<String, dynamic> m) =>
      '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();

  Future<void> _wish(BuildContext context, Map<String, dynamic> m) async {
    final phone = (m['phone'] as String?)?.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this member')),
      );
      return;
    }
    final text = Uri.encodeComponent(
      'Happy birthday, ${m['first_name'] ?? 'there'}! 🎉',
    );
    final uri = Uri.parse('https://wa.me/$phone?text=$text');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Birthdays today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${members.length}',
              style: AppTheme.numberStyle(fontSize: 15, color: AppTheme.accent),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: AppTheme.cardDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                    color: AppTheme.border,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _name(members[i]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _wish(context, members[i]),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            'Wish',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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

/// This month's collection with its trend and today's figure, then the one
/// row that asks for an action: what's left to collect.
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
    final today = (data['collectedToday'] as double?) ?? 0;
    final todayCount = (data['todayPayments'] as int?) ?? 0;
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
            const SizedBox(height: 8),
            Text(
              'Today ${_rupees(today)} · $todayCount payment${todayCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.onDarkSoft,
              ),
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
                        'To collect',
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

// ─── Due stats (overdue · due this week · last month) ─────────────────────────

class _DueStats extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DueStats({required this.data});

  @override
  Widget build(BuildContext context) {
    final overdueCount = (data['overdueCount'] as int?) ?? 0;
    final overdueAmount = (data['overdueAmount'] as double?) ?? 0;
    final renewals = (data['renewals'] as List<dynamic>? ?? const []).length;
    final lastMonth = (data['lastMonthRevenue'] as double?) ?? 0;

    Widget stat({
      required String label,
      required String value,
      required String hint,
      required Color color,
      VoidCallback? onTap,
    }) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: AppTheme.cardDecoration(radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTheme.numberStyle(fontSize: 18, color: color),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        stat(
          label: 'Overdue',
          value: _rupees(overdueAmount),
          hint: '$overdueCount member${overdueCount == 1 ? '' : 's'}',
          color: overdueCount > 0 ? AppTheme.statusDanger : AppTheme.ink,
          // Same destination the old Needs-attention overdue row opened.
          onTap: () => context.push('/staff/upcoming-payments'),
        ),
        const SizedBox(width: 8),
        stat(
          label: 'Due in 7 days',
          value: '$renewals',
          hint: 'renewals',
          color: renewals > 0 ? AppTheme.statusWarn : AppTheme.ink,
          onTap: () => context.push('/staff/upcoming-payments?tab=expiring'),
        ),
        const SizedBox(width: 8),
        stat(
          label: 'Last month',
          value: _rupees(lastMonth),
          hint: 'collected',
          color: AppTheme.ink,
          onTap: () => context.push('/staff/reports'),
        ),
      ],
    );
  }
}

// ─── Profit & loss (this month) ───────────────────────────────────────────────

/// Collected − expenses, the same rule Reports uses. Only built for roles that
/// can read expenses — RLS returns none otherwise and profit would be fake.
class _ProfitLossCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _ProfitLossCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenue = (data['monthRevenue'] as double?) ?? 0;
    final expenses = (data['monthExpenses'] as double?) ?? 0;
    final profit = (data['profit'] as double?) ?? 0;
    final margin = revenue > 0 ? (profit / revenue * 100).round() : null;
    final container = ProviderScope.containerOf(context, listen: false);

    Widget figure(String label, double value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _rupees(value.abs()),
              style: AppTheme.numberStyle(fontSize: 17, color: color),
            ),
          ),
        ],
      ),
    );

    Widget button(String label, IconData icon, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppTheme.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Profit & loss', style: AppTheme.sectionTitle),
              ),
              if (margin != null)
                Text(
                  '$margin% margin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: profit >= 0
                        ? AppTheme.statusActive
                        : AppTheme.statusDanger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'This month',
            style: TextStyle(fontSize: 12, color: AppTheme.inkHint),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              figure('Collected', revenue, AppTheme.ink),
              figure('Expenses', expenses, AppTheme.statusDanger),
              figure(
                profit >= 0 ? 'Profit' : 'Loss',
                profit,
                profit >= 0 ? AppTheme.statusActive : AppTheme.statusDanger,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              button('Add expense', AppIcons.add, () async {
                await showAddExpenseSheet(context);
                container.invalidate(dashboardDataProvider);
              }),
              const SizedBox(width: 8),
              button(
                'Full report',
                AppIcons.barChart,
                () => context.push('/staff/reports'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Breakdown (payment mode / expense category) ──────────────────────────────

String _methodLabel(String method) => switch (method) {
  'cash' => 'Cash',
  'upi' => 'UPI',
  'bank_transfer' => 'Bank transfer',
  'card' => 'Card',
  'online' || 'razorpay' => 'Online',
  _ => method.isEmpty ? 'Other' : method[0].toUpperCase() + method.substring(1),
};

/// A titled card of horizontal bars — one per key, largest first.
class _BreakdownCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, double> totals;
  final String Function(String) labelFor;
  final Color color;
  final String emptyText;
  final VoidCallback onTap;
  const _BreakdownCard({
    required this.title,
    required this.subtitle,
    required this.totals,
    required this.labelFor,
    required this.color,
    required this.emptyText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = totals.values.fold<double>(0, (s, v) => s + v);
    // ponytail: top 5, the rest folded into "Others" so the card stays short.
    final entries = totals.entries.toList();
    final shown = entries.take(5).toList();
    final rest = entries.skip(5).fold<double>(0, (s, e) => s + e.value);

    Widget bar(String label, double value) {
      final share = total > 0 ? value / total : 0.0;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                Text(
                  '${_rupees(value)} · ${(share * 100).round()}%',
                  style: AppTheme.numberStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: AppTheme.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: AppTheme.sectionTitle)),
                const Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: AppTheme.inkHint,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              total > 0 ? '$subtitle · ${_rupees(total)}' : subtitle,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
            ),
            if (total <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  emptyText,
                  style: const TextStyle(fontSize: 13, color: AppTheme.inkHint),
                ),
              )
            else ...[
              for (final e in shown) bar(labelFor(e.key), e.value),
              if (rest > 0) bar('Others', rest),
            ],
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
class NeedsAttention extends ConsumerWidget {
  final Map<String, dynamic> data;
  final bool canBilling;
  final bool canLeads;
  final bool canCheckIn;
  const NeedsAttention({
    super.key,
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
    final container = ProviderScope.containerOf(ctx, listen: false);
    await showAdaptiveSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CollectPaymentSheet(
        member: member,
        onPaid: () => container.invalidate(dashboardDataProvider),
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
  DateTime _paidAt = today;
  DateTime? _validTill;
  DateTime? _defaultTill;

  /// The open bill this collect settles, and whether it is an older bill
  /// (joining bill, old due, a balance already extended) rather than the
  /// current renewal — the server settles those without moving the plan.
  String? _invoiceId;
  bool _settlingOldBill = false;

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
    // The valid-till hint switches wording when the amount won't clear the bill.
    _amountCtrl.addListener(() => setState(() {}));
    _autofill();
  }

  bool get _isPartial {
    final amount = double.tryParse(_amountCtrl.text.trim());
    return _due != null && amount != null && amount < _due!;
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
            'next_payment_date, billing_interval_months, memberships(status, discount_amount, billing_interval_days, membership_plans(price, name, billing_interval, billing_interval_months))',
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
        // A day pass never advances, so it gets no valid-till row.
        if (active?['billing_interval_days'] == null) {
          _defaultTill = defaultValidTill(
            _nextPaymentDate,
            renewalMonths(
              plan,
              (data['billing_interval_months'] as num?)?.toInt(),
            ),
          );
          _validTill = _defaultTill;
        }
      });

      // If there's already an open/partial invoice for this member, its
      // amount (not the plan price) is the real total owed — pre-fill the
      // remaining balance instead of the full plan price.
      final openInvoices =
          (await client
                      .from('invoices')
                      .select('id, amount, due_at')
                      .eq('member_id', memberId)
                      .inFilter('status', ['open', 'partial'])
                      .order('created_at', ascending: true)
                  as List)
              .cast<Map<String, dynamic>>();
      final existing = preferredCollectInvoice(openInvoices, _nextPaymentDate);
      if (existing != null && mounted) {
        final invoiceAmount = (existing['amount'] as num).toDouble();
        final due = await invoiceDue(existing['id'] as String, invoiceAmount);
        if (!mounted) return;
        final dueDate = (existing['due_at'] as String?)?.split('T').first;
        setState(() {
          _due = due;
          _partlyPaid = due < invoiceAmount;
          _outstanding = due;
          _amountCtrl.text = due.toStringAsFixed(0);
          _invoiceId = existing['id'] as String;
          _settlingOldBill = !billRenewsPlan(
            dueDate: dueDate,
            nextPaymentDate: _nextPaymentDate,
          );
          if (_settlingOldBill) {
            _validTill = null;
            _defaultTill = null;
          }
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
    final dateError = paymentDatesError(
      _paidAt,
      _validTill,
      defaultTill: _defaultTill,
    );
    if (dateError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    final memberIdForCheck = widget.member['id'] as String;
    // Only a genuine duplicate is worth stopping. If the member still owes
    // money on an open bill, a second collection today is the rest of that
    // bill, not an accidental re-tap. A backdated entry is catch-up
    // bookkeeping, not a re-tap either.
    final backdated = paidAtParam(_paidAt) != null;
    final prior = _outstanding > 0 || backdated
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
      settlingPartialInvoice: _partlyPaid || _settlingOldBill,
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
    if (!mounted) return;
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
        // Pin the bill shown on screen so the server settles exactly it.
        invoiceId: _invoiceId,
        paidAt: paidAtParam(_paidAt),
        validTill: validTillParam(_validTill, _defaultTill),
      );

      if (!backdated) await LocalPaymentGuard.record(memberId, amount);

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
            PaymentDatesFields(
              paidAt: _paidAt,
              onPaidAt: (d) => setState(() => _paidAt = d),
              validTill: _validTill,
              defaultTill: _defaultTill,
              onValidTill: (d) => setState(() => _validTill = d),
              partial: _isPartial,
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
