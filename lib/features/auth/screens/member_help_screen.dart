import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';

/// Canvas `mHelp` — member password recovery runs through the gym, not a
/// self-serve email reset (there's no member email on file to reset). This
/// replaces the old one-line "Ask your gym for help" text with the canvas's
/// real 3-step explanation.
class MemberHelpScreen extends StatelessWidget {
  const MemberHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CanvasBack(onTap: () => context.pop()),
                  const SizedBox(height: 16),
                  const CanvasHeading(
                    title: 'Your gym can reset it',
                    subtitle:
                        'Member passwords are handled at the gym desk. Ask '
                        'your gym to send a fresh portal invite, then set a '
                        'new password.',
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: const [
                        _HelpStep(
                          number: 1,
                          text:
                              'Ask the front desk to resend your portal invite.',
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        _HelpStep(
                          number: 2,
                          text:
                              'Sign in again with your gym code and mobile number.',
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        _HelpStep(
                          number: 3,
                          text:
                              'Verify the code sent by SMS and set a new password.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  CanvasButton(
                    label: 'Sign in with gym code',
                    loading: false,
                    onPressed: () => context.push('/login/member-signup'),
                  ),
                  const SizedBox(height: 10),
                  CanvasSecondaryButton(
                    label: 'Back to log in',
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  final int number;
  final String text;
  const _HelpStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: AppTheme.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}
