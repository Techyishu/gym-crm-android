import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../core/theme/app_icons.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _FoodItem {
  final TextEditingController food;
  final TextEditingController qty;
  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;

  _FoodItem({
    String f = '',
    String q = '',
    String cal = '',
    String p = '',
    String c = '',
    String ft = '',
  }) : food = TextEditingController(text: f),
       qty = TextEditingController(text: q),
       calories = TextEditingController(text: cal),
       protein = TextEditingController(text: p),
       carbs = TextEditingController(text: c),
       fat = TextEditingController(text: ft);

  factory _FoodItem.fromJson(Map<String, dynamic> j) => _FoodItem(
    f: j['food'] as String? ?? '',
    q: j['qty'] as String? ?? '',
    cal: '${j['calories'] ?? ''}',
    p: '${j['protein'] ?? ''}',
    c: '${j['carbs'] ?? ''}',
    ft: '${j['fat'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'food': food.text.trim(),
    'qty': qty.text.trim(),
    if (calories.text.trim().isNotEmpty)
      'calories': int.tryParse(calories.text.trim()),
    if (protein.text.trim().isNotEmpty)
      'protein': int.tryParse(protein.text.trim()),
    if (carbs.text.trim().isNotEmpty) 'carbs': int.tryParse(carbs.text.trim()),
    if (fat.text.trim().isNotEmpty) 'fat': int.tryParse(fat.text.trim()),
  };

  void dispose() {
    food.dispose();
    qty.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
  }
}

class _MealData {
  final TextEditingController name;
  final TextEditingController time;
  final List<_FoodItem> items;

  _MealData({
    required String nameText,
    String timeText = '',
    List<_FoodItem>? items,
  }) : name = TextEditingController(text: nameText),
       time = TextEditingController(text: timeText),
       items = items ?? [];

  factory _MealData.fromJson(Map<String, dynamic> j) => _MealData(
    nameText: j['name'] as String? ?? '',
    timeText: j['time'] as String? ?? '',
    items: ((j['items'] as List?)?.cast<Map<String, dynamic>>() ?? [])
        .map(_FoodItem.fromJson)
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'time': time.text.trim(),
    'items': items
        .where((i) => i.food.text.trim().isNotEmpty)
        .map((i) => i.toJson())
        .toList(),
  };

