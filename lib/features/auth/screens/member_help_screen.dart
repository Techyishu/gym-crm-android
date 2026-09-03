import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';

/// Canvas `mHelp` — member password recovery is self-serve over SMS, not
/// email (there's no member email on file to reset). It reuses the member
/// signup flow: gym code -> phone -> SMS OTP -> set password, which
/// `verify-phone-otp` accepts for an already-claimed member row too.
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
                    title: 'Reset it over SMS',
                    subtitle:
                        'Verify your mobile number and set a new password. '
                        'No need to call the gym.',
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
                              'Enter your gym code (ask the front desk if you '
                              'do not have it).',
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        _HelpStep(
                          number: 2,
                          text:
                              'Enter the mobile number your gym has on file.',
                        ),
                        Divider(height: 1, color: AppTheme.border),
                        _HelpStep(
                          number: 3,
                          text:
                              'Enter the code sent by SMS, then set a new '
                              'password.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  CanvasButton(
                    label: 'Reset my password',
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
