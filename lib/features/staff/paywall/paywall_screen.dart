import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/revenue_cat_provider.dart';
import '../../../core/services/revenue_cat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../auth/providers/auth_provider.dart';
import 'ios_custom_paywall.dart';

const _kWhatsAppUrl = 'https://wa.me/917541004076';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: AppTheme.statusDanger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authNotifierProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(staffProfileProvider);
    final gym = profileAsync.valueOrNull?['gyms'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Choose a Plan'),
        actions: [
          TextButton(
            onPressed: _signOut,
            child: const Text('Sign out', style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
          ),
        ],
      ),
      body: _PlanBody(gym: gym),
    );
  }
}

// ── Subscription screen (accessed from Settings while still active) ───────────

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(staffProfileProvider);
    final gym = profileAsync.valueOrNull?['gyms'] as Map<String, dynamic>?;

    // On iOS, show the RC customer center directly from Settings.
    if (isIOS) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Subscription'),
          leading: const BackButton(),
        ),
        body: _IosActiveSubscription(gym: gym),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        leading: const BackButton(),
      ),
      body: _PlanBody(gym: gym),
    );
  }
}

// ── Shared plan body ──────────────────────────────────────────────────────────

class _PlanBody extends StatelessWidget {
  final Map<String, dynamic>? gym;

  const _PlanBody({required this.gym});

  @override
  Widget build(BuildContext context) {
    if (isIOS) {
      return _IosPaywall(gym: gym);
    }

    final isLegacy = gym?['legacy_pricing'] == true;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(gym: gym),
            const SizedBox(height: 24),
            if (isLegacy) ..._legacyPro(gym) else _NewProPricing(gym: gym),
            const SizedBox(height: 24),
            _ContactForPricing(),
          ],
        ),
      ),
    );
  }

  List<Widget> _legacyPro(Map<String, dynamic>? gym) {
    final price = gym?['plan_price'] as int? ?? 249;
    return [
      _PlanCard(
        name: 'Pro',
        highlighted: true,
        price: '₹$price/mo',
        features: const [
          'Unlimited members & check-ins',
          'Unlimited staff logins & roles',
          'Automatic email due reminders',
          'WhatsApp due reminders',
          'Advanced reports & analytics',
          'Class scheduling & bookings',
          'Leads & CRM',
          'Member portal & QR check-in',
          'Priority support',
        ],
      ),
      const SizedBox(height: 16),
      _UpgradeButton(gym: gym, term: '1mo'),
    ];
  }
}

// ── iOS: RevenueCat paywall + subscription management ─────────────────────────

class _IosPaywall extends ConsumerWidget {
  final Map<String, dynamic>? gym;
  const _IosPaywall({required this.gym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerInfoAsync = ref.watch(customerInfoProvider);
    final hasAccess = customerInfoAsync.valueOrNull?.entitlements.active
            .containsKey(kRcEntitlement) ??
        false;

    // Loading RC customer info — show blank to avoid flash.
    if (customerInfoAsync.isLoading && !customerInfoAsync.hasValue) {
      return const Scaffold(backgroundColor: AppTheme.background);
    }

    // Active subscription → show status + manage options.
    if (hasAccess) {
      return _IosActiveSubscription(gym: gym);
    }

    // No active subscription → show custom paywall with StoreKit IAP.
    // Sign out is handled by PaywallScreen's AppBar action above.
    return const IosCustomPaywall();
  }
}

// ── Active subscription screen (iOS) ─────────────────────────────────────────

class _IosActiveSubscription extends StatelessWidget {
  final Map<String, dynamic>? gym;
  const _IosActiveSubscription({required this.gym});

