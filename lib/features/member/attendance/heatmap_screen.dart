import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

/// Returns IST-localised dates of all check-ins in the last 6 months.
final _attendanceDatesProvider = FutureProvider<List<DateTime>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return [];

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return [];

  final since = DateTime.now().subtract(const Duration(days: 182));
  final data = await client
      .from('check_ins')
      .select('checked_in_at')
      .eq('member_id', member['id'] as String)
      .gte('checked_in_at', since.toIso8601String())
      .order('checked_in_at', ascending: true);

  return (data as List).map((e) {
    // Convert to IST (UTC+5:30) for consistent day boundaries.
    final utc = DateTime.parse(e['checked_in_at'] as String).toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }).toList();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class AttendanceHeatmapScreen extends ConsumerWidget {
  const AttendanceHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_attendanceDatesProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Attendance')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load attendance: $e',
                style: const TextStyle(color: AppTheme.inkHint)),
          ),
        ),
        data: (dates) => _AttendanceBody(dates: dates),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _AttendanceBody extends StatelessWidget {
  final List<DateTime> dates;
  const _AttendanceBody({required this.dates});

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Set<String> get _daySet => dates.map(_dayKey).toSet();

  DateTime get _nowIST =>
      DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  int get _thisMonthCount {
    final now = _nowIST;
    return dates.where((d) => d.year == now.year && d.month == now.month).length;
  }

  int get _streak {
    final set = _daySet;
    DateTime cursor = _nowIST;
    // If today has no visit, start counting from yesterday.
    if (!set.contains(_dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (set.contains(_dayKey(cursor)) && streak < 366) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {}, // parent provider handles re-watch on rebuild
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatsRow(
            thisMonth: _thisMonthCount,
            streak: _streak,
            total: dates.length,
          ),
          const SizedBox(height: 16),
          _HeatmapCard(daySet: _daySet, nowIST: _nowIST),
          const SizedBox(height: 16),
          _RecentListCard(dates: dates),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int thisMonth;
  final int streak;
  final int total;
  const _StatsRow({
    required this.thisMonth,
    required this.streak,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatChip(value: '$thisMonth', label: 'This month')),
        const SizedBox(width: 10),
        Expanded(child: _StatChip(value: '🔥 $streak', label: 'Day streak')),
        const SizedBox(width: 10),
        Expanded(child: _StatChip(value: '$total', label: '6-month total')),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
          ),
        ],
      ),
    );
  }
}

// ── Heatmap card ──────────────────────────────────────────────────────────────

class _HeatmapCard extends StatelessWidget {
  final Set<String> daySet;
  final DateTime nowIST;
  const _HeatmapCard({required this.daySet, required this.nowIST});

  static const _weeks = 26; // ~6 months
  static const _cellSize = 13.0;
  static const _cellGap = 3.0;
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Monday of the week containing [nowIST].
  DateTime get _startMonday {
    final dow = nowIST.weekday; // 1=Mon … 7=Sun
    final thisMonday = nowIST.subtract(Duration(days: dow - 1));
    return DateTime(thisMonday.year, thisMonday.month, thisMonday.day);
  }

  @override
  Widget build(BuildContext context) {
    final startMonday = _startMonday.subtract(Duration(days: (_weeks - 1) * 7));

    // Build month label positions: (column index, label string)
    final monthLabels = <(int, String)>[];
    final monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    int? lastMonth;
    for (int w = 0; w < _weeks; w++) {
      final weekStart = startMonday.add(Duration(days: w * 7));
      if (weekStart.month != lastMonth) {
        monthLabels.add((w, monthNames[weekStart.month]));
        lastMonth = weekStart.month;
      }
    }

    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last 6 months',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day-of-week labels
                Column(
                  children: List.generate(7, (i) => Padding(
                    padding: EdgeInsets.only(
                      bottom: i < 6 ? _cellGap : 0,
                      right: 4,
                    ),
                    child: SizedBox(
                      width: 12,
                      height: _cellSize,
                      child: Text(
                        _dayLabels[i],
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.inkHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )),
                ),
                // Grid columns (one per week)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Month labels row
                    SizedBox(
                      height: 14,
                      child: Stack(
                        children: monthLabels.map((t) {
                          final col = t.$1;
                          return Positioned(
                            left: col * (_cellSize + _cellGap),
                            child: Text(
                              t.$2,
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppTheme.inkHint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Week columns
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(_weeks, (w) {
                        return Padding(
                          padding: EdgeInsets.only(right: w < _weeks - 1 ? _cellGap : 0),
                          child: Column(
                            children: List.generate(7, (d) {
                              final date = startMonday.add(Duration(days: w * 7 + d));
                              final isFuture = date.isAfter(nowIST);
                              final hasVisit = !isFuture && daySet.contains(_key(date));
                              return Padding(
                                padding: EdgeInsets.only(bottom: d < 6 ? _cellGap : 0),
                                child: Container(
                                  width: _cellSize,
                                  height: _cellSize,
                                  decoration: BoxDecoration(
                                    color: isFuture
                                        ? Colors.transparent
                                        : hasVisit
                                            ? AppTheme.accent
                                            : AppTheme.border,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Legend
          Row(
            children: [
              const Text('Less', style: TextStyle(fontSize: 10, color: AppTheme.inkHint)),
              const SizedBox(width: 6),
              ...List.generate(4, (i) => Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: i == 0
                      ? AppTheme.border
                      : AppTheme.accent.withValues(alpha: 0.25 + i * 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const Text('More', style: TextStyle(fontSize: 10, color: AppTheme.inkHint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Recent list ───────────────────────────────────────────────────────────────

class _RecentListCard extends StatelessWidget {
  final List<DateTime> dates;
  const _RecentListCard({required this.dates});

  @override
  Widget build(BuildContext context) {
    final recent = [...dates].reversed.take(20).toList();
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Visits',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No visits in the last 6 months',
                  style: TextStyle(color: AppTheme.inkHint, fontSize: 13)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recent.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (_, i) {
                final dt = recent[i];
                final months = [
                  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                ];
                final dateStr =
                    '${months[dt.month]} ${dt.day}, ${dt.year}';
                final h = dt.hour;
                final m = dt.minute.toString().padLeft(2, '0');
                final period = h >= 12 ? 'PM' : 'AM';
                final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
                final timeStr = '$displayH:$m $period';

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.statusActiveBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.fitness_center_outlined,
                          size: 18,
                          color: AppTheme.statusActive,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Gym Visit',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.ink)),
                            Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.inkHint)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.statusActiveBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.statusActive,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
