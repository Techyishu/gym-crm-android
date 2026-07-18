import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

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
        // Default selection: annual (best value)
        _selected = _annual ?? _monthly;
        _loadingOfferings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load plans. Check your connection and try again.';
        _loadingOfferings = false;
      });
    }
  }

  Future<void> _purchase() async {
    if (_selected == null || _purchasing) return;
    setState(() { _purchasing = true; _errorMessage = null; });
    try {
      await Purchases.purchasePackage(_selected!);
      // customerInfoProvider stream auto-updates → StaffShell gate drops
    } on PurchasesError catch (e) {
      if (!mounted) return;
      // User cancelled — no error message needed
      if (e.code != PurchasesErrorCode.purchaseCancelledError) {
        setState(() { _errorMessage = e.message; });
      }
    } finally {
      if (mounted) setState(() { _purchasing = false; });
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() { _restoring = true; _errorMessage = null; });
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
      setState(() { _errorMessage = e.message; });
    } finally {
      if (mounted) setState(() { _restoring = false; });
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────────
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.darkCardDecoration(radius: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
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
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Run your gym\nwithout limits.',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.onDark,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._features.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.check, size: 16, color: AppTheme.mintOnDark),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.onDarkSoft,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Plan cards ───────────────────────────────────────────────
                if (annual != null)
                  _PlanCard(
                    package: annual!,
                    isSelected: selected == annual,
                    badge: 'Best Value',
                    onTap: () => onSelect(annual!),
                  ),
                if (annual != null && monthly != null)
                  const SizedBox(height: 12),
                if (monthly != null)
                  _PlanCard(
                    package: monthly!,
                    isSelected: selected == monthly,
                    onTap: () => onSelect(monthly!),
                  ),

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
                          fontSize: 13, color: AppTheme.statusDanger),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── CTA button ───────────────────────────────────────────────
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (purchasing || selected == null) ? null : onPurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.accentFg,
                      disabledBackgroundColor: AppTheme.surface2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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

  static const _features = [
    'Unlimited members & check-ins',
    'Unlimited staff logins & roles',
    'WhatsApp due reminders',
    'Class scheduling & bookings',
    'Advanced reports & analytics',
    'Member portal & QR check-in',
    'Priority support',
  ];
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Package package;
  final bool isSelected;
  final String? badge;
  final VoidCallback onTap;

  const _PlanCard({
    required this.package,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  String get _title {
    switch (package.packageType) {
      case PackageType.annual:
        return 'Yearly';
      case PackageType.monthly:
        return 'Monthly';
      default:
        return package.storeProduct.title;
    }
  }

  String? get _perMonthPrice {
    if (package.packageType != PackageType.annual) return null;
    final annual = package.storeProduct.price;
    final perMonth = annual / 12;
    final currency = package.storeProduct.currencyCode;
    return '$currency${perMonth.toStringAsFixed(0)}/mo';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentSoft : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.accent : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppTheme.accent : AppTheme.inkHint,
                  width: isSelected ? 6 : 2,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? AppTheme.ink : AppTheme.inkSoft,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accentFg,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_perMonthPrice != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$_perMonthPrice — billed annually',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Price
            Text(
              package.storeProduct.priceString,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? AppTheme.ink : AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
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
          const Icon(Icons.wifi_off_outlined, size: 48, color: AppTheme.inkHint),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
