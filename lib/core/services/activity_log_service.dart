import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reports events to the platform admin dashboard's activity timeline and
/// error log (`activity_events` / `error_logs` tables). Fire-and-forget —
/// never throws, since this must not affect the app's own behavior.
class ActivityLogService {
  static Future<void> logActivity({
    required String gymId,
    required String action,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('activity_events').insert({
        'gym_id': gymId,
        'user_id': client.auth.currentUser?.id,
        'action': action,
        'metadata': metadata,
      });
    } catch (e) {
      debugPrint('[ActivityLogService] failed to log activity: $e');
    }
  }

  static Future<void> logError({
    required String message,
    String? stackTrace,
    String? page,
    String? gymId,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.from('error_logs').insert({
        'gym_id': gymId,
        'user_id': client.auth.currentUser?.id,
        'source': 'android',
        'message': message.length > 2000 ? message.substring(0, 2000) : message,
        'stack_trace': stackTrace != null && stackTrace.length > 8000 ? stackTrace.substring(0, 8000) : stackTrace,
        'page': page,
      });
    } catch (e) {
      debugPrint('[ActivityLogService] failed to log error: $e');
    }
  }
}
