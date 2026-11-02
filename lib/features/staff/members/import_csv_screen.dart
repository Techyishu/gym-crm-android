import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/billing/advance_payment_date.dart';
import '../../../core/billing/plan_limits.dart';
import '../../../core/services/app_events.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/utils/validators.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

/// Bulk member import from a CSV file. Mirrors the web import-csv-dialog:
/// upload → preview (valid/invalid) → assign an optional plan → import.
/// Replicates the server validation + dedupe from /api/members/import.

const _csvColumns = [
  'first_name',
  'last_name',
  'email',
  'phone',
  'notes',
  'status',
  'joined_at',
];
// Only a name is required: most gym registers have a name and a phone, not an
// email. Email and phone, when present, are what duplicates are matched on.
const _requiredColumns = {'first_name'};
const _validStatuses = {'active', 'frozen', 'expired', 'cancelled', ''};
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

final _importPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  final data = await client
      .from('membership_plans')
      .select('id, name, price, billing_interval, billing_interval_months')
      .eq('gym_id', gymId)
      .eq('is_active', true)
      // Day passes don't renew, so they make no sense for a bulk import.
      .isFilter('billing_interval_days', null)
      .order('price');
  return (data as List).cast<Map<String, dynamic>>();
});

String _planLabel(Map<String, dynamic> p) {
  final price = (p['price'] as num?)?.toStringAsFixed(0) ?? '0';
  final interval = p['billing_interval'] as String? ?? '';
  const short = {
    'monthly': 'mo',
    'quarterly': 'qtr',
    'biannual': '6mo',
    'annual': 'yr',
  };
  final unit = interval == 'custom'
      ? '${p['billing_interval_months'] ?? ''}mo'
      : (short[interval] ?? interval);
  return '${p['name']} — $currencySymbol$price/$unit';
}

enum _Phase { upload, preview, importing, done }

class _CsvRow {
  final String firstName, lastName, email, phone, notes, status, joinedAt;
  _CsvRow(
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.notes,
    this.status,
    this.joinedAt,
  );
}

class _Invalid {
  final int row;
  final String email;
  final String reason;
  _Invalid(this.row, this.email, this.reason);
}

class ImportCsvScreen extends ConsumerStatefulWidget {
  /// Rows to import instead of a file (e.g. picked phone contacts), keyed by
  /// the CSV column names. The screen opens straight on the preview.
  final List<Map<String, String>>? initialRows;
  const ImportCsvScreen({super.key, this.initialRows});

  @override
  ConsumerState<ImportCsvScreen> createState() => _ImportCsvScreenState();
}

class _ImportCsvScreenState extends ConsumerState<ImportCsvScreen> {
  _Phase _phase = _Phase.upload;
  List<_CsvRow> _valid = [];
  List<_Invalid> _invalid = [];
  String? _planId;
  String _importingLabel = '';

  int _imported = 0;
  int _skipped = 0;
  List<_Invalid> _errors = [];

