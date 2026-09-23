import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _RevReport {
  final double totalRevenue;
  final double totalBilled;
  final double prevTotalRevenue;
  final int totalInvoices;
  final int paidCount;
  final int partialCount;
  final int failedCount;
  final int activeMembers;
  final double? avgDaysToPay;
  final List<(String label, double value)> chartData;
  final List<(String method, double amount)> paymentMethod;
  final List<(String bucket, double amount)> duesAging;

  const _RevReport({
    required this.totalRevenue,
    required this.totalBilled,
    required this.prevTotalRevenue,
    required this.totalInvoices,
    required this.paidCount,
    required this.partialCount,
    required this.failedCount,
    required this.activeMembers,
    required this.avgDaysToPay,
    required this.chartData,
    required this.paymentMethod,
    required this.duesAging,
  });

  double get collectionRate => totalBilled > 0 ? totalRevenue / totalBilled : 0;
  double get avgPerMember =>
      activeMembers > 0 ? totalRevenue / activeMembers : 0;
  double get trendPct {
    if (prevTotalRevenue <= 0) return totalRevenue > 0 ? 100 : 0;
    return ((totalRevenue - prevTotalRevenue) / prevTotalRevenue) * 100;
  }
}

class _MemReport {
  final int total;
  final int active;
  final int frozen;
  final int expired;
  final int cancelled;
  final int newLast30d;
  final double? avgTenureDays;
  final List<(String label, int count)> growthData;
  final List<(int months, int count)> planMix;
  final int leadsTotal;
  final int leadsTrial;
  final int leadsConverted;

  const _MemReport({
    required this.total,
    required this.active,
    required this.frozen,
    required this.expired,
    required this.cancelled,
    required this.newLast30d,
    required this.avgTenureDays,
    required this.growthData,
    required this.planMix,
    required this.leadsTotal,
    required this.leadsTrial,
    required this.leadsConverted,
  });

  double get leadConversionRate =>
      leadsTotal > 0 ? leadsConverted / leadsTotal : 0;
}

// ─── Providers ────────────────────────────────────────────────────────────────

// A preset period ('week' | 'month' | 'year'), or a custom range when [range]
// is set (period is then ignored). Record equality keeps the family cache key
// stable across rebuilds.
typedef _RevQuery = ({String period, DateTimeRange? range});

// The window every period-driven figure on this screen uses (revenue,
// expenses, new members), so they always describe the same dates.
// [to] is exclusive; null means "up to now".
({DateTime from, DateTime? to, String period}) _windowOf(_RevQuery query) {
  final range = query.range;
  if (range != null) {
    // Whole local days, end day inclusive.
    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(range.end.year, range.end.month, range.end.day + 1);
    // Daily points up to ~3 months, monthly beyond that.
    return (
      from: from,
      to: to,
      period: to.difference(from).inDays > 92 ? 'year' : 'month',
    );
  }
  final now = DateTime.now();
  return (
    from: switch (query.period) {
      'week' => now.subtract(const Duration(days: 7)),
      'year' => DateTime(now.year - 1, now.month, now.day),
      _ => DateTime(now.year, now.month - 1, now.day),
    },
    to: null,
    period: query.period,
  );
}

String _isoDate(DateTime d) => d.toIso8601String().split('T').first;

