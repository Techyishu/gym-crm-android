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
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
    if (await _adsConsented()) {
      await _fb.logEvent(name: name, parameters: params);
    }
  }

  /// Account created. Meta's standard registration event — the first signal
  /// worth bidding on while purchase volume is still too thin to optimise.
  static Future<void> signUpCompleted() async {
    await _log('sign_up_completed');
    if (defaultTargetPlatform != TargetPlatform.android) return;
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
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await FirebaseAnalytics.instance.logPurchase(
      value: amount,
      currency: currency,
      parameters: plan == null ? null : {'plan': plan},
    );
    if (!await _adsConsented()) return;
    await _fb.logPurchase(amount: amount, currency: currency);
  }
}
