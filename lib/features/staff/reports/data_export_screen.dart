import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/csv_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

class DataExportScreen extends ConsumerStatefulWidget {
  const DataExportScreen({super.key});

  @override
  ConsumerState<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends ConsumerState<DataExportScreen> {
  final _search = TextEditingController();
  String _type = 'members';
  String? _status;
  String? _method;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  CsvExportPreview? _preview;
  bool _loading = false;
  bool _sharing = false;
  String? _error;

  static const _types = <String, String>{
    'members': 'Members',
    'payments': 'Payments',
    'dues': 'Dues & outstanding',
    'attendance': 'Attendance',
    'leads': 'Leads',
    'expenses': 'Expenses',
    'activity_logs': 'Activity logs',
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _filtersChanged() => setState(() {
    _preview = null;
    _error = null;
  });

  Map<String, dynamic> get _filters => {
    if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    if (_status != null) 'status': _status,
    if (_method != null) 'method': _method,
  };

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final preview = await CsvExportService(ref.read(supabaseProvider))
          .prepare(
            gymId: gymId,
            type: _type,
            from: _range.start,
            to: _range.end,
            filters: _filters,
          );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyExportError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export({required bool share}) async {
    final preview = _preview;
    if (preview == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final service = CsvExportService(ref.read(supabaseProvider));
      final shared = share
          ? await service.shareAndComplete(preview)
          : await service.saveAndComplete(preview);
      if (!mounted) return;
      if (!shared) {
        // Keep the preview so backing out of the share sheet doesn't cost
        // them the query they just built.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export cancelled')),
        );
        return;
      }
      setState(() => _preview = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${preview.rows.length} rows exported')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not export the CSV. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      _filtersChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Export data')),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            const Text('Dataset', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _type,
              items: _types.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _type = value ?? 'members';
                  _status = null;
                  _method = null;
                });
                _filtersChanged();
              },
              decoration: const InputDecoration(labelText: 'Export type'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(AppIcons.dateRange),
              label: Text(
                '${DateFormat('d MMM yyyy').format(_range.start)} – ${DateFormat('d MMM yyyy').format(_range.end)}',
              ),
            ),
            const SizedBox(height: 18),
            const Text('Filters', style: AppTheme.sectionTitle),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              onChanged: (_) => _filtersChanged(),
              decoration: const InputDecoration(
                labelText: 'Search name or record',
                prefixIcon: Icon(AppIcons.search),
              ),
            ),
            if ({'members', 'payments', 'leads'}.contains(_type)) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: _status,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ..._statusOptions(_type).map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_title(value)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _status = value);
                  _filtersChanged();
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ],
            if ({'payments', 'attendance'}.contains(_type)) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: _method,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All methods'),
                  ),
                  ..._methodOptions(_type).map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_title(value)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _method = value);
                  _filtersChanged();
                },
                decoration: const InputDecoration(labelText: 'Method'),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loading ? null : _prepare,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(AppIcons.preview),
              label: const Text('Preview filtered data'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              StateMessage(
                icon: AppIcons.lock,
                tint: AppTheme.statusDanger,
                tintBg: AppTheme.statusDangerBg,
                title: 'Export unavailable',
                body: _error!,
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 24),
              _previewHeader(_preview!),
              const SizedBox(height: 10),
              _previewTable(_preview!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _preview == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  // "Export" used to mean "open the share sheet", which left
                  // no file on the phone. Saving is the primary action now;
                  // sharing is still one tap away beside it.
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : () => _export(share: false),
                      icon: const Icon(AppIcons.download),
                      label: Text(
                        _sharing
                            ? 'Preparing CSV…'
                            : 'Save ${_preview!.rows.length} rows',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _sharing ? null : () => _export(share: true),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(56, 52),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(AppIcons.iosShare),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _previewHeader(CsvExportPreview preview) => Row(
    children: [
      Expanded(
        child: Text(
          '${preview.rows.length} filtered row${preview.rows.length == 1 ? '' : 's'}',
          style: AppTheme.sectionTitle,
        ),
      ),
      Text(
        preview.piiIncluded ? 'PII included' : 'PII hidden',
        style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
      ),
    ],
  );

  Widget _previewTable(CsvExportPreview preview) {
    if (preview.rows.isEmpty) {
      return const StateMessage(
        icon: AppIcons.filterOff,
        title: 'No rows match these filters',
        body: 'Change the date range or filters and preview again.',
      );
    }
    final visibleRows = preview.rows.take(50).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: preview.columns
              .map((column) => DataColumn(label: Text(column)))
              .toList(),
          rows: visibleRows
              .map(
                (row) => DataRow(
                  cells: preview.columns
                      .map(
                        (column) => DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              _value(row[column]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

List<String> _statusOptions(String type) => switch (type) {
  'members' => ['active', 'frozen', 'expired', 'cancelled', 'blocked'],
  'payments' => ['succeeded', 'refunded', 'failed'],
  'leads' => ['new', 'contacted', 'trial', 'converted', 'lost'],
  _ => const [],
};

List<String> _methodOptions(String type) => switch (type) {
  'payments' => ['cash', 'upi', 'card', 'bank_transfer'],
  'attendance' => ['manual', 'manual_backdated', 'qr', 'biometric'],
  _ => const [],
};

String _title(String value) => value
    .split('_')
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _value(Object? value) =>
    value == null || '$value'.isEmpty ? '—' : '$value';

String _friendlyExportError(Object error) {
  final text = '$error';
  if (text.contains('permission_denied')) {
    return "You don't have permission to view or export this dataset.";
  }
  if (text.contains('date_range_too_large')) {
    return 'Choose a date range of five years or less.';
  }
  return 'The filtered dataset could not be prepared. Please try again.';
}
