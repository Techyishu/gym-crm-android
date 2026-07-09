import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

final _workoutPlansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser!;

  final member = await client.from('members').select('id').eq('user_id', user.id).maybeSingle();
  if (member == null) return [];

  return await client
      .from('workout_plans')
      .select()
      .eq('member_id', member['id'])
      .order('created_at', ascending: false);
});

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  int _planIndex = 0;
  int _dayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(_workoutPlansProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const SafeArea(child: _EmptyWorkout()),
        data: (list) {
          if (list.isEmpty) return const SafeArea(child: _EmptyWorkout());
          final planIdx = _planIndex.clamp(0, list.length - 1);
          final plan = list[planIdx];
          final rawDays = plan['days'];
          final days = rawDays is List
              ? rawDays.cast<Map<String, dynamic>>().where((d) {
                  final ex = d['exercises'];
                  return ex is List && ex.isNotEmpty;
                }).toList()
              : <Map<String, dynamic>>[];
          final dayIdx = days.isEmpty ? 0 : _dayIndex.clamp(0, days.length - 1);

          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async => ref.invalidate(_workoutPlansProvider),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DarkHeader(
                  plan: plan,
                  planCount: list.length,
                  planIndex: planIdx,
                  onSwitchPlan: () => setState(() {
                    _planIndex = (planIdx + 1) % list.length;
                    _dayIndex = 0;
                  }),
                ),
                if (days.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No exercises in this plan yet',
                      style: TextStyle(color: AppTheme.inkHint))),
                  )
                else ...[
                  // Day chips
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: days.asMap().entries.map((e) {
                          final selected = e.key == dayIdx;
                          final label = _shortLabel(e.value['label'] as String? ?? 'Day ${e.key + 1}');
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _dayIndex = e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected ? AppTheme.accent : AppTheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: selected ? Colors.white : AppTheme.inkSoft,
                                  )),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  _DayContent(day: days[dayIdx]),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _shortLabel(String label) {
    final l = label.trim();
    return l.length > 12 ? l.substring(0, 12) : l;
  }
}

// ── Dark header ───────────────────────────────────────────────────────────────

class _DarkHeader extends StatelessWidget {
  final Map<String, dynamic> plan;
  final int planCount;
  final int planIndex;
  final VoidCallback onSwitchPlan;
  const _DarkHeader({
    required this.plan,
    required this.planCount,
    required this.planIndex,
    required this.onSwitchPlan,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final name = plan['name'] as String? ?? 'Workout Plan';
    final type = (plan['type'] as String? ?? 'weekly').toLowerCase();
    final created = formatDateFromString(plan['created_at'] as String?);

    return Container(
      width: double.infinity,
      color: AppTheme.darkCard,
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('My workout',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
            const Spacer(),
            if (planCount > 1)
              GestureDetector(
                onTap: onSwitchPlan,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Plan ${planIndex + 1} / $planCount ›',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onDark)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text(name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.onDark, letterSpacing: -0.4)),
          const SizedBox(height: 4),
          Text('${type[0].toUpperCase()}${type.substring(1)} plan · assigned $created',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.onDarkSoft)),
        ],
      ),
    );
  }
}

// ── Day content ───────────────────────────────────────────────────────────────

class _DayContent extends StatelessWidget {
  final Map<String, dynamic> day;
  const _DayContent({required this.day});

  @override
  Widget build(BuildContext context) {
    final label = day['label'] as String? ?? '';
    final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 10),
          Container(
            decoration: AppTheme.cardDecoration(),
            child: Column(
              children: exercises.asMap().entries.map((e) {
                final i = e.key;
                final ex = e.value;
                final sets = (ex['sets'] as String? ?? '').trim();
                final reps = (ex['reps'] as String? ?? '').trim();
                final weight = (ex['weight'] as String? ?? '').trim();
                final setsReps = sets.isNotEmpty && reps.isNotEmpty
                    ? '$sets × $reps'
                    : (sets.isNotEmpty ? '$sets sets' : reps);
                return Container(
                  decoration: BoxDecoration(
                    border: i == exercises.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: AppTheme.border, width: 0.7)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.inkSoft)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ex['name'] as String? ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.ink)),
                        if (weight.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(weight, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                        ],
                      ]),
                    ),
                    const SizedBox(width: 8),
                    if (setsReps.isNotEmpty)
                      Text(setsReps, style: AppTheme.numberStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkout extends StatelessWidget {
  const _EmptyWorkout();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 64, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text('No workout plans yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          SizedBox(height: 8),
          Text('Your trainer will assign workout plans here',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