  @override
  void initState() {
    super.initState();
    final rows = widget.initialRows;
    if (rows != null && rows.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _validate(rows);
      });
    }
  }

  /// Full number with the gym's country code — "+91 98290-41210" and
  /// "9829041210" are the same member, but two countries' numbers that share
  /// their last 10 digits are not.
  static String _phoneKey(String phone) => whatsAppDigits(phone);

  // ── CSV parsing (handles quotes, BOM, CRLF — same as the web) ──────────────
  List<String> _parseLine(String line) {
    final out = <String>[];
    var cur = '';
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          cur += '"';
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
    out.add(cur);
    return out;
  }

  List<Map<String, String>> _parseCsv(String text) {
    final cleaned = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = cleaned
        .trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return [];
    final headers = _parseLine(lines[0])
        .map((h) => h.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_'))
        .toList();
    return lines.skip(1).map((line) {
      final values = _parseLine(line);
      final row = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        row[headers[i]] = (i < values.length ? values[i] : '').trim();
      }
      return row;
    }).toList();
  }

  void _validate(List<Map<String, String>> rows) {
    final valid = <_CsvRow>[];
    final invalid = <_Invalid>[];
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rowNum = i + 2;
      final email = r['email'] ?? '';
      final phone = r['phone'] ?? '';
      final label = email.isNotEmpty ? email : phone;
      final status = r['status'] ?? '';
      final joinedAt = r['joined_at'] ?? '';
      if ((r['first_name'] ?? '').isEmpty) {
        invalid.add(_Invalid(rowNum, label, 'Missing first_name'));
        continue;
      }
      if (email.isNotEmpty && !_emailRe.hasMatch(email)) {
        invalid.add(_Invalid(rowNum, label, 'Invalid email'));
        continue;
      }
      if (status.isNotEmpty && !_validStatuses.contains(status)) {
        invalid.add(_Invalid(rowNum, label, 'Invalid status "$status"'));
        continue;
      }
      if (joinedAt.isNotEmpty && DateTime.tryParse(joinedAt) == null) {
        invalid.add(
          _Invalid(rowNum, label, 'Invalid joined_at — use YYYY-MM-DD'),
        );
        continue;
      }
      // Same person twice in the file: same email, or same phone.
      final keys = [
        if (email.isNotEmpty) 'e:${email.toLowerCase()}',
        if (_phoneKey(phone).length >= 6) 'p:${_phoneKey(phone)}',
      ];
      if (keys.any(seen.contains)) {
        invalid.add(_Invalid(rowNum, label, 'Duplicate in file'));
        continue;
      }
      seen.addAll(keys);
      valid.add(
        _CsvRow(
          r['first_name']!,
          r['last_name'] ?? '',
          email,
          r['phone'] ?? '',
          r['notes'] ?? '',
          status.isEmpty ? 'active' : status,
          joinedAt,
        ),
      );
    }
    setState(() {
      _valid = valid;
      _invalid = invalid;
      _phase = _Phase.preview;
    });
  }

  Future<void> _pickFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
    } on MissingPluginException {
      // The file picker ships as native code; an over-the-air patch can't add
      // it. Surface a clear message instead of crashing until the next release.
      _toast(
        'CSV import needs the latest app version — please update from the ${isIOS ? 'App Store' : 'Play Store'}.',
      );
      return;
    } on PlatformException catch (e) {
      _toast('Could not open the file picker: ${e.message ?? e.code}');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!, allowMalformed: true);
    } else {
      _toast('Could not read file');
      return;
    }
    final rows = _parseCsv(text);
    if (rows.isEmpty) {
      _toast('CSV is empty or has no data rows');
      return;
    }
    _validate(rows);
  }

  void _copyTemplate() {
    final header = _csvColumns.join(',');
    const example = 'Rahul,Sharma,,9876543210,Morning batch,active,2024-01-15';
    Clipboard.setData(ClipboardData(text: '$header\n$example'));
    _toast('Template copied to clipboard');
  }

  Future<void> _import() async {
    setState(() {
      _phase = _Phase.importing;
      _importingLabel = 'Importing members…';
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      // Real (non-demo) member count before this import, so a bulk import
      // that jumps straight past 1 or 3 members doesn't skip both
      // activation milestones — checkMemberMilestones needs the crossing.
      // Own try/catch: this only supports analytics — a transient failure
      // here must never block the actual import.
      int? countBefore;
      try {
        final res = await client
            .from('members')
            .select('id')
            .eq('gym_id', gymId)
            .eq('is_demo_data', false)
            .count(CountOption.exact);
        countBefore = res.count;
      } catch (_) {
        countBefore = null;
      }

      // Skip members the gym already has: same email or same phone.
      final existing = await client
          .from('members')
          .select('email, phone')
          .eq('gym_id', gymId);
      final existingEmails = <String>{};
      final existingPhones = <String>{};
      for (final m in (existing as List)) {
        final e = (m['email'] as String?)?.toLowerCase();
        if (e != null && e.isNotEmpty) existingEmails.add(e);
        final p = _phoneKey(m['phone'] as String? ?? '');
        if (p.length >= 6) existingPhones.add(p);
      }

      final errors = <_Invalid>[];
      final toInsert = <Map<String, dynamic>>[];
      for (var i = 0; i < _valid.length; i++) {
        final r = _valid[i];
        final label = r.email.isNotEmpty ? r.email : r.phone;
        if (r.email.isNotEmpty &&
            existingEmails.contains(r.email.toLowerCase())) {
          errors.add(_Invalid(i + 2, label, 'Email already exists'));
          continue;
        }
        if (_phoneKey(r.phone).length >= 6 &&
            existingPhones.contains(_phoneKey(r.phone))) {
          errors.add(_Invalid(i + 2, label, 'Phone already exists'));
          continue;
        }
        final joined = DateTime.tryParse(r.joinedAt) ?? DateTime.now();
        toInsert.add({
          'gym_id': gymId,
          'first_name': r.firstName,
          'last_name': r.lastName.isEmpty ? null : r.lastName,
          'email': r.email.isEmpty ? null : r.email,
          // Stored with the country code, or WhatsApp reminders never reach them.
          'phone': phoneWithCountryCode(r.phone),
          'notes': r.notes.isEmpty ? null : r.notes,
          'status': r.status,
          'joined_at': joined.toUtc().toIso8601String(),
        });
      }

      var imported = 0;
      final insertedMembers = <Map<String, dynamic>>[]; // {id, joined_at}
      // Insert in batches of 100.
      for (var i = 0; i < toInsert.length; i += 100) {
        final batch = toInsert.sublist(i, (i + 100).clamp(0, toInsert.length));
        try {
          final inserted = await client
              .from('members')
              .insert(batch)
              .select('id, joined_at');
          imported += batch.length;
          insertedMembers.addAll(
            (inserted as List).cast<Map<String, dynamic>>(),
          );
        } catch (e) {
          debugPrint('[GymCRM] CSV batch insert error: $e');
          // A plan-limit rejection fails the whole batch, not just the row that
          // crossed the cap — say so, or the importer reports a bare "Insert
          // failed" against 100 rows and the owner has no idea why.
          final reason =
              planLimitMessage(e) ??
              duplicatePhoneMessage(e) ??
              'Insert failed';
          for (var j = 0; j < batch.length; j++) {
            errors.add(
              _Invalid(
                i + j + 2,
                (batch[j]['email'] ?? batch[j]['phone'] ?? '') as String,
                reason,
              ),
            );
          }
          if (planLimitMessage(e) != null) break;
        }
      }
      // Optionally assign a plan to every imported member.
      if (_planId != null && insertedMembers.isNotEmpty) {
        setState(() => _importingLabel = 'Assigning membership plans…');
        final plans = await ref.read(_importPlansProvider.future);
        final plan = plans.firstWhere(
          (p) => p['id'] == _planId,
          orElse: () => {},
        );
        final months =
            (plan['billing_interval_months'] as int?) ??
            const {
              'monthly': 1,
              'quarterly': 3,
              'biannual': 6,
              'annual': 12,
            }[plan['billing_interval']] ??
            1;
        // Plan cycle starts on each member's join date, not the import date.
        // Membership is open-ended — next_payment_date tracks renewal, not ends_at.
        final memberships = insertedMembers.map((mem) {
          final startsAt =
              DateTime.tryParse(mem['joined_at'] as String) ??
              DateTime.now().toUtc();
          return {
            'member_id': mem['id'],
            'plan_id': _planId,
            'status': 'active',
            'starts_at': startsAt.toIso8601String(),
            'ends_at': null,
          };
        }).toList();
        try {
          await client.from('memberships').insert(memberships);
          // next_payment_date isn't set anywhere else in the CSV path — derive
          // it from join date + plan duration so imported members show up in
          // upcoming-payments and reminders (both key off next_payment_date).
          for (final mem in insertedMembers) {
            final startsAt =
                DateTime.tryParse(mem['joined_at'] as String) ??
                DateTime.now().toUtc();
            final joinedStr = startsAt.toIso8601String().split('T').first;
            final nextPaymentDate = advancePaymentDate(
              joinedStr,
              months: months,
            );
            if (nextPaymentDate == null) continue;
            await client
                .from('members')
                .update({
                  'next_payment_date': nextPaymentDate,
                  'billing_interval_months': months,
                })
                .eq('id', mem['id']);
          }
        } catch (e) {
          debugPrint('[GymCRM] CSV plan assignment error: $e');
        }
      }

      if (countBefore != null) {
        unawaited(
          AppEvents.checkMemberMilestones(
            before: countBefore,
            after: countBefore + imported,
          ),
        );
      }

      setState(() {
        _imported = imported;
        _skipped = errors.length;
        _errors = errors;
        _phase = _Phase.done;
      });
    } catch (e) {
      _toast('Import failed: $e');
      setState(() => _phase = _Phase.preview);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Import members'),
        leading: IconButton(
          icon: const Icon(AppIcons.close),
          onPressed: () => Navigator.pop(context, _phase == _Phase.done),
        ),
      ),
      body: Column(
        children: [
          _StepIndicator(
            step: switch (_phase) {
              _Phase.upload => 0,
              _Phase.preview => 1,
              _Phase.importing => 1,
              _Phase.done => 2,
            },
          ),
          Expanded(
            child: switch (_phase) {
              _Phase.upload => _buildUpload(),
              _Phase.preview => _buildPreview(),
              _Phase.importing => _buildImporting(),
              _Phase.done => _buildDone(),
            },
          ),
        ],
      ),
    );
  }

  // ── Upload ─────────────────────────────────────────────────────────────────
  Widget _buildUpload() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.border,
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.activeBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(AppIcons.uploadFile, color: AppTheme.ink),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Choose a CSV file',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to browse your device',
                    style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Not sure about the format?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.ink,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _copyTemplate,
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(AppIcons.copy, size: 14),
                      label: const Text('Copy template'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'CSV COLUMNS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _csvColumns.map((c) {
                    final req = _requiredColumns.contains(c);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            req ? 'REQ' : 'OPT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: req
                                  ? AppTheme.statusDanger
                                  : AppTheme.inkHint,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            c,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview ────────────────────────────────────────────────────────────────
  Widget _buildPreview() {
    final plans = ref.watch(_importPlansProvider);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statBox(
                      '${_valid.length}',
                      'Valid rows',
                      AppTheme.statusActive,
                      AppTheme.statusActiveBg,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statBox(
                      '${_invalid.length}',
                      'Errors',
                      _invalid.isEmpty
                          ? AppTheme.inkSoft
                          : AppTheme.statusDanger,
                      _invalid.isEmpty
                          ? AppTheme.surface2
                          : AppTheme.statusDangerBg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_valid.isNotEmpty) ...[
                Text(
                  'Preview — first ${_valid.length < 5 ? _valid.length : 5} of ${_valid.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                ..._valid
                    .take(5)
                    .map(
                      (r) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: AppTheme.cardDecoration(),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r.firstName} ${r.lastName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  Text(
                                    r.email.isNotEmpty ? r.email : r.phone,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              r.status,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_invalid.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'ROWS THAT WILL BE SKIPPED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.statusDanger,
                  ),
                ),
                const SizedBox(height: 8),
                ..._invalid.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Row ${e.row}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppTheme.inkHint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${e.email.isNotEmpty ? '${e.email} — ' : ''}${e.reason}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.statusDanger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_valid.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'ASSIGN A PLAN (OPTIONAL)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                plans.maybeWhen(
                  data: (list) => list.isEmpty
                      ? const Text(
                          'No active plans. Create one in Billing first.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkSoft,
                          ),
                        )
                      : DropdownButtonFormField<String?>(
                          value: _planId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Membership plan',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No plan'),
                            ),
                            ...list.map(
                              (p) => DropdownMenuItem<String?>(
                                value: p['id'] as String,
                                child: Text(
                                  _planLabel(p),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _planId = v),
                        ),
                  orElse: () => const LinearProgressIndicator(),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _phase = _Phase.upload),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                  ),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _valid.isEmpty ? null : _import,
                    child: Text(
                      'Import ${_valid.length} member${_valid.length == 1 ? '' : 's'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statBox(String value, String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImporting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _importingLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Please wait…',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _buildDone() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.statusActiveBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      AppIcons.checkCircleActive,
                      color: AppTheme.statusActive,
                      size: 32,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_imported imported',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const Text(
                          'Members added to your gym',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.statusActive,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_skipped > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '$_skipped row${_skipped == 1 ? '' : 's'} skipped',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 8),
                ..._errors.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Row ${e.row}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppTheme.inkHint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${e.email.isNotEmpty ? '${e.email} — ' : ''}${e.reason}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step indicator (1 Upload — 2 Map — 3 Done) ────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int step; // 0-based current step
  const _StepIndicator({required this.step});

  static const _labels = ['Upload', 'Map', 'Done'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: i == step
                    ? AppTheme.accent
                    : i < step
                    ? AppTheme.statusActiveBg
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                i < step
                    ? '${i + 1} ${_labels[i]} ✓'
                    : '${i + 1} ${_labels[i]}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: i == step
                      ? Colors.white
                      : i < step
                      ? AppTheme.statusActive
                      : AppTheme.inkHint,
                ),
              ),
            ),
            if (i < _labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i < step ? AppTheme.accent : AppTheme.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
