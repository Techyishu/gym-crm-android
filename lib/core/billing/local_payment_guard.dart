import 'package:shared_preferences/shared_preferences.dart';

/// Local (no backend call) check for "did we already collect a payment for
/// this member today". Staff on a slow connection sometimes don't see the
/// list refresh after Collect Payment, assume it failed, and tap again —
/// this catches that on-device before any second insert happens.
///
/// Keyed by device + day, not synced across staff/devices — a lightweight
/// speed bump, not a source of truth. The real duplicate-payment case still
/// needs checking, this only stops the common accidental-retry path fast.
class LocalPaymentGuard {
  static String _key(String memberId) => 'paid_today_$memberId';

  static Future<({double amount, DateTime at})?> check(String memberId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(memberId));
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    final amount = double.tryParse(parts[0]);
    final at = DateTime.tryParse(parts[1]);
    if (amount == null || at == null) return null;
    final now = DateTime.now();
    if (at.year != now.year || at.month != now.month || at.day != now.day) {
      return null;
    }
    return (amount: amount, at: at);
  }

  static Future<void> record(String memberId, double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(memberId),
      '$amount|${DateTime.now().toIso8601String()}',
    );
  }
}