// Expense rows (category, amount) in the window. expense_date is a plain date,
// so the window is compared as local dates. RLS returns nothing without the
// expenses permission — callers must gate on it, or profit would read as
// "all revenue".
final _expensesReportProvider =
    FutureProvider.family<List<(String category, double amount)>, _RevQuery>((
      ref,
      query,
    ) async {
      ref.watch(gymDataVersionProvider); // refetch after a write elsewhere
      final gymId = await ref.watch(gymIdProvider.future);
      final w = _windowOf(query);
      var q = Supabase.instance.client
          .from('expenses')
          .select('category, amount')
          .eq('gym_id', gymId)
          .gte('expense_date', _isoDate(w.from));
      final to = w.to;
      if (to != null) q = q.lt('expense_date', _isoDate(to));
      final rows = await q;
      return (rows as List)
          .map(
            (e) => (
              (e['category'] as String?) ?? 'Other',
              (e['amount'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList();
    });

// Members who joined inside the window.
final _newMembersProvider = FutureProvider.family<int, _RevQuery>((
  ref,
  query,
) async {
  ref.watch(gymDataVersionProvider); // refetch after a write elsewhere
  final gymId = await ref.watch(gymIdProvider.future);
  final w = _windowOf(query);
  var q = Supabase.instance.client
      .from('members')
      .select('id')
      .eq('gym_id', gymId)
      .gte('joined_at', w.from.toUtc().toIso8601String());
  final to = w.to;
  if (to != null) q = q.lt('joined_at', to.toUtc().toIso8601String());
  final res = await q.count(CountOption.exact);
  return res.count;
});

final _revReportProvider = FutureProvider.family<_RevReport, _RevQuery>((
  ref,
  query,
) async {
  ref.watch(gymDataVersionProvider); // refetch after a write elsewhere
  final gymId = await ref.watch(gymIdProvider.future);
  final now = DateTime.now();
  final w = _windowOf(query);
  final from = w.from;
  final to = w.to;
  final period = w.period;

  const mon = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final raw =
      await Supabase.instance.client.rpc(
            'get_revenue_report',
            params: {
              'p_gym_id': gymId,
              // toUtc(): a local DateTime serialises without an offset and
              // the DB (UTC) would read IST midnight as UTC midnight.
              'p_from': from.toUtc().toIso8601String(),
              'p_period': period,
              if (to != null) 'p_to': to.toUtc().toIso8601String(),
              // Chart buckets follow the device's local day, not UTC's.
              'p_utc_offset_min': now.timeZoneOffset.inMinutes,
            },
          )
          as Map<String, dynamic>;

  final chartData = ((raw['chart_data'] as List?) ?? []).map((e) {
    final key = e['key'] as String;
    final value = (e['value'] as num).toDouble();
    final parts = key.split('-');
    final d = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      parts.length > 2 ? int.parse(parts[2]) : 1,
    );
    final label = period == 'year'
        ? mon[d.month - 1]
        : '${d.day} ${mon[d.month - 1]}';
    return (label, value);
  }).toList();

  final paymentMethod = ((raw['payment_method'] as List?) ?? [])
      .map((e) => (e['method'] as String, (e['amount'] as num).toDouble()))
      .toList();

  final duesAging = ((raw['dues_aging'] as List?) ?? [])
      .map((e) => (e['bucket'] as String, (e['amount'] as num).toDouble()))
      .toList();

  return _RevReport(
    totalRevenue: (raw['total_revenue'] as num).toDouble(),
    totalBilled: (raw['total_billed'] as num).toDouble(),
    prevTotalRevenue: (raw['prev_total_revenue'] as num).toDouble(),
    totalInvoices: (raw['total_invoices'] as num).toInt(),
    paidCount: (raw['paid_count'] as num).toInt(),
    partialCount: (raw['partial_count'] as num?)?.toInt() ?? 0,
    failedCount: (raw['failed_count'] as num).toInt(),
    activeMembers: (raw['active_members'] as num).toInt(),
    avgDaysToPay: (raw['avg_days_to_pay'] as num?)?.toDouble(),
    chartData: chartData,
    paymentMethod: paymentMethod,
    duesAging: duesAging,
  );
});

final _memReportProvider = FutureProvider<_MemReport>((ref) async {
  ref.watch(gymDataVersionProvider); // refetch after a write elsewhere
  final gymId = await ref.watch(gymIdProvider.future);

  const mon = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final raw =
      await Supabase.instance.client.rpc(
            'get_member_stats',
            params: {'p_gym_id': gymId},
          )
          as Map<String, dynamic>;

  final growthData = ((raw['growth_data'] as List?) ?? []).map((e) {
    final key = e['key'] as String;
    final count = (e['count'] as num).toInt();
    final month = int.parse(key.split('-')[1]);
    return (mon[month - 1], count);
  }).toList();

  final planMix = ((raw['plan_mix'] as List?) ?? [])
      .map((e) => ((e['months'] as num).toInt(), (e['count'] as num).toInt()))
      .toList();

  return _MemReport(
    total: (raw['total'] as num).toInt(),
    active: (raw['active'] as num).toInt(),
    frozen: (raw['frozen'] as num).toInt(),
    expired: (raw['expired'] as num).toInt(),
    cancelled: (raw['cancelled'] as num).toInt(),
    newLast30d: (raw['new_last_30d'] as num).toInt(),
    avgTenureDays: (raw['avg_tenure_days'] as num?)?.toDouble(),
    growthData: growthData,
    planMix: planMix,
    leadsTotal: (raw['leads_total'] as num).toInt(),
    leadsTrial: (raw['leads_trial'] as num).toInt(),
    leadsConverted: (raw['leads_converted'] as num).toInt(),
  );
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _compactRev(double amount) => formatCurrencyCompact(amount);

// "5 Sep – 18 Sep", or with years when the range isn't in the current year.
String _rangeLabel(DateTimeRange r) {
  final thisYear = DateTime.now().year;
  final fmt = r.start.year == thisYear && r.end.year == thisYear
      ? formatDateShort
      : formatDate;
  if (DateUtils.isSameDay(r.start, r.end)) return fmt(r.start);
  return '${fmt(r.start)} – ${fmt(r.end)}';
}

String _planLabel(int months) => switch (months) {
  1 => 'Monthly',
  3 => 'Quarterly',
  6 => 'Half-yearly',
  12 => 'Yearly',
  _ => '$months mo',
};

String _methodLabel(String method) => switch (method) {
  'upi' => 'UPI',
  'cash' => 'Cash',
  'card' => 'Card',
  'bank_transfer' => 'Bank transfer',
  _ => method,
};

Color _methodColor(int i) => const [
  AppTheme.ink,
  AppTheme.statusActive,
  AppTheme.accent,
  AppTheme.statusWarn,
][i % 4];

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'month';
  DateTimeRange? _customRange;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          ),
      helpText: 'Select report dates',
    );
    if (picked != null && mounted) setState(() => _customRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ResponsiveContent(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      // Opened directly (web refresh / link) there's nothing
                      // to pop and pop() leaves a blank screen.
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/staff/dashboard'),
                      icon: const Icon(
                        AppIcons.arrowBack,
                        size: 20,
                        color: AppTheme.ink,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(_revReportProvider);
                    ref.invalidate(_memReportProvider);
                    ref.invalidate(_expensesReportProvider);
                    ref.invalidate(_newMembersProvider);
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Canvas 1i is one continuous scroll: revenue and
                        // collections first, then memberships, then expenses.
                        _RevenueTab(
                          period: _period,
                          customRange: _customRange,
                          onPeriodChanged: (p) => setState(() {
                            _period = p;
                            _customRange = null;
                          }),
                          onCustomTap: _pickCustomRange,
                        ),
                        const SizedBox(height: 20),
                        _MembersTab(
                          query: (period: _period, range: _customRange),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueTab extends ConsumerWidget {
  final String period;
  final DateTimeRange? customRange;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onCustomTap;
  const _RevenueTab({
    required this.period,
    required this.customRange,
    required this.onPeriodChanged,
    required this.onCustomTap,
  });

  static const _periods = [('week', '7d'), ('month', '30d'), ('year', '12m')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = customRange;
    final _RevQuery query = (period: period, range: range);
    final async = ref.watch(_revReportProvider(query));
    final canSeeExpenses = ref.watch(
      gymPermissionProvider((GymModule.expenses, GymAction.view)),
    );
    final title = range != null
        ? _rangeLabel(range)
        : switch (period) {
            'week' => 'Last 7 days',
            'year' => 'Last 12 months',
            _ => 'Last 30 days',
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero: collected revenue + trend + chart
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          decoration: AppTheme.darkCardDecoration(radius: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Collected · $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onDarkSoft,
                      ),
                    ),
                  ),
                  ..._periods.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _HeroPeriodChip(
                        label: p.$2,
                        active: range == null && period == p.$1,
                        onTap: () => onPeriodChanged(p.$1),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _HeroPeriodChip(
                      label: 'Custom',
                      active: range != null,
                      onTap: onCustomTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              async.when(
                loading: () => const SizedBox(height: 40),
                error: (_, _) => const Text(
                  'Could not load. Pull down to retry.',
                  style: TextStyle(color: AppTheme.inkSoft, fontSize: 12),
                ),
                data: (r) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _compactRev(r.totalRevenue),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(
                            r.trendPct >= 0 ? '↑' : '↓',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: r.trendPct >= 0
                                  ? AppTheme.mintOnDark
                                  : AppTheme.statusDanger,
                            ),
                          ),
                          Text(
                            '${r.trendPct.abs().toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: r.trendPct >= 0
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
              const SizedBox(height: 12),
              SizedBox(
                height: 130,
                child: async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.mintOnDark,
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  // One point draws a lone dot that looks broken (a one-day
                  // range, or all money collected on one day) — say it instead.
                  data: (r) => r.chartData.length < 2
                      ? Center(
                          child: Text(
                            r.chartData.isEmpty
                                ? 'No revenue data for this period'
                                : 'All collected on ${r.chartData.first.$1}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.onDarkSoft,
                            ),
                          ),
                        )
                      : _HeroLineChart(data: r.chartData),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Profit & loss for the same dates: collected minus expenses (the
        // dashboard's profit rule). Hidden without the expenses permission —
        // RLS would return no expenses and profit would read as all revenue.
        if (canSeeExpenses) ...[
          _ProfitLossCard(
            revenue: async.whenData((r) => r.totalRevenue),
            expenses: ref.watch(_expensesReportProvider(query)),
            periodLabel: title,
          ),
          const SizedBox(height: 14),
        ],

        // Collection rate / Avg per member / Avg days to pay
        async.when(
          loading: () => _kpiShimmerRow3(),
          error: (_, _) => const _ErrorText(),
          data: (r) => Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Collection rate',
                  value: '${(r.collectionRate * 100).toStringAsFixed(0)}%',
                  sub:
                      '${_compactRev(r.totalRevenue)} of ${_compactRev(r.totalBilled)} billed',
                  valueColor: AppTheme.statusActive,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Avg / member',
                  value: formatCurrency(r.avgPerMember),
                  sub: 'per active member',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'Avg days to pay',
                  value: r.avgDaysToPay == null
                      ? '—'
                      : r.avgDaysToPay!.abs().toStringAsFixed(1),
                  sub: r.avgDaysToPay == null
                      ? 'no paid invoices yet'
                      : (r.avgDaysToPay! >= 0
                            ? 'after due date'
                            : 'before due date'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Payment method donut + dues aging — side by side once there's room
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) {
            final donut = r.paymentMethod.isEmpty
                ? null
                : _DonutCard(
                    title: 'Payment method',
                    entries: r.paymentMethod
                        .asMap()
                        .entries
                        .map(
                          (e) => (
                            _methodLabel(e.value.$1),
                            e.value.$2,
                            _methodColor(e.key),
                          ),
                        )
                        .toList(),
                  );
            final duesAging = r.duesAging.isEmpty
                ? null
                : _DuesAgingCard(entries: r.duesAging);
            if (donut == null && duesAging == null)
              return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child:
                  ResponsiveContent.isWide(context) &&
                      donut != null &&
                      duesAging != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: donut),
                        const SizedBox(width: 12),
                        Expanded(child: duesAging),
                      ],
                    )
                  : Column(
                      children: [
                        if (donut != null) donut,
                        if (donut != null && duesAging != null)
                          const SizedBox(height: 14),
                        if (duesAging != null) duesAging,
                      ],
                    ),
            );
          },
        ),

        // Invoice counts (existing ops data, not in the mockup — kept)
        async.when(
          loading: () => _kpiShimmerRow3(),
          error: (_, _) => const _ErrorText(),
          data: (r) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Invoices',
                      value: '${r.totalInvoices}',
                      sub: '${r.paidCount} paid',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      label: 'Paid',
                      value: '${r.paidCount}',
                      sub: 'of ${r.totalInvoices}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Partial',
                      value: '${r.partialCount}',
                      sub: 'still owing',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      label: 'Failed',
                      value: '${r.failedCount}',
                      sub: r.totalInvoices > 0
                          ? '${((r.failedCount / r.totalInvoices) * 100).toStringAsFixed(1)}%'
                          : '0%',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Members tab ──────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  // Same dates as the revenue section — drives "New members".
  final _RevQuery query;
  const _MembersTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_memReportProvider);
    final newMembers = ref.watch(_newMembersProvider(query));
    final range = query.range;
    final periodLabel = range != null
        ? _rangeLabel(range)
        : switch (query.period) {
            'week' => 'last 7 days',
            'year' => 'last 12 months',
            _ => 'last 30 days',
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero: active members + chart
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          decoration: AppTheme.darkCardDecoration(radius: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Active members',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onDarkSoft,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    // Describes the chart below (joins per month), which is
                    // always the last 6 months — not a filter.
                    child: const Text(
                      'Joins · last 6 months',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              async.when(
                loading: () => const SizedBox(height: 40),
                error: (_, _) => const Text(
                  'Could not load. Pull down to retry.',
                  style: TextStyle(color: AppTheme.inkSoft, fontSize: 12),
                ),
                data: (r) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${r.active}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onDark,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Text(
                            '↑',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mintOnDark,
                            ),
                          ),
                          Text(
                            '${newMembers.value ?? '…'} new',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mintOnDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 130,
                child: async.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.mintOnDark,
                    ),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (r) {
                    final last6 = r.growthData.length > 6
                        ? r.growthData.sublist(r.growthData.length - 6)
                        : r.growthData;
                    final chartData = last6
                        .map((e) => (e.$1, e.$2.toDouble()))
                        .toList();
                    return chartData.isEmpty
                        ? const Center(
                            child: Text(
                              'No member data yet',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.onDarkSoft,
                              ),
                            ),
                          )
                        : _HeroLineChart(data: chartData);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Avg tenure / new this month
        async.when(
          loading: () => _kpiShimmerRow3(),
          error: (_, _) => const _ErrorText(),
          data: (r) => Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Avg tenure',
                  value: r.avgTenureDays == null
                      ? '—'
                      : '${(r.avgTenureDays! / 30.44).toStringAsFixed(1)}mo',
                  sub: 'per member',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'New members',
                  value: switch (newMembers) {
                    AsyncData(:final value) => '$value',
                    AsyncError() => '—',
                    _ => '…',
                  },
                  sub: periodLabel,
                  valueColor: AppTheme.statusActive,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Plan mix donut + lead conversion — side by side once there's room
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) {
            final donut = r.planMix.isEmpty
                ? null
                : _DonutCard(
                    title: 'Plan mix',
                    entries: r.planMix
                        .asMap()
                        .entries
                        .map(
                          (e) => (
                            _planLabel(e.value.$1),
                            e.value.$2.toDouble(),
                            _methodColor(e.key),
                          ),
                        )
                        .toList(),
                  );
            final leadConversion = r.leadsTotal == 0
                ? null
                : _LeadConversionCard(report: r);
            if (donut == null && leadConversion == null)
              return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child:
                  ResponsiveContent.isWide(context) &&
                      donut != null &&
                      leadConversion != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: donut),
                        const SizedBox(width: 12),
                        Expanded(child: leadConversion),
                      ],
                    )
                  : Column(
                      children: [
                        if (donut != null) donut,
                        if (donut != null && leadConversion != null)
                          const SizedBox(height: 14),
                        if (leadConversion != null) leadConversion,
                      ],
                    ),
            );
          },
        ),

        // Member status breakdown (existing feature, not in the mockup — kept)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Status breakdown',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 16),
              async.when(
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const _ErrorText(),
                data: (r) => _StatusDonut(report: r),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Hero line chart (dark card, dotted trend line) ────────────────────────────

class _HeroLineChart extends StatelessWidget {
  final List<(String label, double value)> data;
  const _HeroLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.$2))
        .toList();

    final maxY = data.map((e) => e.$2).fold<double>(0, (a, b) => a > b ? a : b);
    final showDots = data.length <= 12;
    final step = (data.length / 6).ceil().clamp(1, 999);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.25,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.mintOnDark,
            barWidth: 2.5,
            dotData: FlDotData(
              show: showDots,
              getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                radius: 3,
                color: AppTheme.darkCard,
                strokeWidth: 2,
                strokeColor: AppTheme.mintOnDark,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.mintOnDark.withValues(alpha: 0.35),
                  AppTheme.mintOnDark.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length)
                  return const SizedBox.shrink();
                if (idx % step != 0 && idx != data.length - 1)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data[idx].$1,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppTheme.onDarkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.darkCard2,
            tooltipRoundedRadius: 6,
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    s.y == s.y.roundToDouble()
                        ? s.y.toInt().toString()
                        : formatCurrency(s.y),
                    const TextStyle(
                      color: AppTheme.onDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Profit & loss + expenses ─────────────────────────────────────────────────

class _ProfitLossCard extends StatelessWidget {
  final AsyncValue<double> revenue;
  final AsyncValue<List<(String category, double amount)>> expenses;
  final String periodLabel;
  const _ProfitLossCard({
    required this.revenue,
    required this.expenses,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Profit & loss',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  periodLabel,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (revenue.hasError || expenses.hasError)
            const _ErrorText()
          else if (!revenue.hasValue || !expenses.hasValue)
            const SizedBox(
              height: 96,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._body(context, revenue.requireValue, expenses.requireValue),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    double collected,
    List<(String, double)> rows,
  ) {
    final byCategory = <String, double>{};
    for (final (category, amount) in rows) {
      byCategory[category] = (byCategory[category] ?? 0) + amount;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final spent = byCategory.values.fold<double>(0, (s, v) => s + v);
    final net = collected - spent;
    final isLoss = net < 0;
    final margin = collected > 0 ? (net / collected * 100).round() : null;

    return [
      _line('Collected', formatCurrency(collected), AppTheme.ink),
      const SizedBox(height: 8),
      _line(
        'Expenses',
        spent > 0 ? '− ${formatCurrency(spent)}' : formatCurrency(0),
        AppTheme.ink,
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoss ? 'Net loss' : 'Net profit',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
                // A negative margin ("-1402% of collected") reads as noise;
                // a loss just says what happened.
                if (isLoss || margin != null)
                  Text(
                    isLoss ? 'Spent more than collected' : '$margin% of collected',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.inkHint,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${isLoss ? '− ' : ''}${formatCurrency(net.abs())}',
            style: AppTheme.numberStyle(
              fontSize: 24,
              color: isLoss ? AppTheme.statusDanger : AppTheme.statusActive,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Expenses by category',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.inkSoft,
        ),
      ),
      const SizedBox(height: 10),
      if (categories.isEmpty)
        const Text(
          'No expenses logged for these dates.',
          style: TextStyle(fontSize: 12.5, color: AppTheme.inkHint),
        )
      else
        for (final (i, c) in categories.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _categoryBar(c.key, c.value, spent, _methodColor(i)),
        ],
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => context.push('/staff/expenses'),
          child: const Text('View all expenses'),
        ),
      ),
    ];
  }

  Widget _line(String label, String value, Color color) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );

  Widget _categoryBar(String name, double amount, double total, Color color) {
    final share = total > 0 ? amount / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
            ),
            Text(
              '${formatCurrency(amount)} · ${(share * 100).round()}%',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 6,
            color: color,
            backgroundColor: AppTheme.surface2,
          ),
        ),
      ],
    );
  }
}

// ─── Hero period chip (on dark card) ────────────────────────────────────────

class _HeroPeriodChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _HeroPeriodChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.2 : 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? AppTheme.onDark : AppTheme.onDarkSoft,
          ),
        ),
      ),
    );
  }
}

