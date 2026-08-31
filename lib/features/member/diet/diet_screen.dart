import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';

final _dietPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser!;

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member == null) return [];

  return await client
      .from('diet_plans')
      .select()
      .eq('member_id', member['id'] as String)
      .eq('is_active', true)
      .order('created_at', ascending: false);
});

class DietScreen extends ConsumerStatefulWidget {
  const DietScreen({super.key});

  @override
  ConsumerState<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends ConsumerState<DietScreen> {
  int _planIndex = 0;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(_dietPlansProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const SafeArea(child: _EmptyDiet()),
        data: (list) {
          if (list.isEmpty) return const SafeArea(child: _EmptyDiet());
          final idx = _planIndex.clamp(0, list.length - 1);
          final plan = list[idx];
          final rawMeals = plan['meals'];
          final meals = rawMeals is List
              ? rawMeals.cast<Map<String, dynamic>>().where((m) {
                  final items = m['items'];
                  return items is List && items.isNotEmpty;
                }).toList()
              : <Map<String, dynamic>>[];

          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async => ref.invalidate(_dietPlansProvider),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DietHeader(
                  plan: plan,
                  meals: meals,
                  planCount: list.length,
                  planIndex: idx,
                  onSwitchPlan: () =>
                      setState(() => _planIndex = (idx + 1) % list.length),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _MacroCard(meals: meals),
                      const SizedBox(height: 12),
                      if (meals.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No meals added yet',
                            style: TextStyle(color: AppTheme.inkHint),
                          ),
                        )
                      else
                        Container(
                          decoration: AppTheme.cardDecoration(),
                          child: Column(
                            children: meals
                                .asMap()
                                .entries
                                .map(
                                  (e) => _MealRow(
                                    meal: e.value,
                                    isLast: e.key == meals.length - 1,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Macro helpers ─────────────────────────────────────────────────────────────

int _mealCalories(Map<String, dynamic> meal) {
  final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();
  return items.fold<int>(
    0,
    (s, it) => s + ((it['calories'] as num?)?.toInt() ?? 0),
  );
}

(int, int, int) _macroTotals(List<Map<String, dynamic>> meals) {
  int p = 0, c = 0, f = 0;
  for (final meal in meals) {
    final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final it in items) {
      p += (it['protein'] as num?)?.toInt() ?? 0;
      c += (it['carbs'] as num?)?.toInt() ?? 0;
      f += (it['fat'] as num?)?.toInt() ?? 0;
    }
  }
  return (p, c, f);
}

// ── Dark header ───────────────────────────────────────────────────────────────

class _DietHeader extends StatelessWidget {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> meals;
  final int planCount;
  final int planIndex;
  final VoidCallback onSwitchPlan;
  const _DietHeader({
    required this.plan,
    required this.meals,
    required this.planCount,
    required this.planIndex,
    required this.onSwitchPlan,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final name = plan['name'] as String? ?? 'Diet Plan';
    final calories =
        (plan['calories'] as int?) ??
        meals.fold<int>(0, (s, m) => s + _mealCalories(m));

    return Container(
      width: double.infinity,
      color: AppTheme.darkCard,
      padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'My diet',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onDarkSoft,
                ),
              ),
              const Spacer(),
              if (planCount > 1)
                GestureDetector(
                  onTap: onSwitchPlan,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Plan ${planIndex + 1} / $planCount ›',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.onDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Daily target',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.onDarkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$calories',
                    style: AppTheme.numberStyle(
                      fontSize: 26,
                      color: AppTheme.mintOnDark,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'kcal',
                    style: TextStyle(fontSize: 12, color: AppTheme.onDarkSoft),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Macro bars card ───────────────────────────────────────────────────────────

class _MacroCard extends StatelessWidget {
  final List<Map<String, dynamic>> meals;
  const _MacroCard({required this.meals});

  @override
  Widget build(BuildContext context) {
    final (protein, carbs, fat) = _macroTotals(meals);
    if (protein == 0 && carbs == 0 && fat == 0) return const SizedBox.shrink();
    final maxVal = [protein, carbs, fat].reduce((a, b) => a > b ? a : b);

    Widget bar(String label, int grams, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '${grams}g',
                  style: AppTheme.numberStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: maxVal > 0 ? grams / maxVal : 0,
                minHeight: 6,
                backgroundColor: AppTheme.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          bar('Protein', protein, AppTheme.statusActive),
          bar('Carbs', carbs, AppTheme.statusWarn),
          bar('Fat', fat, AppTheme.accent),
        ],
      ),
    );
  }
}

// ── Meal row ──────────────────────────────────────────────────────────────────

class _MealRow extends StatefulWidget {
  final Map<String, dynamic> meal;
  final bool isLast;
  const _MealRow({required this.meal, required this.isLast});

  @override
  State<_MealRow> createState() => _MealRowState();
}

class _MealRowState extends State<_MealRow> {
  bool _expanded = false;

  static String _timeBadge(String time) {
    // "7:00 AM" → "7A", "1 PM" → "1P"
    final m = RegExp(r'(\d{1,2})[:.]?\d*\s*([AaPp])?').firstMatch(time.trim());
    if (m == null) return '·';
    final h = m.group(1) ?? '';
    final ap = (m.group(2) ?? '').toUpperCase();
    return '$h$ap';
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final name = meal['name'] as String? ?? 'Meal';
    final time = meal['time'] as String? ?? '';
    final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final foods = items
        .map((it) => (it['food'] as String? ?? '').trim())
        .where((f) => f.isNotEmpty)
        .join(', ');
    final kcal = _mealCalories(meal);
    final (badgeBg, badgeFg) = avatarTintForLocal(name);

    return Container(
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.7),
              ),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      time.isNotEmpty
                          ? _timeBadge(time)
                          : name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppTheme.ink,
                          ),
                        ),
                        if (foods.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            foods,
                            maxLines: _expanded ? 10 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (kcal > 0)
                    Text(
                      '$kcal',
                      style: AppTheme.numberStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              if (_expanded && items.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...items.map((it) {
                  final qty = (it['qty'] as String? ?? '').trim();
                  final c = (it['calories'] as num?)?.toInt();
                  return Padding(
                    padding: const EdgeInsets.only(left: 52, bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              it['food'] as String? ?? '—',
                              if (qty.isNotEmpty) qty,
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        if (c != null)
                          Text(
                            '$c kcal',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.inkHint,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Local tint cycle for meal time badges (mirrors redesign avatar tints).
(Color, Color) avatarTintForLocal(String seed) {
  const tints = [
    (Color(0xFFDDEFE2), Color(0xFF2E7D4F)),
    (Color(0xFFF4E8CD), Color(0xFFB07C1F)),
    (Color(0xFFF8DFD7), Color(0xFFC2492F)),
    (Color(0xFFE9E6DD), Color(0xFF6E6A60)),
  ];
  return tints[seed.isEmpty ? 0 : seed.codeUnitAt(0) % tints.length];
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyDiet extends StatelessWidget {
  const _EmptyDiet();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.restaurant, size: 56, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No diet plans yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your trainer will assign a plan soon',
            style: TextStyle(color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }
}
