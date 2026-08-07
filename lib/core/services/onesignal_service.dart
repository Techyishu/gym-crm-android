import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../router.dart';

const _kOneSignalAppId = '21ed9dad-585e-4219-b9ca-29ba2fd357e8';

class OneSignalService {
  OneSignalService._();

  static Future<void> initialize() async {
    // ponytail: web needs the OneSignal Web SDK script + service worker in
    // web/index.html, which isn't set up yet — skip rather than risk the
    // uncaught init call blocking app boot. Add web push when that's wired up.
    if (kIsWeb) return;
    OneSignal.Debug.setLogLevel(
      kReleaseMode ? OSLogLevel.none : OSLogLevel.verbose,
    );
    OneSignal.initialize(_kOneSignalAppId);
    await OneSignal.Notifications.requestPermission(true);
    _registerInAppMessageClickListener();
  }

  // Handles the "url" set on an In-App Message button/image in the OneSignal
  // dashboard: app-relative paths (e.g. "/staff/billing") navigate in-app,
  // everything else opens externally.
  static void _registerInAppMessageClickListener() {
    OneSignal.InAppMessages.addClickListener((event) {
      final url = event.result.url;
      if (url == null || url.isEmpty) return;

      final context = rootNavigatorKey.currentContext;
      if (url.startsWith('/') && context != null) {
        GoRouter.of(context).push(url);
      } else {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    });
  }

  /// Call after Supabase sign-in so OneSignal ties this device to the user.
  static Future<void> loginUser(String userId) async {
    try {
      await OneSignal.login(userId);
    } catch (e, s) {
      debugPrint('[OneSignal] loginUser error: $e\n$s');
    }
  }

  /// Call on sign-out so OneSignal detaches this device from the user.
  static Future<void> logoutUser() async {
    try {
      await OneSignal.logout();
    } catch (e, s) {
      debugPrint('[OneSignal] logoutUser error: $e\n$s');
    }
  }

  /// Keeps OneSignal tags in sync with the staff member's gym so dashboard
  /// In-App Messages can target by trigger (e.g. "plan_expires_in_days <= 3").
  /// Cheap + idempotent — safe to call on every staffProfileProvider refresh.
  static Future<void> syncGymTags(Map<String, dynamic> gym) async {
    try {
      final tags = <String, String>{
        'plan': gym['plan'] as String? ?? 'starter',
      };

      final createdAt = DateTime.tryParse(gym['created_at'] as String? ?? '');
      if (createdAt != null) {
        final ownerSinceDays = DateTime.now().toUtc().difference(createdAt.toUtc()).inDays;
        tags['owner_since_days'] = ownerSinceDays.toString();
      }

      // Whichever expiry is active — trial for gyms still trialing, plan
      // renewal date once subscribed.
      final expiryStr = gym['plan_expires_at'] as String? ?? gym['trial_ends_at'] as String?;
      final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
      if (expiry != null) {
        final daysLeft = expiry.toUtc().difference(DateTime.now().toUtc()).inDays;
        tags['plan_expires_in_days'] = daysLeft.toString();
      }

      await OneSignal.User.addTags(tags);
    } catch (e, s) {
      debugPrint('[OneSignal] syncGymTags error: $e\n$s');
    }
  }
}
