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

  /// Milestones, in successful-actions. Two shots: one once they're convinced
  /// it works, one once they're a real user.
  static const _milestones = [10, 100];

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

    if (!await InAppReview.instance.isAvailable()) return;
    await prefs.setInt(_askedKey, count);
    await InAppReview.instance.requestReview();
  }

  /// Whether `recordSuccess` would trigger the card at this count. Exposed for
  /// the self-check below.
  static bool isMilestone(int count) => _milestones.contains(count);
}
