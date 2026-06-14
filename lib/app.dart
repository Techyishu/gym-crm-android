import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

class GymCRMApp extends ConsumerWidget {
  const GymCRMApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