  void dispose() {
    name.dispose();
    time.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class DietPlanSheet extends StatefulWidget {
  final String memberId;
  final String memberName;
  final Map<String, dynamic>? plan;

  const DietPlanSheet({
    super.key,
    required this.memberId,
    required this.memberName,
    this.plan,
  });

  @override
  State<DietPlanSheet> createState() => _DietPlanSheetState();
}

class _DietPlanSheetState extends State<DietPlanSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _caloriesCtrl;
  late String _goal;
  late List<_MealData> _meals;
  bool _saving = false;

  static const _goals = [
    'general',
    'weight_loss',
    'muscle_gain',
    'maintenance',
  ];
  static const _goalLabels = {
    'general': 'General',
    'weight_loss': 'Weight Loss',
    'muscle_gain': 'Muscle Gain',
    'maintenance': 'Maintenance',
  };

  static const _defaultMealNames = ['Breakfast', 'Lunch', 'Dinner'];

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _caloriesCtrl = TextEditingController(
      text: p?['calories'] != null ? '${p!['calories']}' : '',
    );
    _goal = p?['goal'] as String? ?? 'general';
    final rawMeals = p?['meals'] as List?;
    if (rawMeals != null && rawMeals.isNotEmpty) {
      _meals = rawMeals
          .cast<Map<String, dynamic>>()
          .map(_MealData.fromJson)
          .toList();
    } else {
      _meals = _defaultMealNames.map((n) => _MealData(nameText: n)).toList();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _caloriesCtrl.dispose();
    for (final m in _meals) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a plan name')));
      return;
    }
    final mealsJson = _meals.map((m) => m.toJson()).toList();
    final caloriesRaw = _caloriesCtrl.text.trim();
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final planId = widget.plan?['id'] as String?;
      if (planId != null) {
        await client
            .from('diet_plans')
            .update({
              'name': name,
              'goal': _goal,
              if (caloriesRaw.isNotEmpty) 'calories': int.tryParse(caloriesRaw),
              'meals': mealsJson,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', planId);
      } else {
        await client.from('diet_plans').insert({
          'member_id': widget.memberId,
          'name': name,
          'goal': _goal,
          if (caloriesRaw.isNotEmpty) 'calories': int.tryParse(caloriesRaw),
          'meals': mealsJson,
          'is_active': true,
          'created_by': client.auth.currentUser?.id,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[GymCRM] Save diet plan error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save plan')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.plan != null;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.memberName,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onDarkSoft,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEdit ? 'Edit diet plan' : 'New diet plan',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onDark,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.close, color: AppTheme.onDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Plan name'),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Lean Bulk',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Goal'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _goals
                          .map(
                            (g) => PillChip(
                              label: _goalLabels[g]!,
                              selected: _goal == g,
                              onTap: () => setState(() => _goal = g),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Daily calorie target (optional)'),
                    TextFormField(
                      controller: _caloriesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 2000',
                        suffixText: 'kcal',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: FieldLabel('Meals')),
                        GestureDetector(
                          onTap: () => setState(
                            () => _meals.add(
                              _MealData(nameText: 'Meal ${_meals.length + 1}'),
                            ),
                          ),
                          child: const Text(
                            '+ Add meal',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _meals.length; i++) _buildMealCard(i),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(isEdit ? 'Save changes' : 'Save diet plan'),
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

  Widget _buildMealCard(int mealIdx) {
    final meal = _meals[mealIdx];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meal header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: meal.name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Meal name',
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: meal.time,
                    decoration: const InputDecoration(
                      hintText: '8:00 AM',
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ),
                if (_meals.length > 1)
                  GestureDetector(
                    onTap: () => setState(() {
                      _meals[mealIdx].dispose();
                      _meals.removeAt(mealIdx);
                    }),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        AppIcons.removeCircle,
                        size: 20,
                        color: AppTheme.statusDanger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Food items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (int fi = 0; fi < meal.items.length; fi++)
                  _buildFoodItemRow(mealIdx, fi),
              ],
            ),
          ),
          // Add food item button
          GestureDetector(
            onTap: () => setState(() => _meals[mealIdx].items.add(_FoodItem())),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                '+ Add food item',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodItemRow(int mealIdx, int fi) {
    final item = _meals[mealIdx].items[fi];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${fi + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: item.food,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Food item',
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _meals[mealIdx].items[fi].dispose();
                  _meals[mealIdx].items.removeAt(fi);
                }),
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(AppIcons.close, size: 16, color: AppTheme.inkHint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 1: quantity + calories (wider, most used)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _macroField(
                  label: 'Qty',
                  ctrl: item.qty,
                  hint: '100g',
                  numeric: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _macroField(
                  label: 'Kcal',
                  ctrl: item.calories,
                  hint: '350',
                  numeric: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: macros
          Row(
            children: [
              Expanded(
                child: _macroField(
                  label: 'Protein',
                  ctrl: item.protein,
                  hint: '12g',
                  numeric: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _macroField(
                  label: 'Carbs',
                  ctrl: item.carbs,
                  hint: '60g',
                  numeric: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _macroField(
                  label: 'Fat',
                  ctrl: item.fat,
                  hint: '5g',
                  numeric: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroField({
    required String label,
    required TextEditingController ctrl,
    required String hint,
    required bool numeric,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextFormField(
          controller: ctrl,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          textAlign: TextAlign.center,
          decoration: InputDecoration(isDense: true, hintText: hint),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
      ],
    );
  }
}
