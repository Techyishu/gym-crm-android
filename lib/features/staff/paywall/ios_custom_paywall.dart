import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';

class IosCustomPaywall extends StatefulWidget {
  const IosCustomPaywall({super.key});

  @override
  State<IosCustomPaywall> createState() => _IosCustomPaywallState();
}

class _IosCustomPaywallState extends State<IosCustomPaywall> {
  Package? _monthly;
  Package? _annual;
  Package? _selected;

  bool _loadingOfferings = true;
  bool _purchasing = false;
  bool _restoring = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (!mounted) return;
      setState(() {
        _monthly = current?.monthly;
        _annual = current?.annual;
        // Default selection: monthly. Annual used to be pre-selected, which
        // asks for a year up front at the moment the owner is least convinced.
        // It stays on screen above as the better-value upsell.
        _selected = _monthly ?? _annual;
        _loadingOfferings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not load plans. Check your connection and try again.';
        _loadingOfferings = false;
      });
    }
  }

  Future<void> _purchase() async {
    if (_selected == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _errorMessage = null;
    });
    try {
      await Purchases.purchasePackage(_selected!);
      // customerInfoProvider stream auto-updates → StaffShell gate drops
    } on PurchasesError catch (e) {
      if (!mounted) return;
      // User cancelled — no error message needed
      if (e.code != PurchasesErrorCode.purchaseCancelledError) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } finally {
      if (mounted)
        setState(() {
          _purchasing = false;
        });
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _errorMessage = null;
    });
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      final hasAccess = info.entitlements.active.containsKey('gymcrm Pro');
      if (!hasAccess) {
        setState(() {
          _errorMessage = 'No active subscription found for this Apple ID.';
        });
      }
      // If hasAccess → stream updates → gate drops automatically
    } on PurchasesError catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } finally {
      if (mounted)
        setState(() {
          _restoring = false;
        });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _loadingOfferings
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _monthly == null && _annual == null
          ? _ErrorState(message: _errorMessage!, onRetry: _loadOfferings)
          : _PaywallBody(
              monthly: _monthly,
              annual: _annual,
              selected: _selected,
              onSelect: (pkg) => setState(() => _selected = pkg),
              onPurchase: _purchase,
              onRestore: _restore,
              purchasing: _purchasing,
              restoring: _restoring,
              errorMessage: _errorMessage,
              onOpenUrl: _openUrl,
            ),
    );
  }
}

// Benefit-first, distinct icon per line — matches the Android paywall's hero.
const _kIosFeatures = [
  (
    icon: AppIcons.chat,
    text: 'We remind your members before their fees are due — automatically',
  ),
  (
    icon: AppIcons.wallet,
    text: 'Know exactly who owes you money, today',
  ),
  (
    icon: AppIcons.showChart,
    text: 'See what you collected this month without opening a register',
  ),
  (
    icon: AppIcons.qrCode,
    text: 'Members check in with a QR code, no register at the door',
  ),
  (
    icon: AppIcons.allInclusive,
    text: 'Unlimited members, check-ins and staff logins',
  ),
  (icon: AppIcons.supportAgent, text: 'Priority support'),
];

// ── Paywall body ──────────────────────────────────────────────────────────────

class _PaywallBody extends StatelessWidget {
  final Package? monthly;
  final Package? annual;
  final Package? selected;
  final void Function(Package) onSelect;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;
  final bool purchasing;
  final bool restoring;
  final String? errorMessage;
  final Future<void> Function(String) onOpenUrl;

