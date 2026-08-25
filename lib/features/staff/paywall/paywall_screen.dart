import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/revenue_cat_provider.dart';
import '../../../core/services/app_events.dart';
import '../../../core/services/revenue_cat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/platform_info.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import 'ios_custom_paywall.dart';

const _kWhatsAppUrl = 'https://wa.me/917541004076';

/// The gym's own numbers, shown at the top of the paywall so the subscribe
/// decision is framed against what the owner would lose rather than against a
/// feature list. Demo rows are excluded — quoting seeded sample data back to
/// the owner as "your gym" would be a lie, and the numbers are the whole point.
///
/// autoDispose: only ever read while the paywall is on screen.
final paywallGymStatsProvider =
    FutureProvider.autoDispose<Map<String, num>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
  final todayDate = now.toIso8601String().split('T')[0];
  final in7Days =
      now.add(const Duration(days: 7)).toIso8601String().split('T')[0];

  final counts =
      await Future.wait<PostgrestResponse<List<Map<String, dynamic>>>>([
    client
        .from('members')
        .select('id')
        .eq('gym_id', gymId)
        .eq('status', 'active')
        .eq('is_demo_data', false)
        .count(CountOption.exact),
    client
        .from('members')
        .select('id')
        .eq('gym_id', gymId)
        .eq('status', 'active')
        .eq('is_demo_data', false)
        .gte('next_payment_date', todayDate)
        .lte('next_payment_date', in7Days)
        .count(CountOption.exact),
  ]);

  // Cash actually collected this month — same source as the dashboard hero
  // (payments, not invoices) so a partial collection counts immediately.
  final payments = await client
      .from('payments')
      .select('amount, invoices!inner(gym_id, is_demo_data)')
      .eq('invoices.gym_id', gymId)
      .eq('invoices.is_demo_data', false)
      .eq('status', 'succeeded')
      .gte('created_at', startOfMonth);

  final collected = (payments as List).fold<double>(
    0,
    (s, r) => s + (((r as Map)['amount'] as num?)?.toDouble() ?? 0),
  );

  return {
    'members': counts[0].count,
    'renewals': counts[1].count,
    'collected': collected,
  };
});

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _loggedView = false;

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

    // Fired once per time the gate actually blocks access — not for
    // SubscriptionScreen, which renders the same body for an
    // already-subscribed owner voluntarily browsing Settings.
    if (!_loggedView && gym != null) {
      _loggedView = true;
      unawaited(AppEvents.paywallViewed());
      final isTrial = gym['trial_ends_at'] != null && gym['plan_expires_at'] == null;
      if (isTrial && _paywallStatus(gym).tone == _StatusTone.danger) {
        unawaited(AppEvents.trialExpired());
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('GymCRM Pro'),
        actions: [
          TextButton(
            onPressed: _signOut,
            child: const Text('Sign out', style: TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
          ),
        ],
      ),
      body: ResponsiveContent(child: _PlanBody(gym: gym)),
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
        body: ResponsiveContent(child: _IosActiveSubscription(gym: gym)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(child: _PlanBody(gym: gym)),
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
    final features = isLegacy ? _kLegacyFeatures : _kProFeatures;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaywallHero(gym: gym, features: features),
            const SizedBox(height: 24),
            if (isLegacy) _LegacyPricing(gym: gym) else _NewProPricing(gym: gym),
            const SizedBox(height: 22),
            const _TrustFooterRow(),
            const SizedBox(height: 10),
            const _WhatsAppFooterLink(),
          ],
        ),
      ),
    );
  }
}

// ── Hero: identity + status + value, one continuous surface ──────────────────

/// Everything that used to be three stacked containers (gym-stats card, a
/// colored status banner, a second dark feature-checklist card) merged into
/// one dark surface with hairline dividers between sections. Two near-identical
/// dark cards back to back read as an accident, not a decision — this is one.
class _PaywallHero extends ConsumerWidget {
  final Map<String, dynamic>? gym;
  final List<({IconData icon, String text})> features;
  const _PaywallHero({required this.gym, required this.features});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymName = (gym?['name'] as String?) ?? 'Your gym';
    final stats = ref.watch(paywallGymStatsProvider);

