import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/gym_class.dart';
import '../../auth/providers/auth_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Fetches all classes (batches) for the gym.
final _classesProvider = FutureProvider<List<GymClass>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('classes')
      .select()
      .eq('gym_id', gymId)
      .order('name');

  return (data as List).map((e) => GymClass.fromJson(e as Map<String, dynamic>)).toList();
});

/// Fetches upcoming sessions grouped by class_id.
final _upcomingSessionsProvider =
    FutureProvider<Map<String, List<ClassSession>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('class_sessions')
      .select('*, classes!inner(*, gym_id)')
      .eq('classes.gym_id', gymId)
      .gte('starts_at',
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String())
      .order('starts_at')
      .limit(50);

  final sessions =
      (data as List).map((e) => ClassSession.fromJson(e as Map<String, dynamic>)).toList();

  final grouped = <String, List<ClassSession>>{};
  for (final s in sessions) {
    grouped.putIfAbsent(s.classId, () => []).add(s);
  }
  return grouped;
});

// ── Constants ─────────────────────────────────────────────────────────────────

const _classTypes = [
  'general', 'yoga', 'hiit', 'spin', 'boxing', 'pilates', 'crossfit', 'zumba', 'swimming'
];

const _colorSwatches = [
  '#6366F1', '#3B82F6', '#10B981', '#F59E0B',
  '#EF4444', '#8B5CF6', '#EC4899', '#0EA5E9',
];

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _parseColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (e) {
    debugPrint('[GymCRM] Parse color error: $e');
    return AppTheme.ink;
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _formatTime(DateTime dt) {
  final h = dt.hour > 12
      ? dt.hour - 12
      : (dt.hour == 0 ? 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $period';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(_classesProvider);
    final sessionsAsync = ref.watch(_upcomingSessionsProvider);

    void openAddSheet() => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _ClassFormSheet(),
        ).then((_) {
          ref.invalidate(_classesProvider);
          ref.invalidate(_upcomingSessionsProvider);
        });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Batches'),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: openAddSheet,
          ),
        ],
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (classes) {
          if (classes.isEmpty) {
            return _EmptyBatches(onAdd: openAddSheet);
          }

          final sessionMap = sessionsAsync.maybeWhen(
            data: (m) => m,
            orElse: () => <String, List<ClassSession>>{},
          );

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_classesProvider);
              ref.invalidate(_upcomingSessionsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: classes.length,
              itemBuilder: (_, i) => _ClassCard(
                gymClass: classes[i],
                sessions: sessionMap[classes[i].id] ?? [],
                onEdit: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _ClassFormSheet(cls: {
                    'id': classes[i].id,
                    'name': classes[i].name,
                    'type': classes[i].type,
                    'color': classes[i].color,
                    'capacity': classes[i].capacity,
                    'description': classes[i].description,
                    'default_start_time': classes[i].defaultStartTime,
                    'default_end_time': classes[i].defaultEndTime,
                    'trainer_name': classes[i].trainerName,
                    'schedule_days': classes[i].scheduleDays,
                  }),
                ).then((_) {
                  ref.invalidate(_classesProvider);
                  ref.invalidate(_upcomingSessionsProvider);
                }),
                onAddSession: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _AddSessionSheet(gymClass: classes[i]),
                ).then((_) => ref.invalidate(_upcomingSessionsProvider)),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Add Session Sheet ─────────────────────────────────────────────────────────
// Creates a one-off class_sessions row. Mirrors the web add-session-dialog:
// end time is derived from the class default_end_time or duration_min.
class _AddSessionSheet extends StatefulWidget {
  final GymClass gymClass;
  const _AddSessionSheet({required this.gymClass});

