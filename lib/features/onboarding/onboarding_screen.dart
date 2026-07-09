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
      tag: 'All-in-one platform',
      title: 'Manage Your\nGym Smarter',
      subtitle:
          'Run memberships, schedules, billing, and staff — all from one powerful app built for gym owners.',
      illustrationColor: Color(0xFFE9E6DD),
      accentColor: Color(0xFF2C6E7A),
      iconData: Icons.fitness_center_rounded,
      badgeItems: [
        _BadgeItem(Icons.people_rounded, '142 Members'),
        _BadgeItem(Icons.trending_up_rounded, '94% Active'),
      ],
    ),
    _PageData(
      tag: 'Smart check-ins',
      title: 'Track Every\nMember Visit',
      subtitle:
          'Instant QR-code check-ins, member profiles with photos, and real-time attendance logs.',
      illustrationColor: Color(0xFFDDEFE2),
      accentColor: Color(0xFF2E7D4F),
      iconData: Icons.qr_code_scanner_rounded,
      badgeItems: [
        _BadgeItem(Icons.check_circle_rounded, '23 Today'),
        _BadgeItem(Icons.timer_rounded, 'Live Tracking'),
      ],
    ),
    _PageData(
      tag: 'Revenue & leads',
      title: 'Grow Your\nBusiness',
      subtitle:
          'Smart invoicing, automated reminders, and a leads pipeline to convert prospects into members.',
      illustrationColor: Color(0xFFF4E8CD),
      accentColor: Color(0xFFB07C1F),
      iconData: Icons.bar_chart_rounded,
      badgeItems: [
        _BadgeItem(Icons.receipt_rounded, '₹ Billing'),
        _BadgeItem(Icons.person_add_rounded, 'Lead Capture'),
      ],
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) context.go('/login');
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
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
          _finish(); // back on first slide = skip onboarding → login
        }
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: logo + skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.fitness_center_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GymCRM',
                        style: TextStyle(fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (!isLast)
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        textStyle: TextStyle(fontFamily: 'Inter',
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _SlidePage(page: _pages[i]),
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: Column(
                children: [
                  _DotRow(
                    count: _pages.length,
                    current: _currentPage,
                    activeColor: _pages[_currentPage].accentColor,
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: SizedBox(
                      key: ValueKey(isLast),
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pages[_currentPage].accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                          textStyle: TextStyle(fontFamily: 'Inter',
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(isLast ? 'Get Started' : 'Next'),
                            const SizedBox(width: 6),
                            Icon(
                              isLast
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),  // PopScope
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

          // Illustration card
          Expanded(
            flex: 5,
            child: _IllustrationCard(page: page),
          ),

          const SizedBox(height: 32),

          // Tag chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: page.illustrationColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: page.accentColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              page.tag.toUpperCase(),
              style: TextStyle(fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: page.accentColor,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Text(
            page.title,
            style: TextStyle(fontFamily: 'Inter',
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              height: 1.18,
            ),
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            page.subtitle,
            style: TextStyle(fontFamily: 'Inter',
              fontSize: 15,
              color: AppTheme.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Illustration card ────────────────────────────────────────────────────────

class _IllustrationCard extends StatelessWidget {
  final _PageData page;
  const _IllustrationCard({required this.page});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: page.illustrationColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: page.accentColor.withValues(alpha: 0.12), width: 1.5),
      ),
      child: Stack(
        children: [
          // Decorative circles (background)
          Positioned(
            top: -30,
            right: -30,
            child: _DecorCircle(
                size: 130,
                color: page.accentColor.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: _DecorCircle(
                size: 100,
                color: page.accentColor.withValues(alpha: 0.07)),
          ),
          Positioned(
            top: 20,
            left: 24,
            child: _DecorCircle(
                size: 20,
                color: page.accentColor.withValues(alpha: 0.25)),
          ),
          Positioned(
            bottom: 32,
            right: 28,
            child: _DecorCircle(
                size: 14,
                color: page.accentColor.withValues(alpha: 0.3)),
          ),

          // Center icon
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: page.accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: page.accentColor.withValues(alpha: 0.28),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(page.iconData, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                // Floating badge row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: page.badgeItems
                      .map((b) => Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: _FloatingBadge(
                                item: b, accentColor: page.accentColor),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _DecorCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  final _BadgeItem item;
  final Color accentColor;
  const _FloatingBadge({required this.item, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 15, color: accentColor),
          const SizedBox(width: 6),
          Text(
            item.label,
            style: TextStyle(fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _DotRow extends StatelessWidget {
  final int count;
  final int current;
  final Color activeColor;
  const _DotRow(
      {required this.count, required this.current, required this.activeColor});

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
            color: isActive
                ? activeColor
                : AppTheme.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Data models ──────────────────────────────────────────────────────────────

class _PageData {
  final String tag;
  final String title;
  final String subtitle;
  final Color illustrationColor;
  final Color accentColor;
  final IconData iconData;
  final List<_BadgeItem> badgeItems;

  const _PageData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.illustrationColor,
    required this.accentColor,
    required this.iconData,
    required this.badgeItems,
  });
}

class _BadgeItem {
  final IconData icon;
  final String label;
  const _BadgeItem(this.icon, this.label);
}
