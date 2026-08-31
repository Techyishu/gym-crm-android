import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CsvExportPreview {
  final String exportId;
  final String type;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final bool piiIncluded;
  final Map<String, dynamic> filters;

  const CsvExportPreview({
    required this.exportId,
    required this.type,
    required this.columns,
    required this.rows,
    required this.piiIncluded,
    required this.filters,
  });

  factory CsvExportPreview.fromJson(Map<String, dynamic> json) =>
      CsvExportPreview(
        exportId: json['export_id'] as String,
        type: json['type'] as String,
        columns: (json['columns'] as List).cast<String>(),
        rows: (json['rows'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
        piiIncluded: json['pii_included'] == true,
        filters: Map<String, dynamic>.from(json['filters'] as Map? ?? const {}),
      );
}

class CsvExportService {
  final SupabaseClient _client;

  CsvExportService(this._client);

  Future<CsvExportPreview> prepare({
    required String gymId,
    required String type,
    required DateTime from,
    required DateTime to,
    Map<String, dynamic> filters = const {},
  }) async {
    final raw = await _client.rpc(
      'prepare_data_export',
      params: {
        'p_gym_id': gymId,
        'p_export_type': type,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_filters': filters,
      },
    );
    return CsvExportPreview.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Hands the CSV to the system share sheet. Returns false when the user
  /// backed out of it \u2014 nothing left the device, so the export must not be
  /// stamped complete.
  ///
  /// The completion RPC used to run *before* the sheet opened, which recorded
  /// a finished export (PII and all) every time someone opened the sheet and
  /// changed their mind.
  Future<bool> shareAndComplete(CsvExportPreview preview) async {
    final result = await Share.shareXFiles([
      XFile.fromData(
        _bytes(preview),
        mimeType: 'text/csv',
        name: _fileName(preview),
      ),
    ], subject: 'GymCRM ${preview.type} export');

    // `unavailable` means the platform shared but couldn't name the target \u2014
    // treat only an explicit dismissal as "did not export".
    if (result.status == ShareResultStatus.dismissed) return false;

    await _complete(preview);
    return true;
  }

  /// Writes the CSV straight to wherever the user picks in the system save
  /// dialog — the share sheet can't do this, and "Export" is expected to leave
  /// a file behind. Returns false when the dialog is dismissed.
  Future<bool> saveAndComplete(CsvExportPreview preview) async {
    final bytes = _bytes(preview);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save export',
      fileName: _fileName(preview),
      bytes: bytes,
    );
    if (path == null) return false;
    // Only mobile writes the bytes for us; desktop returns a path to fill.
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes);
    }
    await _complete(preview);
    return true;
  }

  Future<void> _complete(CsvExportPreview preview) => _client.rpc(
    'complete_data_export',
    params: {'p_export_id': preview.exportId},
  );

  Uint8List _bytes(CsvExportPreview preview) => Uint8List.fromList(
    // Leading BOM so Excel opens the file as UTF-8.
    utf8.encode('﻿${_encode(preview.columns, preview.rows)}'),
  );

  String _fileName(CsvExportPreview preview) =>
      'gymcrm_${preview.type}_${DateTime.now().toIso8601String().split('T').first}.csv';

  static String _encode(List<String> columns, List<Map<String, dynamic>> rows) {
    final lines = <String>[
      columns.map(_cell).join(','),
      ...rows.map(
        (row) => columns.map((column) => _cell(row[column])).join(','),
      ),
    ];
    return lines.join('\r\n');
  }

  static String _cell(Object? value) {
    final text = switch (value) {
      null => '',
      Map() || List() => jsonEncode(value),
      _ => '$value',
    };
    return '"${text.replaceAll('"', '""')}"';
  }

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