  @override
  State<_AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends State<_AddSessionSheet> {
  late DateTime _date;
  late TimeOfDay _start;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _start = _ClassFormSheetState._parseHm(widget.gymClass.defaultStartTime) ??
        const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _start);
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final cls = widget.gymClass;
      final starts = DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);

      // End = class default_end_time on the same day, else start + duration.
      DateTime ends;
      final end = _ClassFormSheetState._parseHm(cls.defaultEndTime);
      if (end != null) {
        ends = DateTime(_date.year, _date.month, _date.day, end.hour, end.minute);
        if (!ends.isAfter(starts)) {
          ends = starts.add(Duration(minutes: cls.durationMin));
        }
      } else {
        ends = starts.add(Duration(minutes: cls.durationMin));
      }

      await Supabase.instance.client.from('class_sessions').insert({
        'class_id': cls.id,
        'starts_at': starts.toUtc().toIso8601String(),
        'ends_at': ends.toUtc().toIso8601String(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Add Session — ${widget.gymClass.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                    ),
                    child: Text(formatDateFromString(_date.toIso8601String())),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickTime,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start time',
                      suffixIcon: Icon(Icons.access_time_outlined, size: 16),
                    ),
                    child: Text(_start.format(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Add Session'),
          ),
        ],
      ),
    );
  }
}

