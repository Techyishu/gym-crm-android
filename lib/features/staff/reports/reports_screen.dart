import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _RevReport {
  final double totalRevenue;
  final double totalBilled;
  final double prevTotalRevenue;
  final int totalInvoices;
  final int paidCount;
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
    required this.failedCount,
    required this.activeMembers,
    required this.avgDaysToPay,
    required this.chartData,
    required this.paymentMethod,
    required this.duesAging,
  });

  double get collectionRate => totalBilled > 0 ? totalRevenue / totalBilled : 0;
  double get avgPerMember => activeMembers > 0 ? totalRevenue / activeMembers : 0;
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

  double get leadConversionRate => leadsTotal > 0 ? leadsConverted / leadsTotal : 0;
}

// ─── Providers ────────────────────────────────────────────────────────────────

final _revReportProvider =
    FutureProvider.family<_RevReport, String>((ref, period) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final now = DateTime.now();
  final from = switch (period) {
    'week' => now.subtract(const Duration(days: 7)),
    'year' => DateTime(now.year - 1, now.month, now.day),
    _ => DateTime(now.year, now.month - 1, now.day),
  };

  const mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final raw = await Supabase.instance.client.rpc('get_revenue_report', params: {
    'p_gym_id': gymId,
    'p_from': from.toIso8601String(),
    'p_period': period,
  }) as Map<String, dynamic>;

  final chartData = ((raw['chart_data'] as List?) ?? []).map((e) {
    final key = e['key'] as String;
    final value = (e['value'] as num).toDouble();
    final parts = key.split('-');
    final d = DateTime(int.parse(parts[0]), int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2]) : 1);
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
    failedCount: (raw['failed_count'] as num).toInt(),
    activeMembers: (raw['active_members'] as num).toInt(),
    avgDaysToPay: (raw['avg_days_to_pay'] as num?)?.toDouble(),
    chartData: chartData,
    paymentMethod: paymentMethod,
    duesAging: duesAging,
  );
});

