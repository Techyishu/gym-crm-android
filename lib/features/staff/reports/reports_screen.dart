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
  final int totalInvoices;
  final int paidCount;
  final int failedCount;
  final List<(String label, double value)> chartData;

  const _RevReport({
    required this.totalRevenue,
    required this.totalInvoices,
    required this.paidCount,
    required this.failedCount,
    required this.chartData,
  });
}

class _MemReport {
  final int total;
  final int active;
  final int frozen;
  final int expired;
  final int cancelled;
  final List<(String label, int count)> growthData;

  const _MemReport({
    required this.total,
    required this.active,
    required this.frozen,
    required this.expired,
    required this.cancelled,
    required this.growthData,
  });
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

  return _RevReport(
    totalRevenue: (raw['total_revenue'] as num).toDouble(),
    totalInvoices: (raw['total_invoices'] as num).toInt(),
    paidCount: (raw['paid_count'] as num).toInt(),
    failedCount: (raw['failed_count'] as num).toInt(),
    chartData: chartData,
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

  return _MemReport(
    total: (raw['total'] as num).toInt(),
    active: (raw['active'] as num).toInt(),
    frozen: (raw['frozen'] as num).toInt(),
    expired: (raw['expired'] as num).toInt(),
    cancelled: (raw['cancelled'] as num).toInt(),
    growthData: growthData,
  );
});

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _compactRev(double amount) {
  if (amount >= 100000) {
    return '₹${(amount / 100000).toStringAsFixed(1)}L';
  }
  if (amount >= 1000) {
    return '₹${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
  }
  return formatCurrency(amount);
}

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
      appBar: AppBar(
        title: const Text('Reports'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_revReportProvider);
          ref.invalidate(_memReportProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 32),
            ],
          ),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
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
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppTheme.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppTheme.inkSoft,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period selector
        Row(
          children: [
            const Text(
              'REVENUE OVERVIEW',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                  letterSpacing: 0.5),
            ),
            const Spacer(),
            ..._periods.map((p) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _PeriodChip(
                    label: p.$2,
                    active: period == p.$1,
                    onTap: () => onPeriodChanged(p.$1),
                  ),
                )),
          ],
        ),
        const SizedBox(height: 12),

        // KPI cards
        async.when(
          loading: () => _kpiShimmer(),
          error: (e, _) => _ErrorText('$e'),
          data: (r) {
            final failRate = r.totalInvoices > 0
                ? ((r.failedCount / r.totalInvoices) * 100).toStringAsFixed(1)
                : '0.0';
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        label: 'Total Revenue',
                        value: _compactRev(r.totalRevenue),
                        sub: '${r.paidCount} paid invoices',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiCard(
                        label: 'Invoices',
                        value: '${r.totalInvoices}',
                        sub: '${r.paidCount} paid',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        label: 'Failed',
                        value: '${r.failedCount}',
                        sub: '$failRate% failure rate',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KpiCard(
                        label: 'Paid',
                        value: '${r.paidCount}',
                        sub: 'of ${r.totalInvoices} invoices',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Revenue over time chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'REVENUE OVER TIME',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorText('$e'),
                  data: (r) => r.chartData.isEmpty
                      ? const _EmptyChart('No revenue data for this period')
                      : _RevenueLineChart(data: r.chartData),
                ),
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
  const _MembersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_memReportProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MEMBER OVERVIEW',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),

        // KPI cards
        async.when(
          loading: () => _kpiShimmer(),
          error: (e, _) => _ErrorText('$e'),
          data: (r) => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                        label: 'Total', value: '${r.total}', sub: 'all members'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiCard(
                        label: 'Active',
                        value: '${r.active}',
                        sub: 'paying members'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                        label: 'Expired',
                        value: '${r.expired}',
                        sub: 'need renewal'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _KpiCard(
                        label: 'Frozen',
                        value: '${r.frozen}',
                        sub: 'paused plans'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // New members bar chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NEW MEMBERS — LAST 12 MONTHS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorText('$e'),
                  data: (r) => r.growthData.isEmpty
                      ? const _EmptyChart('No member data yet')
                      : _GrowthBarChart(data: r.growthData),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Status breakdown donut
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'STATUS BREAKDOWN',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),
              async.when(
                loading: () => const SizedBox(
                    height: 200,
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

// ─── Revenue line chart ───────────────────────────────────────────────────────

class _RevenueLineChart extends StatelessWidget {
  final List<(String label, double value)> data;
  const _RevenueLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.$2))
        .toList();

    final maxY =
        data.map((e) => e.$2).fold<double>(0, (a, b) => a > b ? a : b);
    final step = (data.length / 5).ceil().clamp(1, 999);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.3,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.ink,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.ink.withValues(alpha: 0.25),
                  AppTheme.ink.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                if (idx % step != 0 && idx != data.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data[idx].$1,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w500),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, _) => Text(
                _compactRev(value),
                style: const TextStyle(fontSize: 9, color: AppTheme.inkSoft),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppTheme.ink,
            tooltipRoundedRadius: 6,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      formatCurrency(s.y),
                      const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Growth bar chart ─────────────────────────────────────────────────────────

class _GrowthBarChart extends StatelessWidget {
  final List<(String label, int count)> data;
  const _GrowthBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxY =
        data.map((e) => e.$2.toDouble()).fold<double>(0, (a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxY * 1.3,
        barGroups: data
            .asMap()
            .entries
            .map((e) => BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.$2.toDouble(),
                      color: AppTheme.ink,
                      width: (280 / data.length).clamp(8, 28),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ],
                ))
            .toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                final step = (data.length / 6).ceil().clamp(1, 999);
                if (idx % step != 0 && idx != data.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data[idx].$1,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w500),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, _) {
                if (value % 1 != 0) return const SizedBox.shrink();
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 9, color: AppTheme.inkSoft),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppTheme.ink,
            tooltipRoundedRadius: 6,
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${rod.toY.toInt()} members',
              const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status donut chart ───────────────────────────────────────────────────────

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

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _KpiCard({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                  height: 1.1)),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!,
                style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
          ],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PeriodChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: active ? AppTheme.ink : AppTheme.border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

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

Widget _kpiShimmer() {
  return Column(
    children: [
      Row(
        children: [
          Expanded(child: _ShimmerBox(height: 80)),
          const SizedBox(width: 10),
          Expanded(child: _ShimmerBox(height: 80)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _ShimmerBox(height: 80)),
          const SizedBox(width: 10),
          Expanded(child: _ShimmerBox(height: 80)),
        ],
      ),
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
