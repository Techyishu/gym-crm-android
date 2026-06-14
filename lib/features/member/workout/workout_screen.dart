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

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(_workoutPlansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workout Plans')),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _EmptyWorkout(),
        data: (list) => list.isEmpty
            ? const _EmptyWorkout()
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(_workoutPlansProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _WorkoutPlanCard(plan: list[i]),
                ),
              ),
      ),
    );
  }
}

class _WorkoutPlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  const _WorkoutPlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final title = plan['title'] as String? ?? 'Workout Plan';
    final description = plan['description'] as String?;
    final exercises = plan['exercises'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.fitness_center, color: AppTheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('Created ${formatDateFromString(plan['created_at'] as String?)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(description, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              ...exercises.map((ex) => _ExerciseRow(exercise: ex as Map<String, dynamic>)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final Map<String, dynamic> exercise;
  const _ExerciseRow({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final name = exercise['name'] as String? ?? '';
    final sets = exercise['sets'] as int?;
    final reps = exercise['reps'] as int?;
    final weight = exercise['weight_kg'] as num?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
          if (sets != null || reps != null)
            Text(
              [if (sets != null) '${sets}x', if (reps != null) '$reps reps', if (weight != null) '${weight}kg'].join(' '),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
          Icon(Icons.fitness_center, size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 16),
          Text('No workout plans yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          SizedBox(height: 8),
          Text('Your trainer will assign workout plans here', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
