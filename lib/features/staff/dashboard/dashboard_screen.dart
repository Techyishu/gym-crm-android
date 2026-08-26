import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/billing/billing_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/whats_new.dart';
import '../../../core/access/role_access.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../members/members_screen.dart' show showAddMemberSheet;
import '../notifications/notifications_screen.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

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
          .select('amount, payments(amount, status)')
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
    'activeMembers': counts[0].count ?? 0,
    'todayCheckins': counts[1].count ?? 0,
    'newMembersMonth': counts[2].count ?? 0,
    'allTimeCheckins': counts[3].count ?? 0,
    'planCount': counts[4].count ?? 0,
    'leadsThisWeek': counts[5].count ?? 0,
    'memberCount': counts[6].count ?? 0,
    'collectedToday': collectedToday,
    'todayPayments': todayPaid.length,
    'pendingRevenue': pendingRevenue,
    'monthRevenue': monthRevenue,
    'growthPct': growthPct,
    'renewals': rows[4],
    'recentPaid': recentPaid,
    'todayCheckinsList': rows[6],
    'recentLeads': rows[7],
    'monthExpenses': sum(rows[8]),
    'profit': monthRevenue - sum(rows[8]),
  };
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              Icons.cloud_off_outlined,
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
                icon: const Icon(Icons.refresh, size: 16),
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
    final canExpenses = RoleAccess.canSeeExpenses(role);

    final profile = ref.watch(staffProfileProvider).valueOrNull;
    final gym = profile?['gyms'] as Map<String, dynamic>?;
    final gymName = gym?['name'] as String? ?? 'My Gym';
    final ownerName =
        (profile?['full_name'] as String?) ??
        (Supabase.instance.client.auth.currentUser?.email ?? '');

    final renewals = data['renewals'] as List<dynamic>;

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
      _Header(
        gymName: gymName,
        ownerName: ownerName,
        gym: gym,
        showBilling: canBilling,
      ),
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

    final leftColumn = [
      if (canBilling) ...[
        _CollectedHero(data: data, canExpenses: canExpenses),
        const SizedBox(height: 10),
      ],
      _StatRow(
        active: (data['activeMembers'] as int?) ?? 0,
        checkins: (data['todayCheckins'] as int?) ?? 0,
        renewals: renewals.length,
      ),
      const SizedBox(height: 10),
      _QuickActions(canCollect: canCollect, canLeads: canLeads),
    ];

    final rightColumn = [
      _PaymentDueToday(data: data, canCollect: canCollect),
      const SizedBox(height: 16),
      _UpcomingPayments(data: data, canCollect: canCollect),
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
                              Icons.check,
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
                        Icons.chevron_right,
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
    final items = [
      // Opens the add-member sheet directly instead of routing to the
      // members list first — same shortcut the dashboard checklist uses.
      (
        icon: Icons.person_add_outlined,
        label: 'Add member',
        accent: !canCollect,
        onTap: () => showAddMemberSheet(
          context,
        ).then((_) => ref.invalidate(_dashboardDataProvider)),
      ),
      if (canCollect)
        (
          icon: Icons.payments_outlined,
          label: 'Collect payment',
          accent: true,
          onTap: () => context.push('/staff/billing'),
        ),
      if (canLeads)
        (
          icon: Icons.person_outline,
          label: 'Add lead',
          accent: false,
          onTap: () => context.push('/staff/leads'),
        ),
      (
        icon: Icons.qr_code_scanner,
        label: 'Check in',
        accent: false,
        onTap: () => context.push('/staff/check-in'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: items
            .map(
              (item) => Expanded(
                child: GestureDetector(
                  onTap: item.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: item.accent
                              ? AppTheme.accent
                              : AppTheme.surface2,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          item.icon,
                          size: 18,
                          color: item.accent ? Colors.white : AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

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
                        Icons.check,
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
                        icon: Icons.call_outlined,
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
  final String ownerName;
  final Map<String, dynamic>? gym;
  final bool showBilling;
  const _Header({
    required this.gymName,
    required this.ownerName,
    this.gym,
    this.showBilling = false,
  });

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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
    final now = DateTime.now();
    final dateLabel =
        '${_weekdays[now.weekday - 1]} · ${now.day} ${_months[now.month - 1]}';
    final unreadCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                gymName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  letterSpacing: -0.4,
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
                        Icons.sell_outlined,
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
                        Icons.chevron_right,
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
        GestureDetector(
          onTap: () => showWhatsNewSheet(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.campaign_outlined,
              size: 19,
              color: AppTheme.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => context.push('/staff/notifications'),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.notifications_none,
                  size: 19,
                  color: AppTheme.ink,
                ),
              ),
              if (unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
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
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => context.push('/staff/settings'),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Text(
              initialsOf(ownerName.isEmpty ? gymName : ownerName),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
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

class _CollectedHero extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool canExpenses;
  const _CollectedHero({required this.data, required this.canExpenses});

  @override
  Widget build(BuildContext context) {
    final collected = (data['collectedToday'] as double?) ?? 0;
    final outstanding = (data['pendingRevenue'] as double?) ?? 0;
    final renewals = (data['renewals'] as List<dynamic>? ?? const []).length;
    final expenses = (data['monthExpenses'] as double?) ?? 0;
    final profit = (data['profit'] as double?) ?? 0;

    return GestureDetector(
      onTap: () => context.push('/staff/billing'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: AppTheme.darkCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Needs attention today',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.onDarkSoft,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _rupees(outstanding),
                      style: AppTheme.numberStyle(
                        fontSize: 32,
                        color: AppTheme.onDark,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    outstanding > 0 ? 'to collect' : 'all caught up',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: outstanding > 0
                          ? AppTheme.statusWarn
                          : AppTheme.mintOnDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Collected today',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.onDarkSoft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _rupees(collected),
                          style: AppTheme.numberStyle(
                            fontSize: 18,
                            color: AppTheme.onDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Memberships due in 7 days',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.onDarkSoft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$renewals',
                        style: AppTheme.numberStyle(
                          fontSize: 18,
                          color: AppTheme.onDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (canExpenses) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => context.push('/staff/expenses'),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expenses this month',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.onDarkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(expenses),
                            style: AppTheme.numberStyle(
                              fontSize: 16,
                              color: AppTheme.onDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profit',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.onDarkSoft,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(profit),
                            style: AppTheme.numberStyle(
                              fontSize: 16,
                              color: profit >= 0
                                  ? AppTheme.mintOnDark
                                  : AppTheme.statusDanger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stat tiles row ───────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final int active, checkins, renewals;
  const _StatRow({
    required this.active,
    required this.checkins,
    required this.renewals,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatTileLight(
            label: 'Active members',
            value: '$active',
            onTap: () => context.push('/staff/members'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTileLight(
            label: 'Checked in today',
            value: '$checkins',
            onTap: () => context.push('/staff/check-in'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatTileLight(
            label: 'Due in 7 days',
            value: '$renewals',
            onTap: () => context.push('/staff/upcoming-payments'),
          ),
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

// ─── Upcoming payments ─────────────────────────────────────────────────────────

class _UpcomingPayments extends ConsumerWidget {
  final Map<String, dynamic> data;
  final bool canCollect;
  const _UpcomingPayments({required this.data, required this.canCollect});

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
    // Exclude today's dues — those surface in the "Payment due today" section.
    final renewals = (data['renewals'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((m) {
          final npd = m['next_payment_date'] as String?;
          if (npd == null) return false;
          final d = DateTime.parse(npd);
          return DateTime(d.year, d.month, d.day).isAfter(today);
        })
        .toList();
    if (renewals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Upcoming payments',
          actionLabel: 'See all',
          onAction: () => context.push('/staff/upcoming-payments'),
        ),
        const SizedBox(height: 10),
        CardList(
          children: renewals.map((m) {
            final npd = m['next_payment_date'] as String?;
            final days = npd != null
                ? DateTime.parse(npd).difference(now).inDays
                : 0;
            final subtitle = 'Upcoming in $days day${days == 1 ? '' : 's'}';
            return _AttentionRow(
              member: m,
              subtitle: subtitle,
              subColor: AppTheme.statusWarn,
              canCollect: canCollect,
              collectLabel: 'Collect early',
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

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('upi', 'UPI', Icons.qr_code_outlined),
    ('bank_transfer', 'Bank Transfer', Icons.account_balance_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
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
          _amountCtrl.text = due.toStringAsFixed(0);
        });
      } else {
        _due = finalPrice;
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
    final prior = await LocalPaymentGuard.check(memberIdForCheck);
    if (prior != null && mounted) {
      final firstName = widget.member['first_name'] as String? ?? '';
      final lastName = widget.member['last_name'] as String? ?? '';
      final name = '$firstName $lastName'.trim();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already collected today'),
          content: Text(
            '$currencySymbol${prior.amount.toStringAsFixed(0)} was already collected '
            'from $name today at '
            '${prior.at.hour.toString().padLeft(2, '0')}:${prior.at.minute.toString().padLeft(2, '0')}. '
            'Refresh the member before collecting another renewal.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final early = await confirmEarlyRenewalIfNeeded(
      context,
      nextPaymentDate: _nextPaymentDate,
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
                  icon: const Icon(Icons.close),
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
                    Icons.person_outline,
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