  Future<void> _openCustomerCenter() async {
    await RevenueCatUI.presentCustomerCenter();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(gym: gym),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Subscription',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'View billing history, cancel, or restore purchases.',
                    style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _openCustomerCenter,
                    icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                    label: const Text('Manage subscription'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final Map<String, dynamic>? gym;
  const _StatusBanner({required this.gym});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final plan = gym?['plan'] as String?;
    final planExpiresAt = gym?['plan_expires_at'] as String?;
    final trialEndsAt = gym?['trial_ends_at'] as String?;
    final dodoId = gym?['dodo_subscription_id'] as String?;

    // Active subscription
    final hasExpiry = planExpiresAt != null &&
        (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
    final isActive = (plan == 'pro' && planExpiresAt == null) ||
        (dodoId != null && hasExpiry) ||
        hasExpiry;

    if (isActive) {
      final planName = plan != null
          ? plan[0].toUpperCase() + plan.substring(1)
          : 'Active';
      String sub = 'You have an active $planName plan.';
      if (planExpiresAt != null) {
        final exp = DateTime.tryParse(planExpiresAt)?.toLocal();
        if (exp != null) {
          sub = 'Active $planName plan · renews '
              '${exp.day}/${exp.month}/${exp.year}';
        }
      }
      return _Banner(
        icon: Icons.check_circle_outline,
        message: sub,
        color: AppTheme.statusActiveBg,
        textColor: AppTheme.statusActive,
      );
    }

    // Trial active — iOS has no trial, so skip straight to the paywall message.
    final daysLeft = trialEndsAt != null
        ? DateTime.tryParse(trialEndsAt)?.toUtc().difference(now).inDays
        : null;
    if (!isIOS && daysLeft != null && daysLeft > 0) {
      return _Banner(
        icon: Icons.access_time_outlined,
        message: 'Your free trial ends in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}.',
        color: AppTheme.statusWarnBg,
        textColor: AppTheme.statusWarn,
      );
    }

    // Expired / no subscription
    return _Banner(
      icon: Icons.lock_outline,
      message: isIOS
          ? 'Subscribe to continue using GymCRM.'
          : 'Your free trial has ended. Subscribe to continue using GymCRM.',
      color: AppTheme.statusDangerBg,
      textColor: AppTheme.statusDanger,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Color textColor;

  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final String name;
  final List<String> features;
  final bool highlighted;
  final String? price;

  const _PlanCard({
    required this.name,
    required this.features,
    this.highlighted = false,
    this.price,
  });

  @override
  Widget build(BuildContext context) {
    if (!highlighted) {
      // Secondary (non-featured) plan keeps a light card.
      return Container(
        decoration: AppTheme.cardDecoration(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              if (price != null) ...[
                const Spacer(),
                Text(price!, style: AppTheme.numberStyle(fontSize: 15)),
              ],
            ]),
            const SizedBox(height: 14),
            ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check, size: 16, color: AppTheme.statusActive),
                const SizedBox(width: 10),
                Expanded(child: Text(f, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft))),
              ]),
            )),
          ],
        ),
      );
    }

    // Featured plan: deep green-black card, mint launch badge, big price.
    return Container(
      decoration: AppTheme.darkCardDecoration(radius: 22),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF7FD6A2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              name.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Color(0xFF12291B)),
            ),
          ),
          if (price != null) ...[
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(price!, style: AppTheme.numberStyle(fontSize: 40, color: AppTheme.onDark, height: 1)),
            ]),
            const SizedBox(height: 8),
            const Text('Flat. No per-member fees. Cancel anytime.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.onDarkSoft)),
          ],
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check, size: 16, color: AppTheme.mintOnDark),
              const SizedBox(width: 10),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 13.5, color: AppTheme.onDark))),
            ]),
          )),
        ],
      ),
    );
  }
}

// ── New-customer Pro pricing: 4 billing terms ─────────────────────────────────

class _TermOption {
  final String id;
  final String label;
  final int totalPrice;
  final int months;
  final int? discountPct;
  final String? badge;

  const _TermOption(this.id, this.label, this.totalPrice, this.months,
      {this.discountPct, this.badge});
}

const _kProTerms = [
  _TermOption('1mo', '1 Month', 499, 1),
  _TermOption('3mo', '3 Months', 1399, 3, discountPct: 7),
  _TermOption('6mo', '6 Months', 2599, 6, discountPct: 12),
  _TermOption('12mo', '12 Months', 4799, 12, discountPct: 20, badge: 'Best Value'),
];

// No 3mo Elite product exists in Dodo yet — omitted here rather than showing
// a term that would 503 at checkout.
const _kEliteTerms = [
  _TermOption('1mo', '1 Month', 999, 1),
  _TermOption('6mo', '6 Months', 5299, 6, discountPct: 12),
  _TermOption('12mo', '12 Months', 9599, 12, discountPct: 20, badge: 'Best Value'),
];

const _kProFeatures = [
  'Up to 500 members & check-ins',
  'Up to 33 staff logins & roles',
  'Automatic email due reminders',
  '500 free WhatsApp due reminders/month',
  'Advanced reports & analytics',
  'Class scheduling & bookings',
  'Leads & CRM',
  'Member portal & QR check-in',
  'Priority support',
];

const _kEliteFeatures = [
  'Unlimited members & check-ins',
  'Unlimited staff logins & roles',
  'Automatic email due reminders',
  '1,500 free WhatsApp due reminders/month',
  'Advanced reports & analytics',
  'Class scheduling & bookings',
  'Leads & CRM',
  'Member portal & QR check-in',
  'Priority support',
];

