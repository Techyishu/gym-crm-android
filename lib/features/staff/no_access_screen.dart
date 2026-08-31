import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_icons.dart';

/// Shown when someone opens a staff route their role doesn't cover, instead of
/// bouncing them to the dashboard with no explanation (canvas 1n).
class NoAccessScreen extends ConsumerWidget {
  /// Human name of the area they tried to open, e.g. "Money", "Reports".
  final String feature;
  const NoAccessScreen({super.key, required this.feature});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider).valueOrNull ?? 'staff';
    final roleLabel = role.isEmpty
        ? 'account'
        : '${role[0].toUpperCase()}${role.substring(1)} account';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppTheme.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    AppIcons.lock,
                    size: 26,
                    color: AppTheme.statusNeutral,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '$feature is manager-only',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your $roleLabel does not cover this area. '
                  'Ask the owner to change your role.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => context.go('/staff/dashboard'),
                    child: const Text('Back to Home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
