import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';

class GymCRMApp extends ConsumerStatefulWidget {
  const GymCRMApp({super.key});

  @override
  ConsumerState<GymCRMApp> createState() => _GymCRMAppState();
}

class _GymCRMAppState extends ConsumerState<GymCRMApp> {
  StreamSubscription<Uri>? _linkSub;
  ProviderSubscription<AsyncValue<AuthState>>? _authSub;

  @override
  void initState() {
    super.initState();
    // Dodo checkout redirects here (gymcrm://payment-success) after mobile
    // payment completes. The webhook (server-side) is the source of truth
    // for the actual plan update — this just forces the app to re-read it
    // immediately instead of waiting for the next natural refetch.
    _linkSub = AppLinks().uriLinkStream.listen((uri) {
      if (uri.host == 'payment-success') {
        ref.invalidate(staffProfileProvider);
      }
    });

    // Email/OTP sign-in paths invalidate these caches themselves right after
    // the session is created (see AuthNotifier). OAuth (Google) can't do that
    // — signInWithOAuth() just launches the browser and returns immediately;
    // the real session lands later via deep link, racing whatever screen is
    // already on-screen. If a provider fetches during that race window it
    // caches the failure and never retries. Catch every sign-in here instead,
    // in one place, so no auth path can skip it.
    _authSub = ref.listenManual(authStateProvider, (previous, next) {
      if (next.valueOrNull?.event == AuthChangeEvent.signedIn) {
        ref.invalidate(gymIdProvider);
        ref.invalidate(staffProfileProvider);
        ref.invalidate(userTypeProvider);
        ref.invalidate(memberRecordProvider);
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _authSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'GymCRM',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Replace Flutter's red crash screen in production with a graceful
      // error widget so one broken widget doesn't crash the whole app.
      builder: (context, child) {
        ErrorWidget.builder = (_) => const _AppErrorWidget();
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _AppErrorWidget extends StatelessWidget {
  const _AppErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Color(0xFFE53935)),
              SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Please go back or restart the app.\nIf this keeps happening, contact support.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
