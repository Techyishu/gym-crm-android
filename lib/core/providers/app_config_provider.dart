import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// public.app_config as {key: value} — settings changed in the database
/// without an app release (paywall default term, support WhatsApp number, …).
/// Empty on any failure, so every reader keeps its built-in default.
final appConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from('app_config')
        .select('key, value');
    return {for (final r in rows) r['key'] as String: r['value']};
  } catch (_) {
    return const {};
  }
});