    // Network/DB failure must never blank the paywall — fall back to the pitch.
    final members = stats.valueOrNull?['members']?.toInt() ?? 0;
    final renewals = stats.valueOrNull?['renewals']?.toInt() ?? 0;
    final collected = stats.valueOrNull?['collected'] ?? 0;
    final hasData = members > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.darkCardDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gymName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppTheme.onDarkSoft,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasData
                ? 'Your gym is running\non GymCRM. Keep it that way.'
                : 'Everything your gym needs,\nin one app.',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.onDark,
              height: 1.18,
              letterSpacing: -0.4,
            ),
          ),
          if (hasData) ...[
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderStat(value: '$members', label: 'members'),
                _HeaderStat(
                  value: formatCurrencyCompact(collected),
                  label: 'collected this month',
                ),
                if (renewals > 0)
                  _HeaderStat(
                    value: '$renewals',
                    label: 'renewals due',
                    valueColor: const Color(0xFFEF8B72),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Text(
              'Members, fees, dues and check-ins — stop running your gym from a register.',
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.onDarkSoft,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 22),
          _HeroDivider(),
          const SizedBox(height: 18),
          _HeroStatusRow(gym: gym),
          const SizedBox(height: 22),
          _HeroDivider(),
          const SizedBox(height: 18),
          ...features.map((f) => Padding(
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
              )),
        ],
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.08));
}

