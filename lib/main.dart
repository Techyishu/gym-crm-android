import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

const _supabaseUrl = 'https://orlqjhqxeyukvfzsursl.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw';

const _sentryDsn =
    'https://01a220921e1bfadef6df0380bfacec1f@o4511580229402624.ingest.us.sentry.io/4511580238774272';

const _smsChannel = MethodChannel('com.gymcrm/sms');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty,
    'Build with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
  );

  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.environment = kReleaseMode ? 'production' : 'development';
      options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
      options.attachScreenshot = true;
      options.attachViewHierarchy = true;
    },
    appRunner: () async {
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        Sentry.captureException(details.exception, stackTrace: details.stack);
      };

      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );

      runApp(const ProviderScope(child: GymCRMApp()));

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _syncNativeCredentials();
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
          if (data.event == AuthChangeEvent.tokenRefreshed ||
              data.event == AuthChangeEvent.signedIn) {
            await _syncNativeCredentials();
          }
        });
      });
    },
  );
}

Future<void> _syncNativeCredentials() async {
  try {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;

    final profile = await client
        .from('profiles')
        .select('gym_id')
        .eq('id', session.user.id)
        .maybeSingle();
    final gymId = profile?['gym_id'] as String?;
    if (gymId == null) return;

    await _smsChannel.invokeMethod('storeCredentials', {
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'gymId': gymId,
    });
  } catch (e, stack) {
    debugPrint('[GymCRM] _syncNativeCredentials error: $e');
    Sentry.captureException(e, stackTrace: stack);
  }
}
