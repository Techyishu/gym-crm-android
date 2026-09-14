import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

/// Canvas `welcome` — the owner/member chooser shown after onboarding and
/// consent, before either login form. Not a route many people bookmark;
/// it's the fork every fresh sign-in (and every sign-out) lands back on.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Who is signing in?',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                      height: 1.15,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Pick one to continue.',
                    style: TextStyle(fontSize: 15, color: AppTheme.inkSoft),
                  ),
                  const SizedBox(height: 22),
                  _PathCard(
                    dark: true,
                    number: '01',
                    title: 'I run a gym',
                    body: 'Owners, managers, trainers and front-desk staff.',
                    cta: 'Continue →',
                    onTap: () => context.go('/login'),
                  ),
                  const SizedBox(height: 14),
                  _PathCard(
                    dark: false,
                    number: '02',
                    title: "I'm a gym member",
                    body: 'See your plan, dues, workouts and check-ins.',
                    cta: 'Continue →',
                    onTap: () => context.go('/login/member'),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Picked the wrong one? Go back anytime. Nothing is saved '
                    'until you log in.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkHint,
                      height: 1.6,
                    ),
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

class _PathCard extends StatelessWidget {
  final bool dark;
  final String number;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;
  const _PathCard({
    required this.dark,
    required this.number,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = dark ? AppTheme.darkCard : AppTheme.surface;
    final fg = dark ? AppTheme.onDark : AppTheme.ink;
    final bodyFg = dark ? AppTheme.onDarkSoft : AppTheme.inkSoft;
    final ctaFg = dark ? AppTheme.mintOnDark : AppTheme.accent;
    final badgeBg = dark ? AppTheme.darkCard2 : AppTheme.accentSoft;
    final badgeFg = dark ? AppTheme.mintOnDark : AppTheme.accent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: dark ? null : Border.all(color: AppTheme.border, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: badgeFg,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: fg,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(fontSize: 14, height: 1.55, color: bodyFg),
            ),
            const SizedBox(height: 8),
            Text(
              cta,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: ctaFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
