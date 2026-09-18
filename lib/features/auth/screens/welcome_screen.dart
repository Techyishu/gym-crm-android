import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Owner/member chooser shown after onboarding and consent.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static final _helpUri = Uri.parse(
    'https://wa.me/917541004076?text=${Uri.encodeComponent('Hi, I need help with GymCRM.')}',
  );

  static const _space8 = 8.0;
  static const _space12 = 12.0;
  static const _space16 = 16.0;
  static const _space20 = 20.0;
  static const _space24 = 24.0;

  static Future<void> _openHelp(BuildContext context) async {
    final opened = await launchUrl(
      _helpUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 760;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                _space16,
                _space12,
                _space16,
                _space24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OrbitHero(height: compact ? 320 : 390),
                      SizedBox(height: compact ? _space20 : _space24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: _space8),
                        child: Text(
                          'Welcome to GymCRM.',
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                            color: AppTheme.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                      SizedBox(height: compact ? _space20 : _space24),
                      _PortalButton(
                        label: 'I run a gym',
                        primary: true,
                        onTap: () => context.go('/login'),
                      ),
                      const SizedBox(height: _space12),
                      _PortalButton(
                        label: "I'm a gym member",
                        primary: false,
                        onTap: () => context.go('/login/member'),
                      ),
                      const SizedBox(height: _space12),
                      Center(
                        child: TextButton(
                          onPressed: () => _openHelp(context),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.inkSoft,
                            minimumSize: const Size(44, 44),
                          ),
                          child: Text.rich(
                            const TextSpan(
                              text: 'Need help? ',
                              children: [
                                TextSpan(
                                  text: 'Contact us',
                                  style: TextStyle(
                                    color: AppTheme.ink,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbitHero extends StatelessWidget {
  final double height;
  const _OrbitHero({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Stack(
        children: [
          Positioned(
            width: height * .88,
            height: height * .88,
            right: -height * .18,
            top: -height * .12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: .13),
                ),
              ),
            ),
          ),
          Positioned(
            width: height * .62,
            height: height * .62,
            right: -height * .05,
            top: height * .02,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: .18),
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            top: 18,
            child: SizedBox(
              width: 142,
              height: 48,
              child: Image.asset(
                'assets/branding/gymcrm-logo-horizontal-theme.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, _, _) => const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'GymCRM',
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -8,
            right: -8,
            top: 42,
            bottom: -22,
            child: Image.asset(
              'assets/illustrations/gymcrm_welcome_hero.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 72,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 72,
            right: 14,
            child: _InfoPill(label: 'Run the floor'),
          ),
          const Positioned(
            left: 14,
            bottom: 14,
            child: _InfoPill(label: 'Track member progress'),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  const _InfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(99),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PortalButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _PortalButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = primary ? AppTheme.accent : AppTheme.surface2;
    final foreground = primary ? AppTheme.accentFg : AppTheme.ink;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward_rounded, color: foreground, size: 21),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
