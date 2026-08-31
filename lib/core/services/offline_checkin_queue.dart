import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'activity_log_service.dart';
import 'app_events.dart';
import 'data_refresh.dart';

/// Stores QR check-ins that failed due to no connectivity.
/// Uses shared_preferences (already a dep) and dart:io for connectivity tests.
/// All methods are static; no initialisation required.
class OfflineCheckInQueue {
  static const _queueKey = 'offline_checkin_queue_v1';
  static const _gymIdKey = 'cached_staff_gym_id';

  static final _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  // ── Connectivity ─────────────────────────────────────────────────────────

  static Future<bool> isOnline() async {
    // dart:io sockets aren't available on web; the browser wouldn't have
    // loaded the app at all if it had no network, so assume online.
    if (kIsWeb) return true;
    try {
      final results = await InternetAddress.lookup(
        '8.8.8.8',
      ).timeout(const Duration(seconds: 3));
      return results.isNotEmpty && results.first.rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('[GymCRM] isOnline check error: $e');
      return false;
    }
  }

  // ── Gym-id cache ──────────────────────────────────────────────────────────

  /// Called after a successful online check-in so we always have a cached id.
  static Future<void> cacheGymId(String gymId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gymIdKey, gymId);
  }

  static Future<String?> cachedGymId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gymIdKey);
  }

  // ── Queue ─────────────────────────────────────────────────────────────────

  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }

  static Future<void> enqueue({
    required String memberId,
    required String gymId,
    required String staffId,
  }) async {
    // Reject obviously invalid UUIDs before persisting — the server RPC will
    // re-validate, but this avoids polluting the queue with garbage data.
    if (!_uuidRe.hasMatch(memberId) ||
        !_uuidRe.hasMatch(gymId) ||
        !_uuidRe.hasMatch(staffId)) {
      throw ArgumentError('enqueue: invalid UUID in memberId/gymId/staffId');
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    raw.add(
      jsonEncode({
        'member_id': memberId,
        'gym_id': gymId,
        'staff_id': staffId,
        'method': 'qr',
        'queued_at': DateTime.now().toIso8601String(),
      }),
    );
    await prefs.setStringList(_queueKey, raw);
  }

  /// Tries to insert all queued items via the server-side RPC which re-validates
  /// gym membership before inserting. Returns the count that succeeded.
  /// Failed items (still no network or DB error) stay in the queue.
  static Future<int> flush() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queueKey) ?? [];
    if (raw.isEmpty) return 0;

    final client = Supabase.instance.client;
    int synced = 0;
    final remaining = <String>[];

    for (final item in raw) {
      try {
        final data = jsonDecode(item) as Map<String, dynamic>;

        // Server RPC validates that the member belongs to the gym and that
        // the caller is staff of that gym before inserting. See:
        //   supabase/migrations/20260614_security_rpcs.sql → insert_checkin_secure
        await client.rpc(
          'insert_checkin_secure',
          params: {
            'p_member_id': data['member_id'],
            'p_gym_id': data['gym_id'],
            'p_method': data['method'] ?? 'qr',
            'p_checked_in_at': data['queued_at'],
          },
        );
        synced++;
        ActivityLogService.logActivity(
          gymId: data['gym_id'] as String,
          action: 'check_in',
          metadata: {
            'member_id': data['member_id'],
            'via': 'android_offline_sync',
          },
        );
        unawaited(AppEvents.checkinCompleted());
        notifyGymDataChanged();
      } catch (e) {
        debugPrint('[GymCRM] Flush checkin error: $e');
        remaining.add(item);
      }
    }

    await prefs.setStringList(_queueKey, remaining);
    return synced;
  }
}
