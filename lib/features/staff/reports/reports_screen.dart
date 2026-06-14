import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

final _reportsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final lastMonth = DateTime(now.year, now.month - 1, 1);
  final endOfLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);

  final membersRes = await client
      .from('members')
      .select('id')
      .eq('gym_id', gymId)
      .eq('status', 'active')
      .count(CountOption.exact);
  final checkInsRes = await client
      .from('check_ins')
      .select('id')
      .eq('gym_id', gymId)
      .gte('checked_in_at', startOfMonth.toIso8601String())
      .count(CountOption.exact);
  final thisMonthInvoices = await client
      .from('invoices')
      .select('amount')
      .eq('gym_id', gymId)
      .eq('status', 'paid')
      .gte('paid_at', startOfMonth.toIso8601String());
  final lastMonthInvoices = await client
      .from('invoices')
      .select('amount')
      .eq('gym_id', gymId)
      .eq('status', 'paid')
      .gte('paid_at', lastMonth.toIso8601String())
      .lte('paid_at', endOfLastMonth.toIso8601String());

  final thisMonthRevenue =
      (thisMonthInvoices as List).fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());
  final lastMonthRevenue =
      (lastMonthInvoices as List).fold<double>(0, (sum, r) => sum + (r['amount'] as num).toDouble());

  return {
    'active_members': membersRes.count,
    'this_month_revenue': thisMonthRevenue,
    'last_month_revenue': lastMonthRevenue,
    'this_month_checkins': checkInsRes.count,
  };
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(_reportsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Reports'),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_reportsProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: report.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month label
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.inkHint),
                    const SizedBox(width: 6),
                    Text(
                      formatMonth(DateTime.now()),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // KPI grid
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    _StatCard(
                      label: 'Active Members',
                      value: '${data['active_members']}',
                      icon: Icons.people_outline,
                      iconColor: AppTheme.ink,
                    ),
                    _StatCard(
                      label: 'This Month',
                      value: _formatRevenue(data['this_month_revenue'] as double),
                      icon: Icons.trending_up,
                      iconColor: AppTheme.statusActive,
                      subtitle: (data['last_month_revenue'] as double) > 0
                          ? _revenueGrowth(
                              data['this_month_revenue'] as double,
                              data['last_month_revenue'] as double,
                            )
                          : null,
                    ),
                    _StatCard(
                      label: 'Last Month',
                      value: _formatRevenue(data['last_month_revenue'] as double),
                      icon: Icons.history,
                      iconColor: AppTheme.statusWarn,
                    ),
                    _StatCard(
                      label: 'Check-ins',
                      value: '${data['this_month_checkins']}',
                      icon: Icons.check_circle_outline,
                      iconColor: AppTheme.statusNeutral,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Revenue chart section
                _buildSectionHeader('Revenue Comparison'),
                const SizedBox(height: 12),
                _buildRevenueChart(data),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatRevenue(double amount) {
    if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
    }
    return formatCurrency(amount);
  }

  String _revenueGrowth(double current, double last) {
    if (last == 0) return '+100%';
    final pct = ((current - last) / last * 100).toStringAsFixed(0);
    return current >= last ? '+$pct% vs last month' : '$pct% vs last month';
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppTheme.border, height: 1),
      ],
    );
  }

  Widget _buildRevenueChart(Map<String, dynamic> data) {
    final thisMonth = data['this_month_revenue'] as double;
    final lastMonth = data['last_month_revenue'] as double;
    final max = [thisMonth, lastMonth, 1.0].reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: max * 1.25,
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: lastMonth,
                      color: const Color(0xFFE0E0E0),
                      width: 40,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: thisMonth,
                      color: const Color(0xFF1A1A1A),
                      width: 40,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        v == 0 ? 'Last Month' : 'This Month',
                        style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.ink,
                  tooltipRoundedRadius: 6,
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    formatCurrency(rod.toY),
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? subtitle;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: AppTheme.ink),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppTheme.inkHint, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 10,
                    color: iconColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
