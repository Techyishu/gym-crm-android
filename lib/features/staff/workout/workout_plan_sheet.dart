import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class _ExData {
  final TextEditingController name;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;
  final TextEditingController notes;

  _ExData({String n = '', String s = '', String r = '', String w = '', String nt = ''})
      : name = TextEditingController(text: n),
        sets = TextEditingController(text: s),
        reps = TextEditingController(text: r),
        weight = TextEditingController(text: w),
        notes = TextEditingController(text: nt);

  factory _ExData.fromJson(Map<String, dynamic> j) => _ExData(
        n: j['name'] as String? ?? '',
        s: j['sets'] as String? ?? '',
        r: j['reps'] as String? ?? '',
        w: j['weight'] as String? ?? '',
        nt: j['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name.text.trim(),
        'sets': sets.text.trim(),
        'reps': reps.text.trim(),
        'weight': weight.text.trim(),
        'notes': notes.text.trim(),
      };

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
    weight.dispose();
    notes.dispose();
  }
}

class _DayData {
  final TextEditingController label;
  final List<_ExData> exercises;

  _DayData({required String labelText, List<_ExData>? exercises})
      : label = TextEditingController(text: labelText),
        exercises = exercises ?? [];

  factory _DayData.fromJson(Map<String, dynamic> j) => _DayData(
        labelText: j['label'] as String? ?? '',
        exercises: ((j['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [])
            .map(_ExData.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'label': label.text.trim(),
        'exercises': exercises
            .where((e) => e.name.text.trim().isNotEmpty)
            .map((e) => e.toJson())
            .toList(),
      };

  void dispose() {
    label.dispose();
    for (final e in exercises) {
      e.dispose();
    }
  }
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class WorkoutPlanSheet extends StatefulWidget {
  final String memberId;
  final String memberName;
  final Map<String, dynamic>? plan; // null = create, non-null = edit

  const WorkoutPlanSheet({
    super.key,
    required this.memberId,
    required this.memberName,
    this.plan,
  });

  @override
  State<WorkoutPlanSheet> createState() => _WorkoutPlanSheetState();
}

class _WorkoutPlanSheetState extends State<WorkoutPlanSheet> {
  late final TextEditingController _nameCtrl;
  late String _type;
  late List<_DayData> _days;
  bool _saving = false;

  static const _weekLabels = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _type = p?['type'] as String? ?? 'daily';
    final rawDays = p?['days'] as List?;
    if (rawDays != null && rawDays.isNotEmpty) {
      _days = rawDays.cast<Map<String, dynamic>>().map(_DayData.fromJson).toList();
    } else {
      _days = _buildDefaultDays(_type);
    }
  }

  List<_DayData> _buildDefaultDays(String type) {
    if (type == 'weekly') {
      return _weekLabels.map((l) => _DayData(labelText: l)).toList();
    }
    if (type == 'monthly') {
      return ['Week 1', 'Week 2', 'Week 3', 'Week 4']
          .map((l) => _DayData(labelText: l))
          .toList();
    }
    return [_DayData(labelText: 'Daily Routine')];
  }

  void _switchType(String t) {
    if (t == _type) return;
    setState(() {
      for (final d in _days) {
        d.dispose();
      }
      _type = t;
      _days = _buildDefaultDays(t);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a plan name')));
      return;
    }
    final daysJson = _days.map((d) => d.toJson()).toList();
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final planId = widget.plan?['id'] as String?;
      if (planId != null) {
        await client.from('workout_plans').update({
          'name': name,
          'type': _type,
          'days': daysJson,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', planId);
      } else {
        await client.from('workout_plans').insert({
          'member_id': widget.memberId,
          'name': name,
          'type': _type,
          'days': daysJson,
          'is_active': true,
          'created_by': client.auth.currentUser?.id,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[GymCRM] Save workout plan error: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to save plan')));
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
            width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
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
                      Text(widget.memberName,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
                      const SizedBox(height: 2),
                      Text(
                        isEdit ? 'Edit workout plan' : 'New workout plan',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.onDark),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.onDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Scrollable body
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
                      decoration: const InputDecoration(hintText: 'e.g. Push · Pull · Legs'),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Type'),
                    Row(
                      children: ['daily', 'weekly', 'monthly'].map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PillChip(
                          label: t[0].toUpperCase() + t.substring(1),
                          selected: _type == t,
                          onTap: () => _switchType(t),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 20),
                    // Days
                    for (int i = 0; i < _days.length; i++) _buildDayCard(i),
                    if (_type == 'weekly') ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => setState(
                            () => _days.add(_DayData(labelText: 'Day ${_days.length + 1}'))),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('+ Add another day',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(isEdit ? 'Save changes' : 'Save workout plan'),
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

  Widget _buildDayCard(int dayIdx) {
    final day = _days[dayIdx];
    final canRemove = _type == 'weekly' || _days.length > 1;
    final label = day.label.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day label header
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ),
              if (canRemove)
                GestureDetector(
                  onTap: () => setState(() {
                    _days[dayIdx].dispose();
                    _days.removeAt(dayIdx);
                  }),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.remove_circle_outline,
                        size: 18, color: AppTheme.statusDanger),
                  ),
                ),
            ],
          ),
        ),
        // Exercise cards
        for (int exIdx = 0; exIdx < day.exercises.length; exIdx++)
          _buildExerciseRow(dayIdx, exIdx),
        // Add exercise button
        GestureDetector(
          onTap: () => setState(() => _days[dayIdx].exercises.add(_ExData())),
          child: const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text('+ Add another exercise',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent)),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseRow(int dayIdx, int exIdx) {
    final ex = _days[dayIdx].exercises[exIdx];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Exercise name row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text('${exIdx + 1}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.inkSoft)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: ex.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Exercise name', isDense: true),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _days[dayIdx].exercises[exIdx].dispose();
                  _days[dayIdx].exercises.removeAt(exIdx);
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: AppTheme.inkHint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sets / Reps / Weight
          Row(
            children: [
              _statField(label: 'Sets',   ctrl: ex.sets,   hint: '3',     numeric: true),
              const SizedBox(width: 8),
              _statField(label: 'Reps',   ctrl: ex.reps,   hint: '12',    numeric: true),
              const SizedBox(width: 8),
              _statField(label: 'Weight', ctrl: ex.weight, hint: '20 kg', numeric: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statField({
    required String label,
    required TextEditingController ctrl,
    required String hint,
    required bool numeric,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          TextFormField(
            controller: ctrl,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            textAlign: TextAlign.center,
            decoration: InputDecoration(isDense: true, hintText: hint),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
          ),
        ],
      ),
    );
  }
}
