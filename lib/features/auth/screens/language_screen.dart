import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appLocaleProvider).languageCode;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/branding/gymcrm-logo-horizontal-theme.png',
                    height: 44,
                    alignment: Alignment.centerLeft,
                    errorBuilder: (_, _, _) => const Text(
                      'GymCRM',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 52),
                  Text(
                    context.l10n.chooseLanguage,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.chooseLanguageSubtitle,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _LanguageChoice(
                    title: 'हिन्दी',
                    subtitle: 'Hindi',
                    selected: selected == 'hi',
                    onTap: () => setAppLocale(ref, const Locale('hi')),
                  ),
                  const SizedBox(height: 12),
                  _LanguageChoice(
                    title: 'English',
                    subtitle: 'अंग्रेज़ी',
                    selected: selected == 'en',
                    onTap: () => setAppLocale(ref, const Locale('en')),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => context.go('/login'),
                      child: Text(context.l10n.continueLabel),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.languageChangeLater,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkHint,
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

class _LanguageChoice extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageChoice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppTheme.accentSoft : AppTheme.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: selected ? AppTheme.accent : AppTheme.border,
        width: selected ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppTheme.accent : AppTheme.inkHint,
              size: 24,
            ),
          ],
        ),
      ),
    ),
  );
}
