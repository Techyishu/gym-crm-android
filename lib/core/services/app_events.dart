import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/legal/consent_screen.dart' show kConsentAds;

/// The handful of events ad platforms need to optimise for buyers instead of
/// installs. Every call fans out to Firebase (Google Ads) and Meta.
///
/// Android-only. Firebase gates itself — `setAnalyticsCollectionEnabled(false)`
/// drops everything at the SDK. Meta does **not**: its
/// `setAutoLogAppEventsEnabled(false)` only suppresses the SDK's own automatic
/// events, and an explicit `logEvent` still goes out. So every Meta call here
/// is gated on the stored ads consent first.
class AppEvents {
  static final _fb = FacebookAppEvents();

  static Future<bool> _adsConsented() async =>
      (await SharedPreferences.getInstance()).getBool(kConsentAds) ?? false;

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    if (await _adsConsented()) {
      await _fb.logEvent(name: name, parameters: params);
    }
  }

  /// Account created. Meta's standard registration event — the first signal
  /// worth bidding on while purchase volume is still too thin to optimise.
  static Future<void> signUpCompleted() async {
    await _log('sign_up_completed');
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!await _adsConsented()) return;
    await _fb.logCompletedRegistration(registrationMethod: 'email_otp');
  }

  /// `setup_gym` succeeded. The real activation point: the account now has a
  /// gym behind it rather than a bare auth row.
  static Future<void> gymSetupCompleted() => _log('gym_setup_completed');

  /// First member added to a gym. Strongest early predictor of a paying gym.
  static Future<void> firstMemberAdded() => _log('first_member_added');

  /// Subscription paid. The event both platforms should ultimately bid on.
  static Future<void> purchase({
    required double amount,
    String currency = 'INR',
    String? plan,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await FirebaseAnalytics.instance.logPurchase(
      value: amount,
      currency: currency,
      parameters: plan == null ? null : {'plan': plan},
    );
    if (!await _adsConsented()) return;
    await _fb.logPurchase(amount: amount, currency: currency);
  }

  /// First real membership plan created. Without one, "Add member" dead-ends
  /// on "No plans yet" — this measures how many gyms clear that blocker.
  static Future<void> planCreated() => _log('plan_created');

  /// A payment was recorded against an invoice — Billing's Collect flow,
  /// Upcoming Payments, the dashboard's "due today" list, or the add-member
  /// "paid today" shortcut.
  static Future<void> paymentRecorded() => _log('payment_recorded');

  /// Third real (non-demo) member added to a gym. The funnel audit found
  /// paying gyms sit at this depth or above; not-yet-paying gyms almost never
  /// do. Track as a product-health/retention signal for now — under the
  /// current 1-day trial this mostly fires *after* purchase, so it is not a
  /// valid ad-bidding target until the trial is long enough for activation to
  /// genuinely precede payment (re-verify via `plan_started_at` before ever
  /// promoting it to one).
  static Future<void> threeMembersAdded() => _log('three_members_added');

  /// Fires first_member_added / three_members_added exactly once each,
  /// derived from whether this batch of adds crossed the 1 or 3 threshold.
  /// Shared by the single add-member sheet and CSV bulk import so a 5-row
  /// import doesn't silently jump past both milestones without firing them.
  static Future<void> checkMemberMilestones({
    required int before,
    required int after,
  }) async {
    if (before < 1 && after >= 1) await firstMemberAdded();
    if (before < 3 && after >= 3) await threeMembersAdded();
  }

  /// Owner turned WhatsApp reminders on — the most differentiated feature in
  /// the app, and per the funnel audit the one ~82% of gyms never discover.
  static Future<void> whatsappRemindersEnabled() =>
      _log('whatsapp_reminders_enabled');

  /// A member checked in. The clearest day-to-day "this gym is actually
  /// running on GymCRM" signal, distinct from setup-time activation events.
  static Future<void> checkinCompleted() => _log('checkin_completed');

  /// Paywall shown because access was blocked (trial or plan lapsed) — not
  /// logged when an already-subscribed owner browses Settings > Subscription
  /// voluntarily, which renders the same body but isn't a sales moment.
  static Future<void> paywallViewed() => _log('paywall_viewed');

  /// Owner tapped Subscribe and checkout began. On Android this is also the
  /// moment the app hands off to an external Custom Tab for Dodo checkout —
  /// a step the funnel audit flagged as an unmeasured drop-off point.
  /// Comparing this against `purchase` volume is what measures it.
  static Future<void> checkoutStarted() => _log('checkout_started');

  /// Trial lapsed with no plan behind it. Best-effort only — fired the first
  /// time the paywall renders in that state, so a gym that never reopens the
  /// app after its trial ends will never fire this. Not a substitute for a
  /// server-side check against `trial_ends_at`.
  static Future<void> trialExpired() => _log('trial_expired');

  /// Genuinely server-side events — the authoritative cancel/renew signal is
  /// the Dodo/RevenueCat webhook hitting the Next.js backend, not this
  /// client. Defined here so the event vocabulary matches the spec; nothing
  /// in the Flutter app calls these. Guessing them from client-observed
  /// state would double-count (every fresh purchase would also look like a
  /// "renewal" on the next app open) and miss cancellations that happen
  /// while the app isn't running — wire these from the webhook handler
  /// instead.
  static Future<void> subscriptionCancelled() => _log('subscription_cancelled');
  static Future<void> subscriptionRenewed() => _log('subscription_renewed');
}