class _NewProPricing extends StatefulWidget {
  final Map<String, dynamic>? gym;
  const _NewProPricing({required this.gym});

  @override
  State<_NewProPricing> createState() => _NewProPricingState();
}

class _NewProPricingState extends State<_NewProPricing> {
  String _tier = 'pro';
  String _selectedTerm = '1mo';

  List<_TermOption> get _terms => _tier == 'pro' ? _kProTerms : _kEliteTerms;

  void _selectTier(String tier) {
    if (tier == _tier) return;
    setState(() {
      _tier = tier;
      _selectedTerm = (tier == 'pro' ? _kProTerms : _kEliteTerms).first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TierToggle(tier: _tier, onChanged: _selectTier),
        const SizedBox(height: 16),
        _PlanCard(
          name: _tier == 'pro' ? 'Pro' : 'Elite',
          highlighted: true,
          features: _tier == 'pro' ? _kProFeatures : _kEliteFeatures,
        ),
        const SizedBox(height: 16),
        ..._terms.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TermCard(
                term: t,
                isSelected: _selectedTerm == t.id,
                onTap: () => setState(() => _selectedTerm = t.id),
              ),
            )),
        const SizedBox(height: 8),
        _UpgradeButton(gym: widget.gym, plan: _tier, term: _selectedTerm),
      ],
    );
  }
}

class _TierToggle extends StatelessWidget {
  final String tier;
  final ValueChanged<String> onChanged;
  const _TierToggle({required this.tier, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(child: _TierTab(label: 'Pro', selected: tier == 'pro', onTap: () => onChanged('pro'))),
          Expanded(child: _TierTab(label: 'Elite', selected: tier == 'elite', onTap: () => onChanged('elite'))),
        ],
      ),
    );
  }
}

class _TierTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TierTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? AppTheme.accentFg : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  final _TermOption term;
  final bool isSelected;
  final VoidCallback onTap;

  const _TermCard({required this.term, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final perMonth = (term.totalPrice / term.months).round();
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentSoft : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 20,
              height: 20,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      term.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppTheme.ink : AppTheme.inkSoft,
                      ),
                    ),
                    if (term.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          term.badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentFg,
                          ),
                        ),
                      ),
                    ],
                  ]),
                  if (term.discountPct != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '₹$perMonth/mo · ${term.discountPct}% off',
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '₹${term.totalPrice}',
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

// ── Contact for pricing ───────────────────────────────────────────────────────

class _ContactForPricing extends StatelessWidget {
  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(_kWhatsAppUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact us for pricing',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
          const SizedBox(height: 6),
          const Text(
            'Reach out to our support team on WhatsApp to get the right plan for your gym and discuss pricing.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _openWhatsApp(context),
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('Chat on WhatsApp'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upgrade button (Android — Dodo checkout via Custom Tab) ──────────────────

class _UpgradeButton extends ConsumerStatefulWidget {
  final Map<String, dynamic>? gym;
  final String plan;
  final String term;
  const _UpgradeButton({required this.gym, this.plan = 'pro', required this.term});

  @override
  ConsumerState<_UpgradeButton> createState() => _UpgradeButtonState();
}

class _UpgradeButtonState extends ConsumerState<_UpgradeButton>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _checkoutInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fallback for when the gymcrm://payment-success deep link doesn't fire
    // (some OEM Chrome builds drop the redirect) — re-check plan status
    // whenever the app resumes from a checkout attempt.
    if (state == AppLifecycleState.resumed && _checkoutInProgress) {
      _checkoutInProgress = false;
      ref.invalidate(staffProfileProvider);
    }
  }

  Future<void> _upgrade() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse('https://www.gymcrm.in/api/billing/mobile/checkout'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'plan': widget.plan, 'term': widget.term}),
      );

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start checkout. Please try again.')),
          );
        }
        return;
      }

      final url = (jsonDecode(response.body) as Map<String, dynamic>)['url'] as String?;
      if (url == null) return;

      _checkoutInProgress = true;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start checkout. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.gym?['plan'] as String?;
    final planExpiresAt = widget.gym?['plan_expires_at'] as String?;
    final now = DateTime.now().toUtc();
    final hasExpiry = planExpiresAt != null &&
        (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
    final isActive = (plan == 'pro' && planExpiresAt == null) || hasExpiry;

    if (isActive) return const SizedBox.shrink();

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : _upgrade,
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                'Upgrade to Pro',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
      ),
    );
  }
}
