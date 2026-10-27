import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/legal/consent_screen.dart' show kConsentAds;

/// The handful of events ad platforms need to optimise for buyers instead of
/// installs. Every call fans out to Firebase (Google Ads) and Meta.
///
/// Firebase gates itself — `setAnalyticsCollectionEnabled(false)` drops
/// everything at the SDK. Meta does **not**: its
/// `setAutoLogAppEventsEnabled(false)` only suppresses the SDK's own automatic
/// events, and an explicit `logEvent` still goes out. So every Meta call here
/// is gated on the stored ads consent first.
class AppEvents {
  static final _fb = FacebookAppEvents();

  /// Meta runs on both stores — iOS ad campaigns need conversion data too, or
  /// Aggregated Event Measurement can't be configured. Firebase stays
  /// Android-only: `firebase_options.dart` has no iOS entry, so main.dart
  /// never initialises it there and touching the instance would throw.
  static bool get _meta =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _firebase =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _adsConsented() async =>
      (await SharedPreferences.getInstance()).getBool(kConsentAds) ?? false;

  /// App-open ping so Meta can count the install on first open, before any
  /// sign-up or consent. Only needed without ads consent — with consent the
  /// SDK's auto-logging already sends it. Must run after applyStoredConsent(),
  /// which sets Limited Data Use first, so Meta restricts processing. Carries
  /// no user data, params or user ID — just the standard activate-app event.
  static Future<void> logAppOpen() async {
    if (!_meta || await _adsConsented()) return;
    await _fb.logEvent(name: 'fb_mobile_activate_app');
  }

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (_firebase) {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    }
    if (_meta && await _adsConsented()) {
      await _fb.logEvent(name: name, parameters: params);
    }
  }

  /// Account created. Meta's standard registration event — the first signal
  /// worth bidding on while purchase volume is still too thin to optimise.
  static Future<void> signUpCompleted() async {
    await _log('sign_up_completed');
    if (!_meta) return;
    if (!await _adsConsented()) return;
    await _fb.logCompletedRegistration(registrationMethod: 'email_otp');
  }

  /// `setup_gym` succeeded. The real activation point: the account now has a
  /// gym behind it rather than a bare auth row.
  static Future<void> gymSetupCompleted({String? memberCount}) => _log(
    'gym_setup_completed',
    memberCount == null ? null : {'member_count': memberCount},
  );

  /// Setup finished by a gym that says it has 30+ members. The conversion to
  /// bid Google Ads on: it tells the campaign which installs are real gyms,
  /// not students, members or trainers. Fired once, right after setup.
  static Future<void> qualifiedGym(String memberCount) =>
      _log('qualified_gym', {'member_count': memberCount});

  /// First member added to a gym. Strongest early predictor of a paying gym.
  static Future<void> firstMemberAdded() => _log('first_member_added');

  /// Subscription paid — Meta only. Firebase/Google gets `purchase` from the
  /// Dodo webhook (GA4 Measurement Protocol, gyms.firebase_app_instance_id),
  /// which also covers renewals and phones that drop the checkout deep link;
  /// logging it here too would count every first payment twice.
  static Future<void> purchase({
    required double amount,
    String currency = 'INR',
    String? plan,
  }) async {
    if (!_meta) return;
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

  /// A paywall plan card showed a live offer (once per paywall visit).
  static Future<void> offerViewed(String code, String term) =>
      _log('offer_viewed', {'offer_code': code, 'term': term});

  /// The Home "WhatsApp reminders paused" banner was shown.
  static Future<void> whatsappPaused() => _log('whatsapp_paused');

  /// The database-driven offer popup (public.promotions) was shown / tapped.
  static Future<void> promotionViewed(String id) =>
      _log('promotion_viewed', {'promotion_id': id});
  static Future<void> promotionClicked(String id) =>
      _log('promotion_clicked', {'promotion_id': id});

  /// Segments for Firebase / Google Ads audiences: billing state, locked price
  /// plan, Home design and gym size. Android-only, like every Firebase call.
  static Future<void> setGymProperties({
    required String billingState,
    String? pricePlan,
    required bool newHome,
    required int members,
  }) async {
    if (!_firebase) return;
    final a = FirebaseAnalytics.instance;
    final bucket = members == 0
        ? '0'
        : members < 3
        ? '1-2'
        : members < 20
        ? '3-19'
        : '20+';
    await a.setUserProperty(name: 'billing_state', value: billingState);
    await a.setUserProperty(name: 'price_plan', value: pricePlan ?? 'none');
    await a.setUserProperty(
      name: 'home_design',
      value: newHome ? 'new' : 'classic',
    );
    await a.setUserProperty(name: 'member_bucket', value: bucket);
  }

  /// The device's Firebase app_instance_id, or null off Android / before
  /// analytics consent. The Dodo webhook needs it to send `purchase`.
  static Future<String?> appInstanceId() async {
    if (!_firebase) return null;
    try {
      return await FirebaseAnalytics.instance.appInstanceId;
    } catch (_) {
      return null;
    }
  }

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
