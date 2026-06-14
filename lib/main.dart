import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

const _supabaseUrl = 'https://orlqjhqxeyukvfzsursl.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw';

const _smsChannel = MethodChannel('com.gymcrm/sms');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty,
    'Build with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
  );

  // Catch errors thrown inside the Flutter framework (widget build, layout, etc.)
  // and replace the default red-screen crash with a graceful error widget.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[GymCRM] Flutter error: ${details.exception}\n${details.stack}');
  };

  // Catch errors that escape Flutter's zones entirely (unawaited Future errors,
  // isolate-boundary errors). Without this they are silently swallowed on release.
  runZonedGuarded(() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );

    runApp(const ProviderScope(child: GymCRMApp()));

    // Push session tokens + gym_id to the native Kotlin worker on every launch
    // so SmsReminderWorker can refresh tokens and query members without needing
    // a Flutter engine in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncNativeCredentials();
      // Re-sync whenever the session refreshes (token rotation).
      Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
        if (data.event == AuthChangeEvent.tokenRefreshed ||
            data.event == AuthChangeEvent.signedIn) {
          await _syncNativeCredentials();
        }
      });
    });
  }, (error, stack) {
    debugPrint('[GymCRM] Unhandled async error: $error\n$stack');
  });
}

Future<void> _syncNativeCredentials() async {
  try {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;

    // Fetch gym_id for this user.
    final profile = await client
        .from('profiles')
        .select('gym_id')
        .eq('id', session.user.id)
        .maybeSingle();
    final gymId = profile?['gym_id'] as String?;
    if (gymId == null) return;

    // url and anonKey are compile-time constants baked into the binary.
    // The Kotlin worker reads them from BuildConfig, not from this channel.
    // TODO(security): migrate refreshToken storage to Android Keystore on the
    // native side — MethodChannel IPC is IPC-local but not hardware-backed.
    await _smsChannel.invokeMethod('storeCredentials', {
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'gymId': gymId,
    });
  } catch (e) {
    // Best-effort — will retry on next launch/token refresh.
    debugPrint('[GymCRM] _syncNativeCredentials error: $e');
  }
}
