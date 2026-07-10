import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _PageData(
      title: 'All your members,\nin one place',
      subtitle:
          "See who's active, who's expiring and who to call — the moment you open the app.",
      preview: _MembersPreview(),
    ),
    _PageData(
      title: 'Never chase\nfees again',
      subtitle:
          'Collect payments, send auto reminders on WhatsApp, and track dues without a spreadsheet.',
      preview: _PaymentsPreview(),
    ),
    _PageData(
      title: 'Check-ins in\none tap',
      subtitle:
          "Scan a QR at the door or search a name — front desk stays fast, even on your busiest hour.",
      preview: _CheckinPreview(),
    ),
  ];

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
  }

  Future<void> _skipToLogin() async {
    await _markDone();
    if (mounted) context.go('/login');
  }

  Future<void> _finishToSignup() async {
    await _markDone();
    if (mounted) context.go('/signup');
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    } else {
      _finishToSignup();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentPage > 0) {
          _controller.previousPage(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOut,
          );
        } else {
          _skipToLogin();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isLast)
                      TextButton(
                        onPressed: _skipToLogin,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        child: const Text('Skip'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemCount: _pages.length,
                  itemBuilder: (_, i) => _SlidePage(page: _pages[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  children: [
                    _DotRow(count: _pages.length, current: _currentPage),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _next,
                        child: Text(isLast ? 'Create your gym' : 'Next'),
                      ),
                    ),
                    if (isLast) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Already have an account? ',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                          GestureDetector(
                            onTap: _skipToLogin,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Slide page ──────────────────────────────────────────────────────────────

class _SlidePage extends StatelessWidget {
  final _PageData page;
  const _SlidePage({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Expanded(flex: 5, child: Center(child: page.preview)),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.18,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            page.subtitle,
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.55),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Slide 1: members dashboard preview ───────────────────────────────────────

class _MembersPreview extends StatelessWidget {
  const _MembersPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Iron House Gym',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const _InitialsChip(initials: 'RK', bg: AppTheme.statusActive, fg: Colors.white),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              _StatTile(label: 'Active', value: '214'),
              _StatTile(label: 'Check-ins', value: '63'),
              _StatTile(label: 'Renewals', value: '9', valueColor: AppTheme.statusDanger),
            ],
          ),
          const Divider(height: 28),
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
  const _StatTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: valueColor ?? AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

// ── Slide 2: payments preview ────────────────────────────────────────────────

class _PaymentsPreview extends StatelessWidget {
  const _PaymentsPreview();

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collected today',
                    style: TextStyle(color: AppTheme.onDarkSoft, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('₹18,400',
                    style: TextStyle(color: AppTheme.onDark, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('₹42,300 still pending',
                    style: TextStyle(color: AppTheme.onDarkSoft, fontSize: 12)),
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
                  sub: '3 days overdue',
                  subColor: AppTheme.statusDanger,
                  trailing: const Text('₹1,200',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                ),
                const SizedBox(height: 14),
                _MemberRow(
                  initials: 'SN',
                  bg: const Color(0xFFF4E8CD),
                  fg: AppTheme.statusWarn,
                  name: 'Sneha Nair',
                  sub: 'Due in 2 days',
                  subColor: AppTheme.statusWarn,
                  trailing: const Text('₹1,500',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide 3: check-in preview ────────────────────────────────────────────────

class _CheckinPreview extends StatelessWidget {
  const _CheckinPreview();

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
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            color: AppTheme.darkCard,
            child: _ScanFrame(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: AppTheme.onDark, size: 34),
                  const SizedBox(height: 10),
                  Text('Scan to check in',
                      style: TextStyle(color: AppTheme.onDark, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _MemberRow(
                  initials: 'PM',
                  bg: AppTheme.statusActiveBg,
                  fg: AppTheme.statusActive,
                  name: 'Priya Menon',
                  sub: '7:42 AM',
                  subColor: AppTheme.textSecondary,
                  trailing: const Icon(Icons.check_circle, color: AppTheme.statusActive, size: 20),
                ),
                const SizedBox(height: 14),
                _MemberRow(
                  initials: 'RK',
                  bg: AppTheme.statusActiveBg,
                  fg: AppTheme.statusActive,
                  name: 'Rahul Kapoor',
                  sub: '7:31 AM',
                  subColor: AppTheme.textSecondary,
                  trailing: const Icon(Icons.check_circle, color: AppTheme.statusActive, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  final Widget child;
  const _ScanFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(padding: const EdgeInsets.all(14), child: child),
        Positioned(top: 0, left: 0, child: _corner(topLeft: true)),
        Positioned(top: 0, right: 0, child: _corner(topRight: true)),
        Positioned(bottom: 0, left: 0, child: _corner(bottomLeft: true)),
        Positioned(bottom: 0, right: 0, child: _corner(bottomRight: true)),
      ],
    );
  }

  Widget _corner({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    const side = BorderSide(color: AppTheme.accent, width: 2.5);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        border: Border(
          top: (topLeft || topRight) ? side : BorderSide.none,
          bottom: (bottomLeft || bottomRight) ? side : BorderSide.none,
          left: (topLeft || bottomLeft) ? side : BorderSide.none,
          right: (topRight || bottomRight) ? side : BorderSide.none,
        ),
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

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _DotRow extends StatelessWidget {
  final int count;
  final int current;
  const _DotRow({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accent : AppTheme.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _PageData {
  final String title;
  final String subtitle;
  final Widget preview;

  const _PageData({required this.title, required this.subtitle, required this.preview});
}
