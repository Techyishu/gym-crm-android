import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play in-app review card, shown after the user has felt the app work.
///
/// Play policy forbids asking "do you like the app?" before showing the card,
/// so there is no custom dialog here — we only pick the moment and let the
/// native sheet do the rest. Play also quota-limits the card (roughly once a
/// few months per user) and never tells us whether it appeared or what was
/// rated, so `requestReview()` is best-effort by design.
class ReviewPrompt {
  static const _countKey = 'review_success_count';
  static const _askedKey = 'review_asked_at_count';
  static const _lastAskedKey = 'review_last_asked_ms';

  /// Milestones, in successful-actions. Two shots: one once they're convinced
  /// it works, one once they're a real user.
  static const _milestones = [10, 100];

  /// Shortest gap between asks. Play's own quota is the real limit (roughly
  /// once every few months, silently enforced) — this only stops us burning
  /// calls the OS would throw away anyway, and keeps a returning owner from
  /// being asked twice in a week.
  static const _minGap = Duration(days: 30);

  /// Enough real usage to have an opinion worth leaving.
  ///
  /// Set to 1: one added member or one payment collected is treated as enough.
  /// Raise it if early prompts start pulling in one-star ratings from people
  /// who had not yet seen the app do anything for them.
  static const _minSuccessesForLaunchAsk = 1;

  /// Called on app open. Asks only when they have used the app for real and
  /// we have not asked recently.
  ///
  /// Deliberately not an unconditional ask on every launch: Play ignores
  /// repeat calls within its quota without reporting anything, so a per-launch
  /// call would look like it was working while changing nothing — and it
  /// spends the one shot we get on a cold open rather than on a good moment.
  static Future<void> maybeAskOnLaunch() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getInt(_countKey) ?? 0) < _minSuccessesForLaunchAsk) return;

    final last = prefs.getInt(_lastAskedKey);
    if (last != null &&
        DateTime.now().millisecondsSinceEpoch - last < _minGap.inMilliseconds) {
      return;
    }
    await _ask(prefs);
  }

  static Future<void> _ask(SharedPreferences prefs) async {
    if (!await InAppReview.instance.isAvailable()) return;
    await prefs.setInt(_lastAskedKey, DateTime.now().millisecondsSinceEpoch);
    await InAppReview.instance.requestReview();
  }

  /// Call after any action that proves the app works (a check-in, a payment
  /// recorded). Cheap and safe to call on every success — it only reaches the
  /// Play API on a milestone.
  static Future<void> recordSuccess() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_countKey) ?? 0) + 1;
    await prefs.setInt(_countKey, count);

    if (!_milestones.contains(count)) return;
    if ((prefs.getInt(_askedKey) ?? 0) == count) return;

    await prefs.setInt(_askedKey, count);
    await _ask(prefs);
  }

  /// Whether `recordSuccess` would trigger the card at this count. Exposed for
  /// the self-check below.
  static bool isMilestone(int count) => _milestones.contains(count);
}