final _memReportProvider = FutureProvider<_MemReport>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);

  const mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final raw = await Supabase.instance.client.rpc('get_member_stats', params: {
    'p_gym_id': gymId,
  }) as Map<String, dynamic>;

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

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _tab = 'revenue';
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 20, color: AppTheme.ink),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const SizedBox(width: 4),
                  const Text('Reports',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(_revReportProvider);
                  ref.invalidate(_memReportProvider);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TabSwitcher(
                        tab: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                      ),
                      const SizedBox(height: 16),
                      if (_tab == 'revenue')
                        _RevenueTab(
                          period: _period,
                          onPeriodChanged: (p) => setState(() => _period = p),
                        )
                      else
                        const _MembersTab(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab switcher ─────────────────────────────────────────────────────────────

class _TabSwitcher extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onChanged;
  const _TabSwitcher({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.activeBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _TabBtn(label: 'Revenue', value: 'revenue', current: tab, onTap: onChanged),
          _TabBtn(label: 'Members', value: 'members', current: tab, onTap: onChanged),
        ],
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;
  const _TabBtn({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? AppTheme.ink : AppTheme.inkHint,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Revenue tab ──────────────────────────────────────────────────────────────

class _RevenueTab extends ConsumerWidget {
  final String period;
  final ValueChanged<String> onPeriodChanged;
  const _RevenueTab({required this.period, required this.onPeriodChanged});

  static const _periods = [
    ('week', '7d'),
    ('month', '30d'),
    ('year', '12m'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_revReportProvider(period));
    final now = DateTime.now();

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
                  Text('Collected · ${_monthNames[now.month - 1]}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
                  const Spacer(),
                  ..._periods.map((p) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _HeroPeriodChip(
                          label: p.$2,
                          active: period == p.$1,
                          onTap: () => onPeriodChanged(p.$1),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 6),
              async.when(
                loading: () => const SizedBox(height: 40),
                error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppTheme.statusDanger, fontSize: 12)),
                data: (r) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_compactRev(r.totalRevenue),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppTheme.onDark, letterSpacing: -0.5)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Text(r.trendPct >= 0 ? '↑' : '↓',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mintOnDark)),
                          Text('${r.trendPct.abs().toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mintOnDark)),
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
                  loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.mintOnDark)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (r) => r.chartData.isEmpty
                      ? const Center(child: Text('No revenue data for this period',
                          style: TextStyle(fontSize: 11, color: AppTheme.onDarkSoft)))
                      : _HeroLineChart(data: r.chartData),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Collection rate / Avg per member / Avg days to pay
        async.when(
          loading: () => _kpiShimmerRow3(),
          error: (e, _) => _ErrorText('$e'),
          data: (r) => Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Collection rate',
                  value: '${(r.collectionRate * 100).toStringAsFixed(0)}%',
                  sub: '${_compactRev(r.totalRevenue)} of ${_compactRev(r.totalBilled)} billed',
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
                  value: r.avgDaysToPay == null ? '—' : r.avgDaysToPay!.abs().toStringAsFixed(1),
                  sub: r.avgDaysToPay == null
                      ? 'no paid invoices yet'
                      : (r.avgDaysToPay! >= 0 ? 'after due date' : 'before due date'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Payment method donut
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) => r.paymentMethod.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DonutCard(
                    title: 'Payment method',
                    entries: r.paymentMethod
                        .asMap()
                        .entries
                        .map((e) => (_methodLabel(e.value.$1), e.value.$2, _methodColor(e.key)))
                        .toList(),
                  ),
                ),
        ),

        // Dues aging
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) => r.duesAging.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DuesAgingCard(entries: r.duesAging),
                ),
        ),

        // Invoice counts (existing ops data, not in the mockup — kept)
        async.when(
          loading: () => _kpiShimmerRow3(),
          error: (e, _) => _ErrorText('$e'),
          data: (r) => Row(
            children: [
              Expanded(child: _MetricCard(label: 'Invoices', value: '${r.totalInvoices}', sub: '${r.paidCount} paid')),
              const SizedBox(width: 8),
              Expanded(child: _MetricCard(label: 'Paid', value: '${r.paidCount}', sub: 'of ${r.totalInvoices}')),
              const SizedBox(width: 8),
              Expanded(child: _MetricCard(
                label: 'Failed',
                value: '${r.failedCount}',
                sub: r.totalInvoices > 0 ? '${((r.failedCount / r.totalInvoices) * 100).toStringAsFixed(1)}%' : '0%',
              )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Members tab ──────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  const _MembersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_memReportProvider);

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
                  const Text('Active members',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('6 months',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onDark)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              async.when(
                loading: () => const SizedBox(height: 40),
                error: (e, _) => Text('Error: $e', style: const TextStyle(color: AppTheme.statusDanger, fontSize: 12)),
                data: (r) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${r.active}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppTheme.onDark, letterSpacing: -0.5)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Text('↑', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mintOnDark)),
                          Text('${r.newLast30d} new',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mintOnDark)),
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
                  loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.mintOnDark)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (r) {
                    final last6 = r.growthData.length > 6
                        ? r.growthData.sublist(r.growthData.length - 6)
                        : r.growthData;
                    final chartData = last6.map((e) => (e.$1, e.$2.toDouble())).toList();
                    return chartData.isEmpty
                        ? const Center(child: Text('No member data yet',
                            style: TextStyle(fontSize: 11, color: AppTheme.onDarkSoft)))
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
          error: (e, _) => _ErrorText('$e'),
          data: (r) => Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Avg tenure',
                  value: r.avgTenureDays == null ? '—' : '${(r.avgTenureDays! / 30.44).toStringAsFixed(1)}mo',
                  sub: 'per member',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'New members',
                  value: '${r.newLast30d}',
                  sub: 'last 30 days',
                  valueColor: AppTheme.statusActive,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Plan mix donut
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) => r.planMix.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _DonutCard(
                    title: 'Plan mix',
                    entries: r.planMix
                        .asMap()
                        .entries
                        .map((e) => (_planLabel(e.value.$1), e.value.$2.toDouble(), _methodColor(e.key)))
                        .toList(),
                  ),
                ),
        ),

        // Lead conversion
        async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (r) => r.leadsTotal == 0
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _LeadConversionCard(report: r),
                ),
        ),

        // Member status breakdown (existing feature, not in the mockup — kept)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Status breakdown',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              const SizedBox(height: 16),
              async.when(
                loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator())),
                error: (e, _) => _ErrorText('$e'),
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
                radius: 3, color: AppTheme.darkCard, strokeWidth: 2, strokeColor: AppTheme.mintOnDark,
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
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                if (idx % step != 0 && idx != data.length - 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(data[idx].$1,
                    style: const TextStyle(fontSize: 9, color: AppTheme.onDarkSoft, fontWeight: FontWeight.w500)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.darkCard2,
            tooltipRoundedRadius: 6,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      s.y == s.y.roundToDouble() ? s.y.toInt().toString() : formatCurrency(s.y),
                      const TextStyle(color: AppTheme.onDark, fontWeight: FontWeight.w700, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Hero period chip (on dark card) ────────────────────────────────────────

class _HeroPeriodChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _HeroPeriodChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: active ? 0.2 : 0.1)),
        ),
        child: Text(label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? AppTheme.onDark : AppTheme.onDarkSoft,
          )),
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
  const _MetricCard({required this.label, required this.value, required this.sub, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.inkSoft, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: valueColor ?? AppTheme.ink, height: 1.1)),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.inkHint), maxLines: 2),
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
        .map((e) => PieChartSectionData(
              value: e.$2, color: e.$3, radius: 26, title: '', showTitle: false,
            ))
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
            child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 24, sectionsSpace: 2)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                const SizedBox(height: 10),
                ...entries.map((e) {
                  final pct = total > 0 ? (e.$2 / total * 100).toStringAsFixed(0) : '0';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: e.$3, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.$1, style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft))),
                        Text('$pct%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
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

  static const _labels = {'0-7': '0–7 days', '8-15': '8–15 days', '15+': '15+ days'};
  static const _colors = {'0-7': AppTheme.statusWarn, '8-15': AppTheme.statusDanger, '15+': Color(0xFF8B2E1F)};

  @override
  Widget build(BuildContext context) {
    final maxAmount = entries.fold<double>(0, (a, e) => e.$2 > a ? e.$2 : a);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dues aging', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 14),
          for (final e in entries) ...[
            Row(
              children: [
                Expanded(child: Text(_labels[e.$1] ?? e.$1, style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft))),
                Text(formatCurrency(e.$2), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
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
              const Text('Lead conversion', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              const Spacer(),
              Text('${(report.leadConversionRate * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.statusActive)),
            ],
          ),
          const SizedBox(height: 14),
          for (final r in rows) ...[
            Row(
              children: [
                SizedBox(width: 46, child: Text(r.$1, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft))),
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
                SizedBox(width: 24, child: Text('${r.$2}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink))),
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
        .map((e) => PieChartSectionData(
              value: e.$2.toDouble(),
              color: _colors[e.$1] ?? AppTheme.inkSoft,
              radius: 48,
              title: '',
              showTitle: false,
            ))
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
              .map((e) => Padding(
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
                              fontSize: 13, color: AppTheme.inkSoft),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${e.$2}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.ink),
                        ),
                      ],
                    ),
                  ))
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
      child: Text(message,
          style:
              const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;
  const _ErrorText(this.message);

  @override
  Widget build(BuildContext context) {
    return Text('Error: $message',
        style: const TextStyle(color: AppTheme.statusDanger, fontSize: 13));
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
