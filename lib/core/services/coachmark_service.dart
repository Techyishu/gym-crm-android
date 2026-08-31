import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-time guided-tour tooltips ("coach marks"), controlled from Supabase.
/// A key shows once per user, then is remembered as seen. Admins can turn a
/// coach mark off (`coachmark_config.enabled = false`) or make it reappear
/// for everyone by deleting rows from `user_coachmarks_seen` — no app update needed.
class CoachmarkService {
  final Set<String> _enabledKeys;
  final Set<String> _seenKeys;

  CoachmarkService({
    required Set<String> enabledKeys,
    required Set<String> seenKeys,
  }) : _enabledKeys = enabledKeys,
       _seenKeys = seenKeys;

  bool shouldShow(String key) =>
      _enabledKeys.contains(key) && !_seenKeys.contains(key);

  Future<void> markSeen(String key) async {
    if (_seenKeys.contains(key)) return;
    _seenKeys.add(key);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client.from('user_coachmarks_seen').upsert({
      'user_id': userId,
      'coachmark_key': key,
    });
  }
}

final coachmarkServiceProvider = FutureProvider<CoachmarkService>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) {
    return CoachmarkService(enabledKeys: {}, seenKeys: {});
  }

  final results = await Future.wait([
    client.from('coachmark_config').select('key').eq('enabled', true),
    client
        .from('user_coachmarks_seen')
        .select('coachmark_key')
        .eq('user_id', userId),
  ]);

  final enabledKeys = (results[0] as List)
      .map((row) => row['key'] as String)
      .toSet();
  final seenKeys = (results[1] as List)
      .map((row) => row['coachmark_key'] as String)
      .toSet();

  return CoachmarkService(enabledKeys: enabledKeys, seenKeys: seenKeys);
});
