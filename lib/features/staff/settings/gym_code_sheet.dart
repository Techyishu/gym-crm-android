import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

/// The code a gym owner hands to members so they can self-register in the
/// member portal. Setup-once config, not a daily concern — lives in More
/// alongside Gym Branches / Biometric Device rather than on the dashboard or
/// Members screen, where it competed with things staff actually look at
/// every day.
class GymCodeSheet extends ConsumerWidget {
  const GymCodeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym =
        ref.watch(staffProfileProvider).valueOrNull?['gyms']
            as Map<String, dynamic>?;
    final gymName = gym?['name'] as String? ?? 'your gym';
    final code = gym?['member_code'] as String?;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Member signup code',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Members enter this code — plus their phone number — to create their own portal account.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.inkSoft,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (code == null || code.isEmpty)
                    const Text(
                      'No code available yet.',
                      style: TextStyle(color: AppTheme.inkHint, fontSize: 13),
                    )
                  else ...[
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Gym code copied')),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Tap to copy',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkHint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final box = context.findRenderObject() as RenderBox?;
                          Share.share(
                            'Set up your $gymName member portal — open the GymCRM app, '
                            'tap Member, "Create your account", and enter gym code $code with your phone number.',
                            sharePositionOrigin: box != null
                                ? box.localToGlobal(Offset.zero) & box.size
                                : null,
                          );
                        },
                        icon: const Icon(AppIcons.share, size: 18),
                        label: const Text('Share with members'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