// ─── Metric card (small stat tile) ─────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppTheme.ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: const TextStyle(fontSize: 10, color: AppTheme.inkHint),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ─── Generic donut card (payment method / plan mix) ────────────────────────────

class _DonutCard extends StatelessWidget {
  final String title;
  final List<(String label, double value, Color color)> entries;
  const _DonutCard({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (a, e) => a + e.$2);
    final sections = entries
        .where((e) => e.$2 > 0)
        .map(
          (e) => PieChartSectionData(
            value: e.$2,
            color: e.$3,
            radius: 26,
            title: '',
            showTitle: false,
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 24,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 10),
                ...entries.map((e) {
                  final pct = total > 0
                      ? (e.$2 / total * 100).toStringAsFixed(0)
                      : '0';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: e.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.$1,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dues aging card ──────────────────────────────────────────────────────────

class _DuesAgingCard extends StatelessWidget {
  final List<(String bucket, double amount)> entries;
  const _DuesAgingCard({required this.entries});

  static const _labels = {
    '0-7': '0–7 days',
    '8-15': '8–15 days',
    '15+': '15+ days',
  };
  static const _colors = {
    '0-7': AppTheme.statusWarn,
    '8-15': AppTheme.statusDanger,
    '15+': Color(0xFF8B2E1F),
  };

  @override
  Widget build(BuildContext context) {
    final maxAmount = entries.fold<double>(0, (a, e) => e.$2 > a ? e.$2 : a);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dues aging',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 14),
          for (final e in entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _labels[e.$1] ?? e.$1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ),
                Text(
                  formatCurrency(e.$2),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: maxAmount > 0 ? e.$2 / maxAmount : 0,
                minHeight: 6,
                backgroundColor: AppTheme.surface2,
                color: _colors[e.$1] ?? AppTheme.statusNeutral,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ─── Lead conversion card ───────────────────────────────────────────────────────

class _LeadConversionCard extends StatelessWidget {
  final _MemReport report;
  const _LeadConversionCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Leads', report.leadsTotal, AppTheme.statusNeutral),
      ('Trials', report.leadsTrial, AppTheme.statusWarn),
      ('Joined', report.leadsConverted, AppTheme.statusActive),
    ];
    final max = report.leadsTotal > 0 ? report.leadsTotal : 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Lead conversion',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${(report.leadConversionRate * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.statusActive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final r in rows) ...[
            Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    r.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: r.$2 / max,
                      minHeight: 16,
                      backgroundColor: AppTheme.surface2,
                      color: r.$3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${r.$2}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ─── Status donut chart (member status — existing feature) ────────────────────

class _StatusDonut extends StatelessWidget {
  final _MemReport report;
  const _StatusDonut({required this.report});

  static const _colors = {
    'Active': Color(0xFF2E7D32),
    'Expired': Color(0xFFE65100),
    'Frozen': Color(0xFF1565C0),
    'Cancelled': Color(0xFFC62828),
  };

  @override
  Widget build(BuildContext context) {
    final entries = [
      ('Active', report.active),
      ('Expired', report.expired),
      ('Frozen', report.frozen),
      ('Cancelled', report.cancelled),
    ].where((e) => e.$2 > 0).toList();

    if (entries.isEmpty) {
      return const _EmptyChart('No member data yet');
    }

    final sections = entries
        .map(
          (e) => PieChartSectionData(
            value: e.$2.toDouble(),
            color: _colors[e.$1] ?? AppTheme.inkSoft,
            radius: 48,
            title: '',
            showTitle: false,
          ),
        )
        .toList();

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 44,
                sectionsSpace: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _colors[e.$1] ?? AppTheme.inkSoft,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${e.$2}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Could not load. Pull down to retry.',
      style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
    );
  }
}

Widget _kpiShimmerRow3() {
  return Row(
    children: [
      Expanded(child: _ShimmerBox(height: 80)),
      const SizedBox(width: 8),
      Expanded(child: _ShimmerBox(height: 80)),
      const SizedBox(width: 8),
      Expanded(child: _ShimmerBox(height: 80)),
    ],
  );
}

class _ShimmerBox extends StatelessWidget {
  final double height;
  const _ShimmerBox({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
