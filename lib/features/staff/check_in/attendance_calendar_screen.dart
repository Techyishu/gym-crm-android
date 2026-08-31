import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

class AttendanceCalendarScreen extends ConsumerStatefulWidget {
  const AttendanceCalendarScreen({super.key});

  @override
  ConsumerState<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState
    extends ConsumerState<AttendanceCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  List<Map<String, dynamic>> _records = const [];
  Map<String, dynamic> _permissions = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String _key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final raw = await ref
          .read(supabaseProvider)
          .rpc(
            'get_attendance_calendar',
            params: {
              'p_gym_id': gymId,
              'p_month': _key(_month),
              'p_member_id': null,
            },
          );
      final result = Map<String, dynamic>.from(raw as Map);
      if (!mounted) return;
      setState(() {
        _records = (result['records'] as List? ?? const [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _permissions = Map<String, dynamic>.from(
          result['permissions'] as Map? ?? const {},
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _selectedRecords =>
      _records.where((row) => row['date'] == _key(_selected)).toList();

  void _changeMonth(int offset) {
    final month = DateTime(_month.year, _month.month + offset);
    final today = DateTime.now();
    setState(() {
      _month = month;
      _selected = month.year == today.year && month.month == today.month
          ? today
          : month;
    });
    _load();
  }

  Future<void> _openEditor([Map<String, dynamic>? record]) async {
    if (record == null && _permissions['add'] != true) {
      _denied('add attendance');
      return;
    }
    if (record != null && _permissions['edit'] != true) {
      _denied('edit attendance');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AttendanceEditorSheet(date: _selected, record: record),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> record) async {
    if (_permissions['delete'] != true) {
      _denied('delete attendance');
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Delete attendance?',
        actionLabel: 'Delete',
      ),
    );
    if (reason == null) return;
    try {
      final gymId = await ref.read(gymIdProvider.future);
      await ref
          .read(supabaseProvider)
          .rpc(
            'delete_manual_attendance',
            params: {
              'p_gym_id': gymId,
              'p_check_in_id': record['id'],
              'p_reason': reason,
            },
          );
      _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_attendanceError(error))));
      }
    }
  }

  void _denied(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("You don't have permission to $action.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Attendance calendar')),
      body: ResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ErrorState(what: 'attendance', onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  children: [
                    _monthHeader(),
                    const SizedBox(height: 10),
                    _calendar(),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('EEEE, d MMMM').format(_selected),
                            style: AppTheme.sectionTitle,
                          ),
                        ),
                        Text(
                          '${_selectedRecords.length} present',
                          style: const TextStyle(color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_selectedRecords.isEmpty)
                      const StateMessage(
                        icon: AppIcons.eventBusy,
                        title: 'No attendance recorded',
                        body:
                            'Choose Add attendance to record a manual correction.',
                      )
                    else
                      Container(
                        decoration: AppTheme.cardDecoration(radius: 12),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < _selectedRecords.length;
                              index++
                            ) ...[
                              _recordRow(_selectedRecords[index]),
                              if (index != _selectedRecords.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton:
          _permissions['add'] == true && !_selected.isAfter(DateTime.now())
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(AppIcons.add),
              label: const Text('Add attendance'),
            )
          : null,
    );
  }

  Widget _monthHeader() => Row(
    children: [
      IconButton(
        onPressed: () => _changeMonth(-1),
        icon: const Icon(AppIcons.chevronLeft),
      ),
      Expanded(
        child: Text(
          DateFormat('MMMM yyyy').format(_month),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      IconButton(
        onPressed:
            DateTime(
              _month.year,
              _month.month + 1,
            ).isAfter(DateTime(DateTime.now().year, DateTime.now().month))
            ? null
            : () => _changeMonth(1),
        icon: const Icon(AppIcons.chevronRight),
      ),
    ],
  );

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month);
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final leading = first.weekday - 1;
    final counts = <String, int>{};
    for (final record in _records) {
      final key = record['date'] as String;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: AppTheme.cardDecoration(radius: 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkHint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.92,
            ),
            itemCount: leading + days,
            itemBuilder: (_, index) {
              if (index < leading) return const SizedBox.shrink();
              final day = index - leading + 1;
              final date = DateTime(_month.year, _month.month, day);
              final selected = DateUtils.isSameDay(date, _selected);
              final count = counts[_key(date)] ?? 0;
              final future = date.isAfter(DateTime.now());
              return InkWell(
                onTap: future ? null : () => setState(() => _selected = date),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: future
                              ? AppTheme.border
                              : selected
                              ? Colors.white
                              : AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.accent
                                : AppTheme.activeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : AppTheme.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _recordRow(Map<String, dynamic> record) {
    final inAt = DateTime.parse(record['checked_in_at'] as String).toLocal();
    final outRaw = record['checked_out_at'] as String?;
    final outAt = outRaw == null ? null : DateTime.parse(outRaw).toLocal();
    return ListTile(
      title: Text(
        record['member_name'] as String? ?? 'Member',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${DateFormat('h:mm a').format(inAt)}${outAt == null ? '' : ' – ${DateFormat('h:mm a').format(outAt)}'} · ${_methodLabel(record['method'] as String?)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) =>
            value == 'edit' ? _openEditor(record) : _delete(record),
        itemBuilder: (_) => [
          if (_permissions['edit'] == true)
            const PopupMenuItem(value: 'edit', child: Text('Edit correction')),
          if (_permissions['delete'] == true)
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: _permissions['edit'] == true ? () => _openEditor(record) : null,
    );
  }
}

class _AttendanceEditorSheet extends ConsumerStatefulWidget {
  final DateTime date;
  final Map<String, dynamic>? record;

  const _AttendanceEditorSheet({required this.date, this.record});

  @override
  ConsumerState<_AttendanceEditorSheet> createState() =>
      _AttendanceEditorSheetState();
}

class _AttendanceEditorSheetState
    extends ConsumerState<_AttendanceEditorSheet> {
  final _search = TextEditingController();
  final _reason = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _members = const [];
  String? _memberId;
  String? _memberName;
  TimeOfDay _checkIn = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay? _checkOut;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) {
      _memberId = record['member_id'] as String?;
      _memberName = record['member_name'] as String?;
      _reason.text = record['manual_reason'] as String? ?? '';
      final inAt = DateTime.parse(record['checked_in_at'] as String).toLocal();
      _checkIn = TimeOfDay.fromDateTime(inAt);
      final outRaw = record['checked_out_at'] as String?;
      if (outRaw != null) {
        _checkOut = TimeOfDay.fromDateTime(DateTime.parse(outRaw).toLocal());
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _find(value));
  }

  Future<void> _find(String query) async {
    if (query.trim().length < 2) {
      if (mounted) setState(() => _members = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final pattern = '%${query.trim()}%';
      final raw = await ref
          .read(supabaseProvider)
          .from('members')
          .select('id, first_name, last_name, status')
          .eq('gym_id', gymId)
          .or('first_name.ilike.$pattern,last_name.ilike.$pattern')
          .limit(12);
      if (mounted) {
        setState(
          () => _members = (raw as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickTime(bool checkout) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: checkout ? _checkOut ?? _checkIn : _checkIn,
    );
    if (picked != null) {
      setState(() {
        if (checkout) {
          _checkOut = picked;
        } else {
          _checkIn = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_memberId == null) {
      setState(() => _error = 'Select a member.');
      return;
    }
    if (_reason.text.trim().length < 5) {
      setState(() => _error = 'Enter a clear reason (at least 5 characters).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      await ref
          .read(supabaseProvider)
          .rpc(
            'upsert_manual_attendance',
            params: {
              'p_gym_id': gymId,
              'p_member_id': _memberId,
              'p_attendance_date': _date(widget.date),
              'p_check_in_time': _time(_checkIn),
              'p_check_out_time': _checkOut == null ? null : _time(_checkOut!),
              'p_reason': _reason.text.trim(),
              'p_check_in_id': widget.record?['id'],
            },
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _attendanceError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.record == null ? 'Add attendance' : 'Correct attendance',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, d MMMM yyyy').format(widget.date),
              style: const TextStyle(color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 18),
            if (_memberId == null) ...[
              TextField(
                controller: _search,
                onChanged: _searchChanged,
                decoration: InputDecoration(
                  labelText: 'Search member',
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              ..._members.map(
                (member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'
                        .trim(),
                  ),
                  subtitle: Text(member['status'] as String? ?? ''),
                  onTap: () => setState(() {
                    _memberId = member['id'] as String?;
                    _memberName =
                        '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'
                            .trim();
                    _members = const [];
                  }),
                ),
              ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(AppIcons.person)),
                title: Text(_memberName ?? 'Member'),
                trailing: widget.record == null
                    ? TextButton(
                        onPressed: () => setState(() {
                          _memberId = null;
                          _memberName = null;
                        }),
                        child: const Text('Change'),
                      )
                    : null,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(AppIcons.login),
                    label: Text('In ${_checkIn.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(AppIcons.logout),
                    label: Text(
                      _checkOut == null
                          ? 'No checkout'
                          : 'Out ${_checkOut!.format(context)}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason for manual change',
                hintText: 'Example: biometric device was offline',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.statusDanger),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save attendance'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String actionLabel;

  const _ReasonDialog({required this.title, required this.actionLabel});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppTheme.surface,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: 'Reason', errorText: _error),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: DialogButton(
                  label: 'Cancel',
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DialogButton(
                  label: widget.actionLabel,
                  filled: true,
                  onTap: () {
                    if (_controller.text.trim().length < 5) {
                      setState(() => _error = 'Enter at least 5 characters');
                      return;
                    }
                    Navigator.pop(context, _controller.text.trim());
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _time(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

String _methodLabel(String? method) => switch (method) {
  'manual_backdated' => 'manual correction',
  'biometric' => 'biometric',
  'qr' => 'QR',
  _ => 'manual',
};

String _attendanceError(Object error) {
  final text = '$error';
  if (text.contains('attendance_already_exists_for_date')) {
    return 'This member already has attendance recorded for that date.';
  }
  if (text.contains('permission_denied')) {
    return "You don't have permission for this attendance change.";
  }
  if (text.contains('attendance_reason_required')) {
    return 'A clear reason is required.';
  }
  if (text.contains('checkout_before_checkin')) {
    return 'Checkout time cannot be before check-in time.';
  }
  return 'Could not save attendance. Please try again.';
}
