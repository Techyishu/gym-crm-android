import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'features/legal/consent_screen.dart'
    show applyStoredConsent, analyticsConsentGranted;
import 'core/services/activity_log_service.dart';
import 'core/services/onesignal_service.dart';
import 'core/services/update_prompt.dart';
import 'firebase_options.dart';
import 'core/services/revenue_cat_service.dart';

const _supabaseUrl = 'https://orlqjhqxeyukvfzsursl.supabase.co';
const _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw';

const _sentryDsn =
    'https://01a220921e1bfadef6df0380bfacec1f@o4511580229402624.ingest.us.sentry.io/4511580238774272';

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
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;
      // DPDP: the consent screen names Sentry under "Improve the app", so no
      // crash report leaves the device without that consent. Sentry must still
      // initialise this early to catch startup crashes, so the gate is here at
      // the send hook rather than on init.
      options.beforeSendTransaction =
          (transaction, hint) => analyticsConsentGranted ? transaction : null;
      options.beforeSend = (event, hint) {
        if (!analyticsConsentGranted) return null;

        // Drop OS-level network interruptions caused by the device sleeping or
        // Android killing idle sockets. These are not actionable.
        final exceptions = event.exceptions;
        if (exceptions != null) {
          for (final ex in exceptions) {
            final value = ex.value ?? '';
            if (value.contains('Connection closed while receiving data') ||
                value.contains('Connection reset by peer')) {
              return null;
            }
          }
        }
        return event;
      };
    },
    appRunner: () async {
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        Sentry.captureException(details.exception, stackTrace: details.stack);
        ActivityLogService.logError(
          message: details.exception.toString(),
          stackTrace: details.stack?.toString(),
        );
      };

      // firebase_options.dart is Android-only for now; skip on iOS.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      // Runs on every platform, and after Firebase init so it can configure it:
      // Sentry's gate reads the flag this sets. DPDP — analytics, ad
      // measurement and crash reporting all stay off until /consent.
      await applyStoredConsent(await SharedPreferences.getInstance());

      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );

      // Initialize RevenueCat before runApp so the customerInfoStream is ready.
      await RevenueCatService.initialize();

      await OneSignalService.initialize();

      // If a session already exists at cold-start, log the user into RC /
      // OneSignal. Not awaited — these are network calls and must not block
      // first frame; the RC customer-info stream updates when login lands.
      final existingSession = Supabase.instance.client.auth.currentSession;
      if (existingSession != null) {
        unawaited(RevenueCatService.loginUser(existingSession.user.id));
        unawaited(OneSignalService.loginUser(existingSession.user.id));
      }

      runApp(const ProviderScope(child: GymCRMApp()));

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Play update check. Not awaited — it must never delay first paint.
        unawaited(UpdatePrompt.check());

        Supabase.instance.client.auth.onAuthStateChange.listen(
          (data) async {
            if (data.event == AuthChangeEvent.tokenRefreshed ||
                data.event == AuthChangeEvent.signedIn) {
              if (data.session != null) {
                await RevenueCatService.loginUser(data.session!.user.id);
                await OneSignalService.loginUser(data.session!.user.id);
              }
            }
            if (data.event == AuthChangeEvent.signedOut) {
              await RevenueCatService.logoutUser();
              await OneSignalService.logoutUser();
            }
          },
          onError: (error, stack) async {
            // Stale/revoked refresh token — sign out cleanly so the
            // router redirects to login instead of crashing.
            if (error is AuthApiException) {
              await Supabase.instance.client.auth.signOut();
            }
            Sentry.captureException(error, stackTrace: stack);
          },
        );
      });
    },
  );
}