  const _PaywallBody({
    required this.monthly,
    required this.annual,
    required this.selected,
    required this.onSelect,
    required this.onPurchase,
    required this.onRestore,
    required this.purchasing,
    required this.restoring,
    required this.errorMessage,
    required this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Hero: badge + headline + benefits, one continuous surface ──
                const _IosHero(features: _kIosFeatures),

                const SizedBox(height: 24),

                // ── Duration selector + price panel ─────────────────────────
                _IosDurationSegmented(
                  monthly: monthly,
                  annual: annual,
                  selected: selected,
                  onSelect: onSelect,
                ),
                if (monthly != null && annual != null)
                  const SizedBox(height: 14),
                if (selected != null) _IosPricePanel(package: selected!),

                // ── Error ────────────────────────────────────────────────────
                if (errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.statusDangerBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.statusDanger,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── CTA button ───────────────────────────────────────────────
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (purchasing || selected == null)
                        ? null
                        : onPurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.accentFg,
                      disabledBackgroundColor: AppTheme.surface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: purchasing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.accentFg,
                            ),
                          )
                        : Text(
                            _ctaLabel(selected),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Restore ──────────────────────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: restoring ? null : onRestore,
                    child: restoring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Restore purchases',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Trust ─────────────────────────────────────────────────────
                const _TrustFooterRow(),

                const SizedBox(height: 12),

                // ── Legal ─────────────────────────────────────────────────────
                const _LegalLinks(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _ctaLabel(Package? pkg) {
    if (pkg == null) return 'Select a plan';
    return 'Subscribe · ${pkg.storeProduct.priceString}';
  }
}

// ── Hero: badge + headline + benefits, one continuous dark surface ───────────

class _IosHero extends StatelessWidget {
  final List<({IconData icon, String text})> features;
  const _IosHero({required this.features});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.darkCardDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'GymCRM Pro',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.accentFg,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Everything your gym needs,\nin one app.',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.onDark,
              height: 1.18,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 22),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 18),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.icon, size: 17, color: AppTheme.mintOnDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.onDark,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Duration selector ─────────────────────────────────────────────────────────

/// Same pill-toggle idiom as the Android paywall (and the app's own
/// Staff/Member login switch) instead of two stacked bordered radio cards.
/// Falls back to nothing when only one package is on offer — the price panel
/// alone covers that case, same as the old single-card fallback did.
class _IosDurationSegmented extends StatelessWidget {
  final Package? monthly;
  final Package? annual;
  final Package? selected;
  final ValueChanged<Package> onSelect;
  const _IosDurationSegmented({
    required this.monthly,
    required this.annual,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <(String, Package)>[
      if (monthly != null) ('Monthly', monthly!),
      if (annual != null) ('Yearly', annual!),
    ];
    if (segments.length < 2) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: segments.map((s) {
          final (label, pkg) = s;
          final isSelected = selected == pkg;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(pkg),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppTheme.accentFg : AppTheme.ink,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Price panel ────────────────────────────────────────────────────────────────

class _IosPricePanel extends StatelessWidget {
  final Package package;
  const _IosPricePanel({required this.package});

  bool get _isAnnual => package.packageType == PackageType.annual;

  String? get _perMonthPrice {
    if (!_isAnnual) return null;
    final annual = package.storeProduct.price;
    final perMonth = annual / 12;
    final currency = package.storeProduct.currencyCode;
    return '$currency${perMonth.toStringAsFixed(0)}/mo';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                package.storeProduct.priceString,
                style: AppTheme.numberStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _isAnnual ? '/ year' : '/ month',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
              if (_isAnnual) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Best value',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isAnnual
                ? '$_perMonthPrice — billed annually'
                : 'Cancel anytime from your Apple ID settings.',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trust row (footer, unboxed) ───────────────────────────────────────────────

class _TrustFooterRow extends StatelessWidget {
  const _TrustFooterRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        icon: AppIcons.closeRounded,
        text: 'Cancel anytime from your Apple ID settings',
      ),
      (
        icon: AppIcons.lock,
        text: 'Your member data is never deleted, even if you cancel',
      ),
    ];

    return Column(
      children: items
          .map(
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(i.icon, size: 15, color: AppTheme.statusActive),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      i.text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Legal links ───────────────────────────────────────────────────────────────

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.inkHint,
            height: 1.6,
          ),
          children: [
            const TextSpan(
              text:
                  'Subscription auto-renews unless cancelled 24h before renewal.\n',
            ),
            TextSpan(
              text: 'Terms of Use',
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: AppTheme.inkSoft,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => context.push('/legal/terms'),
            ),
            const TextSpan(text: '  ·  '),
            TextSpan(
              text: 'Privacy Policy',
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: AppTheme.inkSoft,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => context.push('/legal/privacy'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            AppIcons.wifiOff,
            size: 48,
            color: AppTheme.inkHint,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
