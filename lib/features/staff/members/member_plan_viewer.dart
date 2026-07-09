import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../diet/diet_plan_sheet.dart';
import '../workout/workout_plan_sheet.dart';

/// Staff-facing plan viewers, matching the redesign spec:
/// dark header (back · member name · edit), day chips / macro bars,
/// numbered rows, bottom orange "Edit plan" button.

// ── Workout plan viewer ───────────────────────────────────────────────────────

class WorkoutPlanViewerPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String memberId;
  final String memberName;
  final bool canManage;
  const WorkoutPlanViewerPage({
    super.key,
    required this.plan,
    required this.memberId,
    required this.memberName,
    required this.canManage,
  });

  @override
  State<WorkoutPlanViewerPage> createState() => _WorkoutPlanViewerPageState();
}

class _WorkoutPlanViewerPageState extends State<WorkoutPlanViewerPage> {
  int _dayIndex = 0;
  late Map<String, dynamic> _plan = widget.plan;
  bool _changed = false;

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WorkoutPlanSheet(
        memberId: widget.memberId,
        memberName: widget.memberName,
        plan: _plan,
      ),
    );
    if (saved == true && mounted) {
      _changed = true;
      Navigator.pop(context, true); // parent reloads the fresh plan
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final name = _plan['name'] as String? ?? 'Workout Plan';
    final type = (_plan['type'] as String? ?? 'weekly').toLowerCase();
    final rawDays = _plan['days'];
    final days = rawDays is List
        ? rawDays.cast<Map<String, dynamic>>().where((d) {
            final ex = d['exercises'];
            return ex is List && ex.isNotEmpty;
          }).toList()
        : <Map<String, dynamic>>[];
    final dayIdx = days.isEmpty ? 0 : _dayIndex.clamp(0, days.length - 1);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            // Dark header
            Container(
              width: double.infinity,
              color: AppTheme.darkCard,
              padding: EdgeInsets.fromLTRB(8, topPad + 2, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.onDark),
                      onPressed: () => Navigator.pop(context, _changed),
                    ),
                    Expanded(
                      child: Text(widget.memberName,
                        textAlign: TextAlign.center,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
                    ),
                    if (widget.canManage)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19, color: AppTheme.onDark),
                        onPressed: _edit,
                      )
                    else
                      const SizedBox(width: 48),
                  ]),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onDark, letterSpacing: -0.4)),
                      const SizedBox(height: 3),
                      Text(
                        '${type[0].toUpperCase()}${type.substring(1)} plan · ${days.length} day${days.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.onDarkSoft)),
                    ]),
                  ),
                ],
              ),
            ),
            // Day chips + exercises
            Expanded(
              child: days.isEmpty
                  ? const Center(child: Text('No exercises in this plan yet',
                      style: TextStyle(color: AppTheme.inkHint)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: days.asMap().entries.map((e) {
                              final selected = e.key == dayIdx;
                              final label = (e.value['label'] as String? ?? 'Day ${e.key + 1}').trim();
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() => _dayIndex = e.key),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selected ? AppTheme.accent : AppTheme.surface,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Text(
                                      label.length > 14 ? label.substring(0, 14) : label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: selected ? Colors.white : AppTheme.inkSoft,
                                      )),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(days[dayIdx]['label'] as String? ?? '',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                        const SizedBox(height: 8),
                        _ExerciseList(
                          exercises: ((days[dayIdx]['exercises'] as List?) ?? [])
                              .cast<Map<String, dynamic>>(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: widget.canManage
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: ElevatedButton(onPressed: _edit, child: const Text('Edit plan')),
                ),
              )
            : null,
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;
  const _ExerciseList({required this.exercises});

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: AppTheme.cardDecoration(),
        child: const Center(child: Text('No exercises for this day',
          style: TextStyle(fontSize: 13, color: AppTheme.inkHint))),
      );
    }
    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.inkSoft)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ex['name'] as String? ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  if (weight.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(weight, style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              if (setsReps.isNotEmpty)
                Text(setsReps, style: AppTheme.numberStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ── Diet plan viewer ──────────────────────────────────────────────────────────

class DietPlanViewerPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String memberId;
  final String memberName;
  final bool canManage;
  const DietPlanViewerPage({
    super.key,
    required this.plan,
    required this.memberId,
    required this.memberName,
    required this.canManage,
  });

  @override
  State<DietPlanViewerPage> createState() => _DietPlanViewerPageState();
}

class _DietPlanViewerPageState extends State<DietPlanViewerPage> {
  late Map<String, dynamic> _plan = widget.plan;
  bool _changed = false;

  Future<void> _edit() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DietPlanSheet(
        memberId: widget.memberId,
        memberName: widget.memberName,
        plan: _plan,
      ),
    );
    if (saved == true && mounted) {
      _changed = true;
      Navigator.pop(context, true);
    }
  }

  static int _mealCalories(Map<String, dynamic> meal) {
    final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.fold<int>(0, (s, it) => s + ((it['calories'] as num?)?.toInt() ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final name = _plan['name'] as String? ?? 'Diet Plan';
    final rawMeals = _plan['meals'];
    final meals = rawMeals is List
        ? rawMeals.cast<Map<String, dynamic>>().where((m) {
            final items = m['items'];
            return items is List && items.isNotEmpty;
          }).toList()
        : <Map<String, dynamic>>[];
    final calories = (_plan['calories'] as int?) ??
        meals.fold<int>(0, (s, m) => s + _mealCalories(m));

    int p = 0, c = 0, f = 0;
    for (final meal in meals) {
      for (final it in (meal['items'] as List? ?? []).cast<Map<String, dynamic>>()) {
        p += (it['protein'] as num?)?.toInt() ?? 0;
        c += (it['carbs'] as num?)?.toInt() ?? 0;
        f += (it['fat'] as num?)?.toInt() ?? 0;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppTheme.darkCard,
              padding: EdgeInsets.fromLTRB(8, topPad + 2, 8, 16),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.onDark),
                    onPressed: () => Navigator.pop(context, _changed),
                  ),
                  Expanded(
                    child: Text(widget.memberName,
                      textAlign: TextAlign.center,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
                  ),
                  if (widget.canManage)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 19, color: AppTheme.onDark),
                      onPressed: _edit,
                    )
                  else
                    const SizedBox(width: 48),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.onDark, letterSpacing: -0.4)),
                          const SizedBox(height: 2),
                          const Text('Daily target',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.onDarkSoft)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$calories',
                          style: AppTheme.numberStyle(fontSize: 26, color: AppTheme.mintOnDark, height: 1)),
                        const Text('kcal', style: TextStyle(fontSize: 12, color: AppTheme.onDarkSoft)),
                      ]),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                children: [
                  if (p > 0 || c > 0 || f > 0) ...[
                    _MacroBars(protein: p, carbs: c, fat: f),
                    const SizedBox(height: 12),
                  ],
                  if (meals.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      decoration: AppTheme.cardDecoration(),
                      child: const Center(child: Text('No meals added yet',
                        style: TextStyle(fontSize: 13, color: AppTheme.inkHint))),
                    )
                  else
                    Container(
                      decoration: AppTheme.cardDecoration(),
                      child: Column(
                        children: meals.asMap().entries.map((e) {
                          final meal = e.value;
                          final mealName = meal['name'] as String? ?? 'Meal';
                          final time = (meal['time'] as String? ?? '').trim();
                          final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();
                          final foods = items
                              .map((it) => (it['food'] as String? ?? '').trim())
                              .where((s) => s.isNotEmpty)
                              .join(', ');
                          final kcal = _mealCalories(meal);
                          return Container(
                            decoration: BoxDecoration(
                              border: e.key == meals.length - 1
                                  ? null
                                  : const Border(bottom: BorderSide(color: AppTheme.border, width: 0.7)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            child: Row(children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.statusActiveBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  time.isNotEmpty
                                      ? _timeBadge(time)
                                      : mealName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.statusActive)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(mealName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                                  if (foods.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(foods,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                                  ],
                                ]),
                              ),
                              const SizedBox(width: 8),
                              if (kcal > 0)
                                Text('$kcal', style: AppTheme.numberStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: widget.canManage
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: ElevatedButton(onPressed: _edit, child: const Text('Edit plan')),
                ),
              )
            : null,
      ),
    );
  }

  static String _timeBadge(String time) {
    final m = RegExp(r'(\d{1,2})[:.]?\d*\s*([AaPp])?').firstMatch(time.trim());
    if (m == null) return '·';
    return '${m.group(1) ?? ''}${(m.group(2) ?? '').toUpperCase()}';
  }
}

class _MacroBars extends StatelessWidget {
  final int protein, carbs, fat;
  const _MacroBars({required this.protein, required this.carbs, required this.fat});

  @override
  Widget build(BuildContext context) {
    final maxVal = [protein, carbs, fat].reduce((a, b) => a > b ? a : b);

    Widget bar(String label, int grams, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Row(children: [
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const Spacer(),
            Text('${grams}g', style: AppTheme.numberStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: maxVal > 0 ? grams / maxVal : 0,
              minHeight: 6,
              backgroundColor: AppTheme.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: AppTheme.cardDecoration(),
      child: Column(children: [
        bar('Protein', protein, AppTheme.statusActive),
        bar('Carbs', carbs, AppTheme.statusWarn),
        bar('Fat', fat, AppTheme.accent),
      ]),
    );
  }
}
