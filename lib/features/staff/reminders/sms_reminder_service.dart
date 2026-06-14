import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _smsChannel = MethodChannel('com.gymcrm/sms');

const kSmsEnabled = 'sms_reminders_enabled';
const kSmsDaysBefore = 'sms_reminders_days_before';
const kSmsTemplate = 'sms_reminders_template';
const kSmsDefaultTemplate =
    'Hi {name}, your gym membership expires in {days} days. Please renew to continue enjoying our services.';

const kWelcomeEnabled = 'sms_welcome_enabled';
const kWelcomeTemplate = 'sms_welcome_template';
const kWelcomeDefaultTemplate =
    'Welcome to our gym, {name}! We\'re thrilled to have you. See you on the floor!';

class SmsReminderService {
  // Send a welcome SMS to a newly added member (foreground, no session needed).
  static Future<void> sendWelcomeSms({
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(kWelcomeEnabled) ?? false)) return;
    final template = prefs.getString(kWelcomeTemplate) ?? kWelcomeDefaultTemplate;
    final msg = template.replaceAll('{name}', name);
    try {
      await _smsChannel.invokeMethod('sendSms', {'to': phone, 'message': msg});
    } catch (e) {
      debugPrint('[GymCRM] Welcome SMS send error to $phone: $e');
    }
  }

  // Schedule or cancel the native Kotlin background worker.
  static Future<void> setNativeRemindersEnabled(bool enabled) async {
    try {
      await _smsChannel.invokeMethod(
        enabled ? 'startNativeReminders' : 'stopNativeReminders',
      );
    } catch (e) {
      debugPrint('[GymCRM] setNativeRemindersEnabled error: $e');
    }
  }

  // Manual trigger from UI — uses foreground MethodChannel (always works).
  static Future<int> sendManualReminders() async {
    final session = await _resolveSession();
    if (session == null) return 0;

    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getInt(kSmsDaysBefore) ?? 3;
    final template = prefs.getString(kSmsTemplate) ?? kSmsDefaultTemplate;
    return _sendReminders(userId: session.user.id, daysBefore: days, template: template);
  }

  // Try currentSession first; fall back to getSession() which forces a refresh
  // from secure storage (handles the case where the token has been rotated).
  static Future<Session?> _resolveSession() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) return client.auth.currentSession;
    try {
      final res = await client.auth.refreshSession();
      return res.session;
    } catch (e) {
      debugPrint('[GymCRM] Session refresh error: $e');
      return null;
    }
  }

  static Future<int> _sendReminders({
    required String userId,
    required int daysBefore,
    required String template,
  }) async {
    final members = await _fetchExpiringMembers(userId: userId, daysBefore: daysBefore);
    int sent = 0;

    for (final m in members) {
      final phone = (m['phone'] as String?)?.trim();
      if (phone == null || phone.isEmpty) continue;

      final name = m['first_name'] as String? ?? 'Member';
      final msg = template
          .replaceAll('{name}', name)
          .replaceAll('{days}', daysBefore.toString());

      try {
        await _smsChannel.invokeMethod('sendSms', {'to': phone, 'message': msg});
        sent++;
      } catch (e) {
        debugPrint('[GymCRM] SMS reminder send error to $phone: $e');
      }
    }

    return sent;
  }

  static Future<List<Map<String, dynamic>>> _fetchExpiringMembers({
    required String userId,
    required int daysBefore,
  }) async {
    final client = Supabase.instance.client;

    final profile = await client
        .from('profiles')
        .select('gym_id')
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) return [];
    final gymId = profile['gym_id'] as String;

    // Members whose next_payment_date falls exactly on (today + daysBefore).
    final target = DateTime.now().add(Duration(days: daysBefore));
    final startStr = _dateStr(target);
    final endStr = _dateStr(target.add(const Duration(days: 1)));

    try {
      final result = await client
          .from('members')
          .select('id, first_name, last_name, phone')
          .eq('gym_id', gymId)
          .eq('status', 'active')
          .gte('next_payment_date', startStr)
          .lt('next_payment_date', endStr)
          .not('phone', 'is', null);
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('[GymCRM] Fetch expiring members error: $e');
      return [];
    }
  }

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