class _HeaderStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  const _HeaderStat({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTheme.numberStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: valueColor ?? AppTheme.onDark,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.onDarkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status logic (shared) ─────────────────────────────────────────────────────

enum _StatusTone { active, warn, danger }

typedef _StatusInfo = ({IconData icon, String message, _StatusTone tone});

/// Pure trial/active/expired branching, used by both the light standalone
/// banner (iOS "already subscribed" screen) and the dark hero's inline status
/// row. One source of truth for the copy and the conditions — only the two
/// presentational leaves differ.
_StatusInfo _paywallStatus(Map<String, dynamic>? gym) {
  final now = DateTime.now().toUtc();
  final plan = gym?['plan'] as String?;
  final planExpiresAt = gym?['plan_expires_at'] as String?;
  final trialEndsAt = gym?['trial_ends_at'] as String?;
  final dodoId = gym?['dodo_subscription_id'] as String?;

  final hasExpiry = planExpiresAt != null &&
      (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
  final isActive = (plan == 'pro' && planExpiresAt == null) ||
      (dodoId != null && hasExpiry) ||
      hasExpiry;

  if (isActive) {
    // Only 'pro' is a real paid plan name — anything else (e.g. 'starter')
    // reaching this branch is a trial row with a stray plan_expires_at, so
    // don't print the raw plan string.
    final planName = plan == 'pro' ? 'Pro' : 'Active';
    String sub = 'You have an active $planName plan.';
    if (planExpiresAt != null) {
      final exp = DateTime.tryParse(planExpiresAt)?.toLocal();
      if (exp != null) {
        sub = 'Active $planName plan · renews '
            '${exp.day}/${exp.month}/${exp.year}';
      }
    }
    return (icon: Icons.check_circle_outline, message: sub, tone: _StatusTone.active);
  }

  // Trial active — iOS has no trial, so skip straight to the paywall message.
  // ceil(), not .inDays: 23h left on a 24h trial is "1 day left", not "0".
  final trialEnd = trialEndsAt != null ? DateTime.tryParse(trialEndsAt)?.toUtc() : null;
  final trialDiff = trialEnd?.difference(now);
  final daysLeft = (trialDiff != null && !trialDiff.isNegative) ? (trialDiff.inHours / 24).ceil() : null;
  if (!isIOS && daysLeft != null) {
    return (
      icon: Icons.access_time_outlined,
      message: daysLeft == 1
          ? 'Your free trial ends tomorrow. Subscribe now and nothing changes.'
          : 'Your free trial ends in $daysLeft days. Subscribe now and nothing changes.',
      tone: _StatusTone.warn,
    );
  }

  // Expired / no subscription
  return (
    icon: Icons.lock_outline,
    message: isIOS
        ? 'Subscribe to unlock your gym.'
        : 'Your free trial has ended. Your members and payment history are '
            'safe — subscribe to get back in.',
    tone: _StatusTone.danger,
  );
}

/// Inline status line inside the dark hero. Two-tone only — mint for "all
/// good", the same coral already used for "renewals due" above for anything
/// that needs attention — so the whole hero signals with one closed palette
/// instead of borrowing the light-mode amber/red pair, which loses contrast
/// on a dark surface.
class _HeroStatusRow extends StatelessWidget {
  final Map<String, dynamic>? gym;
  const _HeroStatusRow({required this.gym});

  @override
  Widget build(BuildContext context) {
    final info = _paywallStatus(gym);
    final color = info.tone == _StatusTone.active
        ? AppTheme.mintOnDark
        : const Color(0xFFEF8B72);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(info.icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            info.message,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Standalone light-card version — the only place this still renders on its
/// own is the iOS "you're already subscribed" management screen, which sits
/// on the cream background, not inside a dark hero.
class _StatusBanner extends StatelessWidget {
  final Map<String, dynamic>? gym;
  const _StatusBanner({required this.gym});

  @override
  Widget build(BuildContext context) {
    final info = _paywallStatus(gym);
    final (bg, fg) = switch (info.tone) {
      _StatusTone.active => (AppTheme.statusActiveBg, AppTheme.statusActive),
      _StatusTone.warn => (AppTheme.statusWarnBg, AppTheme.statusWarn),
      _StatusTone.danger => (AppTheme.statusDangerBg, AppTheme.statusDanger),
    };
    return _Banner(icon: info.icon, message: info.message, color: bg, textColor: fg);
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

// ── Trust row (footer, unboxed) ───────────────────────────────────────────────

class _TrustFooterRow extends StatelessWidget {
  const _TrustFooterRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.close_rounded, text: 'Cancel anytime — no lock-in'),
      (icon: Icons.lock_outline, text: 'Your member data is never deleted, even if you cancel'),
    ];

    return Column(
      children: items
          .map((i) => Padding(
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
              ))
          .toList(),
    );
  }
}

// ── Legacy (₹249/mo grandfathered) pricing: adds 3/6/12mo terms ──────────────

const _kLegacyFeatures = [
  (icon: Icons.groups_outlined, text: 'Unlimited members & check-ins'),
  (icon: Icons.badge_outlined, text: 'Unlimited staff logins & roles'),
  (icon: Icons.mail_outline, text: 'Automatic email due reminders'),
  (icon: Icons.chat_bubble_outline, text: 'WhatsApp due reminders'),
  (icon: Icons.show_chart_rounded, text: 'Advanced reports & analytics'),
  (icon: Icons.event_outlined, text: 'Class scheduling & bookings'),
  (icon: Icons.person_add_alt_1_outlined, text: 'Leads & CRM'),
  (icon: Icons.qr_code_2_rounded, text: 'Member portal & QR check-in'),
  (icon: Icons.support_agent_outlined, text: 'Priority support'),
];

// Multi-month terms at legacy gyms' locked-in ₹249/mo rate, same 7/12/20%
// discount curve as _kProTerms. Dodo products: pdt_0NlI9s2bexR61Mzwwegj9 (3mo),
// pdt_0NlIA0KQM7ZEHFNmfFNmw (6mo), pdt_0NlIDT6RzXCRV4YNUXYwN (12mo) — checkout
// backend must map these against legacy_pricing gyms same way it already does
// for the 1mo legacy_dodo_product_id.
const _kLegacyMultiMonthTerms = [
  _TermOption('3mo', '3 Months', 694, 3, discountPct: 7),
  _TermOption('6mo', '6 Months', 1315, 6, discountPct: 12),
  _TermOption('12mo', '12 Months', 2390, 12, discountPct: 20, badge: '2 months free'),
];

class _LegacyPricing extends StatefulWidget {
  final Map<String, dynamic>? gym;
  const _LegacyPricing({required this.gym});

  @override
  State<_LegacyPricing> createState() => _LegacyPricingState();
}

class _LegacyPricingState extends State<_LegacyPricing> {
  String _selectedTerm = '1mo';

  @override
  Widget build(BuildContext context) {
    final monthlyPrice = widget.gym?['plan_price'] as int? ?? 249;
    final terms = [
      _TermOption('1mo', '1 Month', monthlyPrice, 1),
      ..._kLegacyMultiMonthTerms,
    ];
    final selected = terms.firstWhere((t) => t.id == _selectedTerm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DurationSegmented(
          terms: terms,
          selected: _selectedTerm,
          onChanged: (id) => setState(() => _selectedTerm = id),
        ),
        const SizedBox(height: 14),
        _PricePanel(term: selected),
        const SizedBox(height: 16),
        _UpgradeButton(gym: widget.gym, term: _selectedTerm),
      ],
    );
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
  _TermOption('12mo', '12 Months', 4799, 12, discountPct: 20, badge: '2 months free'),
];

// Elite is hidden until plan gating is enforced. Do not delete.
// No 3mo Elite product exists in Dodo yet — omitted here rather than showing
// a term that would 503 at checkout.
// ignore: unused_element
const _kEliteTerms = [
  _TermOption('1mo', '1 Month', 999, 1),
  _TermOption('6mo', '6 Months', 5299, 6, discountPct: 12),
  _TermOption('12mo', '12 Months', 9599, 12, discountPct: 20, badge: 'Best Value'),
];

// Benefit-first, in the order a gym owner cares about: money he is losing,
// time he is wasting, then everything else. Plan limits still apply but belong
// in the fine print, not in the pitch.
const _kProFeatures = [
  (icon: Icons.chat_bubble_outline, text: 'We WhatsApp your members before their fees are due — automatically'),
  (icon: Icons.account_balance_wallet_outlined, text: 'Know exactly who owes you money, today'),
  (icon: Icons.show_chart_rounded, text: 'See what you collected this month without opening a register'),
  (icon: Icons.qr_code_2_rounded, text: 'Members check in by QR — works even when your internet doesn\'t'),
  (icon: Icons.person_add_alt_1_outlined, text: 'Never lose a walk-in enquiry again'),
  (icon: Icons.badge_outlined, text: 'Your staff get their own logins, with only the access you allow'),
  (icon: Icons.layers_outlined, text: 'Up to 500 members, 4 staff logins, 300 WhatsApp reminders a month'),
];

// Elite is hidden until plan gating is enforced. Do not delete.
// ignore: unused_element
const _kEliteFeatures = [
  (icon: Icons.groups_outlined, text: 'Unlimited members & check-ins'),
  (icon: Icons.badge_outlined, text: 'Unlimited staff logins & roles'),
  (icon: Icons.mail_outline, text: 'Automatic email due reminders'),
  (icon: Icons.chat_bubble_outline, text: '1,500 free WhatsApp due reminders/month'),
  (icon: Icons.show_chart_rounded, text: 'Advanced reports & analytics'),
  (icon: Icons.event_outlined, text: 'Class scheduling & bookings'),
  (icon: Icons.person_add_alt_1_outlined, text: 'Leads & CRM'),
  (icon: Icons.qr_code_2_rounded, text: 'Member portal & QR check-in'),
  (icon: Icons.support_agent_outlined, text: 'Priority support'),
];

class _NewProPricing extends StatefulWidget {
  final Map<String, dynamic>? gym;
  const _NewProPricing({required this.gym});

  @override
  State<_NewProPricing> createState() => _NewProPricingState();
}

class _NewProPricingState extends State<_NewProPricing> {
  // Monthly by default. Annual (₹4,799) used to be pre-selected, which asks a
  // gym owner for a year up front at the exact moment he is least convinced.
  // Longer terms stay available in the segmented selector as an upsell, not
  // as the default ask.
  String _selectedTerm = '1mo';

  List<_TermOption> get _terms => _kProTerms;

  @override
  Widget build(BuildContext context) {
    final selected = _terms.firstWhere((t) => t.id == _selectedTerm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DurationSegmented(
          terms: _terms,
          selected: _selectedTerm,
          onChanged: (id) => setState(() => _selectedTerm = id),
        ),
        const SizedBox(height: 14),
        _PricePanel(term: selected),
        const SizedBox(height: 16),
        _UpgradeButton(gym: widget.gym, plan: 'pro', term: _selectedTerm),
      ],
    );
  }
}

// Elite is hidden until plan gating is enforced. Do not delete.
// ignore: unused_element
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

// Elite is hidden until plan gating is enforced. Do not delete.
// ignore: unused_element
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

// ── Duration selector ─────────────────────────────────────────────────────────

/// Reuses the app's own pill-toggle idiom (see login screen's Staff/Member
/// switch) instead of inventing a new interaction — four stacked bordered
/// radio-cards read as a form; a segmented selector reads as a choice already
/// made for you, which is the more confident framing on a paywall.
class _DurationSegmented extends StatelessWidget {
  final List<_TermOption> terms;
  final String selected;
  final ValueChanged<String> onChanged;
  const _DurationSegmented({required this.terms, required this.selected, required this.onChanged});

  static String _shortLabel(_TermOption t) => switch (t.months) {
        1 => '1 mo',
        3 => '3 mo',
        6 => '6 mo',
        12 => '1 yr',
        _ => t.label,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: terms.map((t) {
          final isSelected = t.id == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(t.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _shortLabel(t),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? AppTheme.accentFg : AppTheme.ink,
                      ),
                    ),
                    if (t.discountPct != null)
                      Text(
                        '${t.discountPct}% off',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppTheme.accentFg.withValues(alpha: 0.75)
                              : AppTheme.inkHint,
                        ),
                      ),
                  ],
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

/// The single focal price for whichever term is selected — replaces four
/// near-identical stacked cards with one panel that gets bigger and more
/// legible the moment it's the only price on screen.
class _PricePanel extends StatelessWidget {
  final _TermOption term;
  const _PricePanel({required this.term});

  @override
  Widget build(BuildContext context) {
    final perMonth = (term.totalPrice / term.months).round();
    final isMonthly = term.months == 1;

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
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${term.totalPrice}',
                    style: AppTheme.numberStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppTheme.ink),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      isMonthly ? '/ month' : 'for ${term.label.toLowerCase()}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.inkSoft),
                    ),
                  ),
                ],
              ),
              if (term.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    term.badge!,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isMonthly
                ? 'Less than one member\'s monthly fee.'
                : '₹$perMonth/mo · ${term.discountPct ?? 0}% cheaper than paying monthly.',
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── WhatsApp help (footer) ────────────────────────────────────────────────────

/// Was a full "Contact us for pricing" card sitting directly under the prices,
/// which told every visitor the listed price was negotiable and routed buyers
/// into a manual sales conversation. Demoted to a plain footer link: still an
/// escape hatch for people who genuinely need one, no longer the easier path
/// than paying.
class _WhatsAppFooterLink extends StatelessWidget {
  const _WhatsAppFooterLink();

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
    return Center(
      child: TextButton(
        onPressed: () => _openWhatsApp(context),
        child: const Text(
          'Need help choosing? Talk to us',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.inkSoft,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.inkHint,
          ),
        ),
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
        body: jsonEncode({
          'plan': widget.plan,
          'term': widget.term,
          'platform': kIsWeb ? 'web' : 'mobile',
        }),
      );

      if (response.statusCode != 200) {
        final message = response.statusCode == 422
            ? ((jsonDecode(response.body) as Map<String, dynamic>)['error'] as String? ??
                'Could not change plan.')
            : 'Could not start checkout. Please try again.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (url == null) {
        // Plan changed on the existing subscription directly — no checkout redirect.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan updated.')),
          );
        }
        ref.invalidate(staffProfileProvider);
        return;
      }

      // Fired here, not on tap — this is the actual hand-off to an external
      // Custom Tab the funnel audit flagged as an unmeasured drop-off point.
      // Comparing this against purchase volume is what measures it.
      unawaited(AppEvents.checkoutStarted());

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

  /// Names the price so the button restates the commitment instead of the
  /// generic "Upgrade to Pro" it used to say. Mirrors the term lists the two
  /// pricing bodies render, including the legacy gym's locked-in 1mo rate.
  String get _ctaLabel {
    final isLegacy = widget.gym?['legacy_pricing'] == true;
    final terms = isLegacy
        ? [
            _TermOption('1mo', '1 Month',
                widget.gym?['plan_price'] as int? ?? 249, 1),
            ..._kLegacyMultiMonthTerms,
          ]
        : _kProTerms;
    final match = terms.where((t) => t.id == widget.term);
    if (match.isEmpty) return 'Subscribe';
    return 'Subscribe · ₹${match.first.totalPrice}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.gym?['plan'] as String?;
    final planExpiresAt = widget.gym?['plan_expires_at'] as String?;
    final now = DateTime.now().toUtc();
    final hasExpiry = planExpiresAt != null &&
        (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
    final isActive = (plan == 'pro' && planExpiresAt == null) || hasExpiry;

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
            : Text(
                isActive ? 'Change plan' : _ctaLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
      ),
    );
  }
}
