import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

/// Shown in place of the whole member portal when the member's gym has no
/// active subscription. The mirror of `PaywallScreen` on the staff side, minus
/// any way to pay: a member cannot buy their gym's plan, so the only actions
/// are "call the gym" and "sign out".
class GymInactiveScreen extends ConsumerWidget {
  final String? gymName;
  const GymInactiveScreen({super.key, this.gymName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = gymName?.trim();
    final hasName = gym != null && gym.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.statusWarnBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    AppIcons.lock,
                    size: 32,
                    color: AppTheme.statusWarn,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  hasName ? '$gym is not active' : 'Your gym is not active',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your gym’s subscription has ended, so the member app is '
                  'paused. Please contact your gym — they can restore access '
                  'by renewing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