// ── Class card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatefulWidget {
  final GymClass gymClass;
  final List<ClassSession> sessions;
  final VoidCallback onEdit;
  final VoidCallback onAddSession;
  const _ClassCard({
    required this.gymClass,
    required this.sessions,
    required this.onEdit,
    required this.onAddSession,
  });

  @override
  State<_ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<_ClassCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cls = widget.gymClass;
    final color = _parseColor(cls.color);
    final sessions = widget.sessions;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Main card content
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left color strip
              Container(
                width: 4,
                color: color,
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + type badge + menu
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cls.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.activeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _capitalize(cls.type),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: widget.onEdit,
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.edit_outlined,
                                  size: 16, color: AppTheme.inkHint),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Capacity info
                      Row(
                        children: [
                          const Icon(Icons.people_outline,
                              size: 13, color: AppTheme.inkHint),
                          const SizedBox(width: 4),
                          Text(
                            'Capacity: ${cls.capacity}  ·  ${cls.durationMin} min',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Schedule info
                      Row(
                        children: [
                          const Icon(Icons.schedule_outlined,
                              size: 13, color: AppTheme.inkHint),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              cls.description != null && cls.description!.isNotEmpty
                                  ? cls.description!
                                  : '${sessions.length} upcoming session${sessions.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.inkHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // "View Sessions" button
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _expanded ? 'Hide Sessions' : 'View Sessions',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.ink,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppTheme.ink,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expandable sessions list
          if (_expanded) ...[
            const Divider(height: 1),
            if (sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No upcoming sessions',
                    style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
                  ),
                ),
              )
            else
              ...sessions.map((s) => _SessionRow(
                    session: s,
                    classCapacity: cls.capacity,
                  )),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: OutlinedButton.icon(
                onPressed: widget.onAddSession,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add session'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 42)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Session row ───────────────────────────────────────────────────────────────

class _SessionRow extends StatelessWidget {
  final ClassSession session;
  final int classCapacity;
  const _SessionRow({required this.session, required this.classCapacity});

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(session.startsAt)?.toLocal();
    final end = DateTime.tryParse(session.endsAt)?.toLocal();
    final enrolled = session.bookingCount ?? 0;
    final capacity = session.capacityOverride ?? classCapacity;

    final statusColors = {
      'scheduled': (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
      'completed': (AppTheme.statusActiveBg, AppTheme.statusActive),
      'cancelled': (AppTheme.statusDangerBg, AppTheme.statusDanger),
    };
    final c = statusColors[session.status] ?? (AppTheme.activeBg, AppTheme.inkSoft);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const SizedBox(width: 4), // offset for the color strip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (start != null)
                      Text(
                        formatDate(start),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.ink,
                        ),
                      ),
                    if (start != null && end != null)
                      Text(
                        '${_formatTime(start)} – ${_formatTime(end)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
              // Enrolled/capacity
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.activeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline,
                        size: 12, color: AppTheme.inkSoft),
                    const SizedBox(width: 3),
                    Text(
                      '$enrolled/$capacity',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.$1,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _capitalize(session.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.$2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyBatches extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyBatches({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.activeBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.fitness_center_outlined,
                size: 48,
                color: AppTheme.inkHint,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No batches yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first class to get started.',
              style: TextStyle(color: AppTheme.inkSoft, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Batch'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Class form sheet ──────────────────────────────────────────────────────────

class _ClassFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? cls;
  const _ClassFormSheet({this.cls});

  @override
  ConsumerState<_ClassFormSheet> createState() => _ClassFormSheetState();
}

class _ClassFormSheetState extends ConsumerState<_ClassFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _trainerCtrl;
  late final TextEditingController _descCtrl;

  String _type = 'general';
  String _color = '#6366F1';
  TimeOfDay _startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 7, minute: 0);
  final Set<int> _scheduleDays = {}; // 1=Mon … 7=Sun (matches web)
  bool _loading = false;

  // Day-of-week labels for the "Runs on" selector (num, label, full).
  static const _days = [
    (1, 'M', 'Mon'),
    (2, 'T', 'Tue'),
    (3, 'W', 'Wed'),
    (4, 'T', 'Thu'),
    (5, 'F', 'Fri'),
    (6, 'S', 'Sat'),
    (7, 'S', 'Sun'),
  ];

  bool get _isEdit => widget.cls != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cls;
    _nameCtrl = TextEditingController(text: c?['name'] as String? ?? '');
    _capacityCtrl =
        TextEditingController(text: c?['capacity']?.toString() ?? '20');
    _trainerCtrl = TextEditingController(text: c?['trainer_name'] as String? ?? '');
    _descCtrl = TextEditingController(text: c?['description'] as String? ?? '');
    _type = c?['type'] as String? ?? 'general';
    _color = c?['color'] as String? ?? '#6366F1';
    final days = c?['schedule_days'] as List?;
    if (days != null) _scheduleDays.addAll(days.map((e) => e as int));
    final start = _parseHm(c?['default_start_time'] as String?);
    if (start != null) _startTime = start;
    final end = _parseHm(c?['default_end_time'] as String?);
    if (end != null) _endTime = end;
  }

  static TimeOfDay? _parseHm(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    _trainerCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null && mounted) {
      setState(() => isStart ? _startTime = picked : _endTime = picked);
    }
  }

  String _formatTod(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period.name.toUpperCase()}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final startStr =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';
    final durationMin = (_endTime.hour * 60 + _endTime.minute) -
        (_startTime.hour * 60 + _startTime.minute);

    try {
      final client = Supabase.instance.client;
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'color': _color,
        'capacity': int.tryParse(_capacityCtrl.text.trim()) ?? 20,
        'duration_min': durationMin > 0 ? durationMin : 60,
        'default_start_time': startStr,
        'default_end_time': endStr,
        'schedule_days': (_scheduleDays.toList()..sort()),
        if (_trainerCtrl.text.trim().isNotEmpty) 'trainer_name': _trainerCtrl.text.trim(),
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      };

      if (_isEdit) {
        await client.from('classes').update(data).eq('id', widget.cls!['id']);
      } else {
        data['gym_id'] = await ref.read(gymIdProvider.future);
        await client.from('classes').insert(data);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdit ? 'Edit Batch' : 'New Batch',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppTheme.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Class name *'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: _classTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_capitalize(t)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _trainerCtrl,
                decoration: const InputDecoration(labelText: 'Trainer name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacityCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacity'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(true),
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Start time',
                          suffixIcon: Icon(Icons.access_time_outlined, size: 16),
                        ),
                        child: Text(_formatTod(_startTime)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickTime(false),
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'End time',
                          suffixIcon: Icon(Icons.access_time_outlined, size: 16),
                        ),
                        child: Text(_formatTod(_endTime)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Runs-on day selector (drives auto-generated sessions)
              const Text(
                'Runs on',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _days.map((d) {
                  final active = _scheduleDays.contains(d.$1);
                  return GestureDetector(
                    onTap: () => setState(() {
                      active ? _scheduleDays.remove(d.$1) : _scheduleDays.add(d.$1);
                    }),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppTheme.ink : AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: active ? AppTheme.ink : AppTheme.border),
                      ),
                      child: Text(
                        d.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppTheme.inkSoft,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _scheduleDays.isEmpty
                      ? 'No days selected — add sessions manually from the calendar.'
                      : '${_scheduleDays.length} day${_scheduleDays.length > 1 ? 's' : ''} selected',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                ),
              ),
              const SizedBox(height: 16),

              // Color picker
              const Text(
                'Colour',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _colorSwatches.map((hex) {
                  final selected = _color == hex;
                  final c = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                  return GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: AppTheme.ink, width: 2.5)
                            : Border.all(
                                color: Colors.transparent, width: 2.5),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color: c.withValues(alpha: 0.4),
                                    blurRadius: 6)
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(_isEdit ? 'Save Changes' : 'Create Batch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
