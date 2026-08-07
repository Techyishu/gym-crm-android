import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  static Future<void> _goToLogin(BuildContext context) async {
    await _markDone();
    if (context.mounted) context.go('/login');
  }

  static Future<void> _goToSignup(BuildContext context) async {
    await _markDone();
    if (context.mounted) context.go('/signup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      const Text(
                        'Run your gym\nlike a pro',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          height: 1.15,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Members, payments and check-ins — all in one place.',
                        style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      const _MembersPreview(),
                      const SizedBox(height: 28),
                      const _BulletRow(
                        icon: Icons.people_outline,
                        text: 'See who\'s active, expiring or due — instantly',
                      ),
                      const SizedBox(height: 14),
                      const _BulletRow(
                        icon: Icons.payments_outlined,
                        text: 'Collect fees and send WhatsApp reminders',
                      ),
                      const SizedBox(height: 14),
                      const _BulletRow(
                        icon: Icons.qr_code_scanner_rounded,
                        text: 'Check members in with a single tap',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _goToSignup(context),
                  child: const Text('Create your gym'),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Already have an account? ',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  GestureDetector(
                    onTap: () => _goToLogin(context),
                    child: const Text(
                      'Log in',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bullet row ───────────────────────────────────────────────────────────────

class _BulletRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: AppTheme.accent, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(text,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          ),
        ),
      ],
    );
  }
}

// ── Hero preview: members/dashboard snapshot ─────────────────────────────────

class _MembersPreview extends StatelessWidget {
  const _MembersPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.cardDecoration(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: AppTheme.darkCard,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Iron House Gym',
                        style: TextStyle(color: AppTheme.onDark, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        _StatTile(label: 'Active', value: '214', dark: true),
                        _StatTile(label: 'Check-ins', value: '63', dark: true),
                        _StatTile(label: 'Renewals', value: '9', valueColor: Color(0xFFEF8B72), dark: true),
                      ],
                    ),
                  ],
                ),
                const _InitialsChip(initials: 'RK', bg: AppTheme.statusActive, fg: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _MemberRow(
                  initials: 'AV',
                  bg: const Color(0xFFF8DFD7),
                  fg: AppTheme.statusDanger,
                  name: 'Amit Verma',
                  sub: 'Plan expired 3 days ago',
                  subColor: AppTheme.statusDanger,
                  trailing: const _RemindPill(),
                ),
                const SizedBox(height: 14),
                _MemberRow(
                  initials: 'SN',
                  bg: const Color(0xFFF4E8CD),
                  fg: AppTheme.statusWarn,
                  name: 'Sneha Nair',
                  sub: 'Due in 2 days · ₹1,500',
                  subColor: AppTheme.statusWarn,
                  trailing: const _RemindPill(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemindPill extends StatelessWidget {
  const _RemindPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(20)),
      child: const Text('Remind', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool dark;
  const _StatTile({required this.label, required this.value, this.valueColor, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: dark ? AppTheme.onDarkSoft : AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? (dark ? AppTheme.onDark : AppTheme.textPrimary))),
        ],
      ),
    );
  }
}

// ── Shared row/chip widgets ──────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  final String initials;
  final Color bg;
  final Color fg;
  final String name;
  final String sub;
  final Color subColor;
  final Widget? trailing;

  const _MemberRow({
    required this.initials,
    required this.bg,
    required this.fg,
    required this.name,
    required this.sub,
    required this.subColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InitialsChip(initials: initials, bg: bg, fg: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _InitialsChip extends StatelessWidget {
  final String initials;
  final Color bg;
  final Color fg;
  const _InitialsChip({required this.initials, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
