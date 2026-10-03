import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../router.dart';

class PushService {
  PushService._();

  /// Fires when a push arrives while the app is open (FCM doesn't show those
  /// on Android, so the UI just refreshes the in-app bell).
  static Stream<RemoteMessage> get onForeground => FirebaseMessaging.onMessage;

  static Future<void> initialize() async {
    // ponytail: web push needs a service worker + VAPID key, not set up —
    // skip rather than risk blocking boot. Add when web push is wired up.
    if (kIsWeb) return;
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission();
    await fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    fcm.onTokenRefresh.listen(_saveToken);
  }

  /// App opened from a terminated state by tapping a push. Call after the
  /// first frame so the router has a context to navigate with.
  static Future<void> handleInitialMessage() async {
    if (kIsWeb) return;
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) _open(msg);
    } catch (e, s) {
      debugPrint('[Push] initial message error: $e\n$s');
    }
  }

  // Deep link travels in the custom "deep_link" data field (set by the edge
  // functions via _shared/fcm.ts).
  static void _open(RemoteMessage msg) {
    final url = msg.data['deep_link'] as String?;
    if (url == null || url.isEmpty) return;

    final context = rootNavigatorKey.currentContext;
    if (url.startsWith('/') && context != null) {
      // go(), not push(): some deep-link targets (e.g. /staff/members,
      // /staff/billing) are StatefulShellRoute branches. Pushing them from
      // the root navigator context mounts them outside their branch's
      // IndexedStack and renders blank. go() re-resolves the full route
      // tree — shell + correct branch — every time.
      GoRouter.of(context).go(url);
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  /// Call after Supabase sign-in so this device's FCM token is tied to the user.
  static Future<void> loginUser(String userId) async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e, s) {
      debugPrint('[Push] loginUser error: $e\n$s');
    }
  }

  /// Call on sign-out. The auth session is already gone by then, so the row
  /// can't be deleted client-side; killing the token makes it invalid and the
  /// edge functions prune it on the first failed send.
  static Future<void> logoutUser() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, s) {
      debugPrint('[Push] logoutUser error: $e\n$s');
    }
  }

  static Future<void> _saveToken(String token) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    try {
      await client.rpc(
        'register_device_token',
        params: {
          'p_token': token,
          'p_platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );
    } catch (e, s) {
      debugPrint('[Push] save token error: $e\n$s');
    }
  }
}
