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
      // Logo stays pinned top-left; the choice itself sits in the middle of
      // whatever room is left, so it lands under the thumb on a tall phone and
      // still scrolls on a short one.
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand lockup — the real app icon + wordmark.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 34,
                      height: 34,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'GymCRM',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: ConstrainedBox(
                    // Exactly the room left under the logo, so Center really
                    // centres; taller content than this simply scrolls.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                              style: TextStyle(
                                fontSize: 15,
                                color: AppTheme.inkSoft,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _PathCard(
                              filled: true,
                              icon: Icons.storefront_rounded,
                              title: 'I run a gym',
                              body:
                                  'Owners, managers, trainers and front-desk staff.',
                              onTap: () => context.go('/login'),
                            ),
                            const SizedBox(height: 12),
                            _PathCard(
                              filled: false,
                              icon: Icons.person_rounded,
                              title: "I'm a gym member",
                              body:
                                  'See your plan, dues, workouts and check-ins.',
                              onTap: () => context.go('/login/member'),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Picked the wrong one? Go back anytime. Nothing is '
                              'saved until you log in.',
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  /// The owner path is the teal-filled one — most sign-ins are staff.
  final bool filled;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  const _PathCard({
    required this.filled,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? AppTheme.accent : AppTheme.surface;
    final fg = filled ? AppTheme.accentFg : AppTheme.ink;
    final bodyFg = filled
        ? AppTheme.accentFg.withValues(alpha: 0.85)
        : AppTheme.inkSoft;
    final iconBg = filled
        ? AppTheme.accentFg.withValues(alpha: 0.18)
        : AppTheme.accentSoft;
    final iconFg = filled ? AppTheme.accentFg : AppTheme.accent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: filled
                ? null
                : Border.all(color: AppTheme.border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: iconFg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: bodyFg,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, size: 20, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
