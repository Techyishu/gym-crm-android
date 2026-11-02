import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/app_config_provider.dart';
import '../../../core/providers/revenue_cat_provider.dart';
import '../../../core/services/app_events.dart';
import '../../../core/services/revenue_cat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/utils/validators.dart' show gymCountry;
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import 'cancel_subscription_screen.dart';
import 'ios_custom_paywall.dart';
import '../../../core/theme/app_icons.dart';

const kSupportWhatsAppUrl = 'https://wa.me/917541004076';

/// "Talk to us" link: app_config.support_whatsapp when set, else the default.
String supportWhatsAppUrl(WidgetRef ref) {
  final n = ref.watch(appConfigProvider).valueOrNull?['support_whatsapp'];
  return n is String && n.isNotEmpty ? 'https://wa.me/$n' : kSupportWhatsAppUrl;
}

/// Where checkout lives. Override for local testing against a gym-crm dev
/// server: --dart-define=API_BASE=http://localhost:3000. Release builds never
/// pass it, so they keep hitting production.
const kBillingApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://www.gymcrm.in',
);

/// Prices, terms and offers come from the database (get_paywall_pricing — the
/// gym's locked plan or the current default, plus any offer), never from
/// constants here. Checkout bills from the same tables, so the price shown and
/// the price charged can't drift apart. Keyed by the typed coupon ('' = none).
final paywallPricingProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, coupon) async {
      final res = await Supabase.instance.client.rpc(
        'get_paywall_pricing',
        params: {'p_coupon': coupon.isEmpty ? null : coupon},
      );
      return Map<String, dynamic>.from(res as Map);
    });

/// The gym's own numbers, shown at the top of the paywall so the subscribe
/// decision is framed against what the owner would lose rather than against a
/// feature list. Demo rows are excluded — quoting seeded sample data back to
/// the owner as "your gym" would be a lie, and the numbers are the whole point.
///
/// autoDispose: only ever read while the paywall is on screen.
final paywallGymStatsProvider = FutureProvider.autoDispose<Map<String, num>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
  final todayDate = now.toIso8601String().split('T')[0];
  final in7Days = now
      .add(const Duration(days: 7))
      .toIso8601String()
      .split('T')[0];

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
    final notifier = ref.read(authNotifierProvider.notifier);
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out?',
      body: 'You can sign back in anytime.',
      confirmLabel: 'Sign out',
      icon: AppIcons.logout,
    );
    if (ok == true) {
      await notifier.signOut();
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
      final isTrial =
          gym['trial_ends_at'] != null && gym['plan_expires_at'] == null;
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
            child: const Text(
              'Sign out',
              style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
            ),
          ),
        ],
      ),
      body: ResponsiveContent(child: _PlanBody(gym: gym)),
    );
  }
}

// ── Subscription screen (accessed from Settings while still active) ───────────

class SubscriptionScreen extends ConsumerStatefulWidget {
  /// Plan length to pre-select ('1mo' / '3mo' / '6mo' / '12mo'), e.g. from an
  /// offer popup linking to /staff/subscription?term=12mo.
  final String? initialTerm;
  const SubscriptionScreen({super.key, this.initialTerm});

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
      body: ResponsiveContent(
        child: _PlanBody(gym: gym, initialTerm: widget.initialTerm),
      ),
    );
  }
}

// ── Shared plan body ──────────────────────────────────────────────────────────

class _PlanBody extends ConsumerStatefulWidget {
  final Map<String, dynamic>? gym;
  final String? initialTerm;

  const _PlanBody({required this.gym, this.initialTerm});

  @override
  ConsumerState<_PlanBody> createState() => _PlanBodyState();
}

class _PlanBodyState extends ConsumerState<_PlanBody> {
  // Tier lives here rather than inside the pricing widget so the hero's
  // benefit list follows the toggle. A hero promising "unlimited members"
  // while Starter is selected is the kind of mismatch that gets refunded.
  String _tier = 'pro';
  String _coupon = '';

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    if (isIOS) {
      return _IosPaywall(gym: gym);
    }

    final isLegacy = gym?['legacy_pricing'] == true;
    // Not symmetric on purpose: a Pro subscriber must never be shown Starter
    // — there's nowhere for that tap to go but a downgrade, which the backend
    // 422s anyway (checkout/route.ts compares per-month price). A Starter
    // subscriber, on the other hand, SHOULD land on Pro here — that's the
    // upgrade we want them looking at, not a toggle back to the plan they're
    // already on. So: once a gym has active billing, this screen always
    // shows Pro, on both sides of that divide, and the toggle itself is
    // hidden — there is nothing left for it to switch between.
    final isActive = _paywallStatus(gym).tone == _StatusTone.active;
    final effectiveTier = (!_kStarterTierEnabled || isActive) ? 'pro' : _tier;
    // The reminder allowance of the plan on sale (₹299 Pro: 100, ₹499: 300),
    // straight from get_paywall_pricing, so the pitch matches what they get.
    final proQuota =
        (ref
                    .watch(paywallPricingProvider(_coupon))
                    .valueOrNull?['plans']?['pro']?['whatsapp_quota']
                as num?)
            ?.toInt();
    // Automatic WhatsApp is India-only, so gyms elsewhere aren't sold it.
    final india = gymCountry == 'IN';
    final features = isLegacy
        ? _kLegacyFeatures
        : effectiveTier == 'starter'
        ? _kStarterFeatures
        : [
            ..._kProFeatures.where(
              (f) => india || !f.text.contains('WhatsApp'),
            ),
            if (proQuota != null && india)
              (
                icon: AppIcons.layers,
                text: context.l10n.paywallLimitsLine(proQuota),
              )
            else if (!india)
              (
                icon: AppIcons.layers,
                text: 'Unlimited members and staff logins',
              ),
          ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaywallHero(gym: gym, features: features),
            const SizedBox(height: 24),
            _DbPricing(
              gym: gym,
              initialTerm: widget.initialTerm,
              tier: effectiveTier,
              showTierToggle: _kStarterTierEnabled && !isActive,
              onTierChanged: (t) => setState(() => _tier = t),
              coupon: _coupon,
              onCouponChanged: (c) => setState(() => _coupon = c),
            ),
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

// ── Hero: identity + status + value, on the app's own canvas ─────────────────

/// Was one 24px-padded dark slab carrying four unrelated jobs at once —
/// identity, headline, stats, status and the feature list — which read as a
/// wall, sat as the heaviest object on a cream page, and pushed the price
/// below the fold. Now: status first (it's the urgency), headline on the bare
/// canvas, proof as a hairline stat strip, and only the feature list earns a
/// surface of its own.
///
/// Depth is hairline borders only — no shadows, no gradients, no second card
/// competing with the price panel below.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroStatusRow(gym: gym),
        const SizedBox(height: 24),
        Text(
          gymName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: AppTheme.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hasData
              ? 'Your gym already runs\non GymCRM.'
              : 'Everything your gym needs,\nin one app.',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
            height: 1.12,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasData
              ? 'Keep it that way — pick a plan below.'
              : 'Members, fees, dues and check-ins — stop running your gym '
                    'from a register.',
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.inkSoft,
            height: 1.45,
          ),
        ),
        // The gym's own numbers are the strongest argument on this screen, so
        // they sit on the canvas as a hairline strip rather than inside yet
        // another container.
        if (hasData) ...[
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.border),
                bottom: BorderSide(color: AppTheme.border),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderStat(value: '$members', label: 'members'),
                  const _StatRule(),
                  _HeaderStat(
                    value: formatCurrencyCompact(collected),
                    label: 'collected this month',
                  ),
                  if (renewals > 0) ...[
                    const _StatRule(),
                    _HeaderStat(
                      value: '$renewals',
                      label: 'renewals due',
                      valueColor: AppTheme.statusDanger,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _FeatureList(features: features),
      ],
    );
  }
}

/// Hairline between stat columns — the only separator in the hero, so the
/// numbers group without a box around them.
class _StatRule extends StatelessWidget {
  const _StatRule();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(horizontal: 14),
    color: AppTheme.border,
  );
}

/// The one surface in the hero. White on cream with a hairline edge, so it
/// reads as a distinct object without the weight of the old dark panel.
class _FeatureList extends StatelessWidget {
  final List<({IconData icon, String text})> features;
  const _FeatureList({required this.features});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < features.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: i == features.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tinted square keeps the icons reading as one set at small
                  // sizes; a bare 17px glyph on white got lost next to the text.
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      features[i].icon,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        features[i].text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  const _HeaderStat({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTheme.numberStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: valueColor ?? AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
          ),
        ],
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

  final hasExpiry =
      planExpiresAt != null &&
      (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
  final isActive =
      (plan == 'pro' && planExpiresAt == null) ||
      (dodoId != null && hasExpiry) ||
      hasExpiry;

  if (isActive) {
    // 'starter' and 'pro' are both real paid plan names now — capitalize
    // either. Anything else that somehow reaches this branch (a stray
    // plan_expires_at on a trial row) falls back to the generic label rather
    // than printing a raw plan string.
    final planName = switch (plan) {
      'starter' => 'Starter',
      'pro' => 'Pro',
      _ => 'Active',
    };
    String sub = 'You have an active $planName plan.';
    if (planExpiresAt != null) {
      final exp = DateTime.tryParse(planExpiresAt)?.toLocal();
      if (exp != null) {
        sub =
            '$planName plan · renews '
            '${exp.day}/${exp.month}/${exp.year}';
      }
    }
    return (icon: AppIcons.checkCircle, message: sub, tone: _StatusTone.active);
  }

  // Trial active — iOS has no trial, so skip straight to the paywall message.
  // ceil(), not .inDays: 23h left on a 24h trial is "1 day left", not "0".
  final trialEnd = trialEndsAt != null
      ? DateTime.tryParse(trialEndsAt)?.toUtc()
      : null;
  final trialDiff = trialEnd?.difference(now);
  final daysLeft = (trialDiff != null && !trialDiff.isNegative)
      ? (trialDiff.inHours / 24).ceil()
      : null;
  if (!isIOS && daysLeft != null) {
    return (
      icon: AppIcons.accessTime,
      message: daysLeft == 1
          ? 'Your free trial ends tomorrow. Subscribe now and nothing changes.'
          : 'Your free trial ends in $daysLeft days. Subscribe now and nothing changes.',
      tone: _StatusTone.warn,
    );
  }

  // Expired / no subscription
  return (
    icon: AppIcons.lock,
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

  // The hero used to be dark, so this needed its own two-tone palette. Now that
  // it sits on the cream canvas it is the same object as _StatusBanner — one
  // status presentation, using the design system's own tonal pairs.
  @override
  Widget build(BuildContext context) => _StatusBanner(gym: gym);
}

/// Tonal status banner — trial countdown, active plan, or expired. Rendered by
/// the hero and by the iOS "you're already subscribed" management screen.
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
    return _Banner(
      icon: info.icon,
      message: info.message,
      color: bg,
      textColor: fg,
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
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
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
      (icon: AppIcons.closeRounded, text: 'Cancel anytime — no lock-in'),
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

// ── Legacy (₹249/mo grandfathered) pricing: adds 3/6/12mo terms ──────────────

const _kLegacyFeatures = [
  (icon: AppIcons.groups, text: 'Unlimited members & check-ins'),
  (icon: AppIcons.badge, text: 'Unlimited staff logins & roles'),
  (icon: AppIcons.mail, text: 'Automatic email due reminders'),
  (icon: AppIcons.chat, text: 'WhatsApp due reminders'),
  (icon: AppIcons.showChart, text: 'Advanced reports & analytics'),
  (icon: AppIcons.event, text: 'Class scheduling & bookings'),
  (icon: AppIcons.personAdd, text: 'Leads & CRM'),
  (icon: AppIcons.qrCode, text: 'Member portal & QR check-in'),
  (icon: AppIcons.supportAgent, text: 'Priority support'),
];

// ── iOS: RevenueCat paywall + subscription management ─────────────────────────

class _IosPaywall extends ConsumerWidget {
  final Map<String, dynamic>? gym;
  const _IosPaywall({required this.gym});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerInfoAsync = ref.watch(customerInfoProvider);
    final hasAccess =
        customerInfoAsync.valueOrNull?.entitlements.active.containsKey(
          kRcEntitlement,
        ) ??
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
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'View billing history, cancel, or restore purchases.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.inkSoft,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: _openCustomerCenter,
                    icon: const Icon(AppIcons.manageAccounts, size: 18),
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

  /// Set when the price is a whole number of monthly prices: ₹2,990 for a
  /// year at ₹299/month is "2 months free", which reads better than "17% off".
  final int? freeMonths;

  /// The live offer on this term (percent_off or amount_off, plus name,
  /// cycles, code), or null.
  final Map<String, dynamic>? offer;

  const _TermOption(
    this.id,
    this.label,
    this.totalPrice,
    this.months, {
    this.discountPct,
    this.freeMonths,
    this.offer,
  });
}

/// The term's price after its offer, in paise; null when no offer applies.
/// A flat offer (amount_off, ₹) never takes the price below ₹1.
int? _offerPaise(_TermOption t) {
  final o = t.offer;
  if (o == null) return null;
  final pct = (o['percent_off'] as num?)?.toInt();
  final amount = (o['amount_off'] as num?)?.toInt();
  if (pct != null) return t.totalPrice * (100 - pct);
  if (amount == null) return null;
  return max((t.totalPrice - amount) * 100, 100);
}

/// "20% off" / "₹50 off".
String _offerLabel(Map<String, dynamic> o) {
  final pct = (o['percent_off'] as num?)?.toInt();
  return pct != null
      ? '$pct% off'
      : '$_cur${(o['amount_off'] as num).toInt()} off';
}

// Master switch for whether the paywall offers Starter as a choice at all.
// The rest of the tier — plan_member_limit()/plan_staff_limit() triggers, the
// whatsapp quota, the biometric gate, the Dodo products — is untouched by
// this flag; it only controls whether _PlanBody ever shows the toggle.
const _kStarterTierEnabled = false;

/// Builds the term ladder from get_paywall_pricing's `terms`. The "% off" and
/// "N months free" labels are derived from the prices, so a new price in the
/// database never shows a stale discount.
List<_TermOption> _termsFrom(Map<String, dynamic>? plan) {
  final raw = ((plan?['terms'] as List?) ?? const [])
      .map((t) => Map<String, dynamic>.from(t as Map))
      .toList();
  int? monthly;
  for (final t in raw) {
    if (t['months'] == 1) monthly = (t['price'] as num).toInt();
  }
  return raw.map((t) {
    final months = (t['months'] as num).toInt();
    final price = (t['price'] as num).toInt();
    final pct = monthly == null || months == 1
        ? null
        : (100 - price * 100 / (monthly * months)).round();
    final free = monthly == null || months == 1 || price % monthly != 0
        ? null
        : months - price ~/ monthly;
    return _TermOption(
      t['term'] as String,
      switch (months) {
        1 => '1 month',
        12 => '1 year',
        _ => '$months months',
      },
      price,
      months,
      discountPct: pct != null && pct > 0 ? pct : null,
      freeMonths: free != null && free > 0 ? free : null,
      offer: t['offer'] == null
          ? null
          : Map<String, dynamic>.from(t['offer'] as Map),
    );
  }).toList();
}

// Benefit-first, in the order a gym owner cares about: money he is losing,
// time he is wasting, then everything else. Plan limits still apply but belong
// in the fine print, not in the pitch.
const _kProFeatures = [
  (
    icon: AppIcons.chat,
    text: 'We WhatsApp your members before their fees are due — automatically',
  ),
  (icon: AppIcons.wallet, text: 'Know exactly who owes you money, today'),
  (
    icon: AppIcons.showChart,
    text: 'See what you collected this month without opening a register',
  ),
  (
    icon: AppIcons.qrCode,
    text: 'Members check in with a QR code, no register at the door',
  ),
  (icon: AppIcons.personAdd, text: 'Never lose a walk-in enquiry again'),
  (
    icon: AppIcons.badge,
    text: 'Your staff get their own logins, with only the access you allow',
  ),
  // + the limits line, built in _PlanBody from the plan's whatsapp_quota.
];

// Starter (₹299) — same core product, with the limits enforced by
// public.plan_member_limit / plan_staff_limit and lib/core/billing/plan_limits.dart.
// Keep this list in step with `_starterLockedModules` there: a feature listed
// as included that the app then locks is a refund request.
const _kStarterFeatures = [
  (icon: AppIcons.wallet, text: 'Know exactly who owes you money, today'),
  (
    icon: AppIcons.chat,
    text: 'WhatsApp your members before fees are due — 100 reminders a month',
  ),
  (
    icon: AppIcons.qrCode,
    text: 'Members check in with a QR code, no register at the door',
  ),
  (
    icon: AppIcons.showChart,
    text: 'See what you collected this month without opening a register',
  ),
  (
    icon: AppIcons.personAdd,
    text: 'Leads, expenses, batches and exports — all included',
  ),
  (icon: AppIcons.layers, text: 'Up to 100 members, 1 login'),
];

// Elite is hidden until plan gating is enforced. Do not delete.
// ignore: unused_element
const _kEliteFeatures = [
  (icon: AppIcons.groups, text: 'Unlimited members & check-ins'),
  (icon: AppIcons.badge, text: 'Unlimited staff logins & roles'),
  (icon: AppIcons.mail, text: 'Automatic email due reminders'),
  (icon: AppIcons.chat, text: '1,500 free WhatsApp due reminders/month'),
  (icon: AppIcons.showChart, text: 'Advanced reports & analytics'),
  (icon: AppIcons.event, text: 'Class scheduling & bookings'),
  (icon: AppIcons.personAdd, text: 'Leads & CRM'),
  (icon: AppIcons.qrCode, text: 'Member portal & QR check-in'),
  (icon: AppIcons.supportAgent, text: 'Priority support'),
];

class _DbPricing extends ConsumerStatefulWidget {
  final Map<String, dynamic>? gym;
  final String tier;
  final bool showTierToggle;
  final ValueChanged<String> onTierChanged;
  final String coupon;
  final ValueChanged<String> onCouponChanged;
  final String? initialTerm;
  const _DbPricing({
    required this.gym,
    this.initialTerm,
    required this.tier,
    required this.showTierToggle,
    required this.onTierChanged,
    required this.coupon,
    required this.onCouponChanged,
  });

  @override
  ConsumerState<_DbPricing> createState() => _DbPricingState();
}

class _DbPricingState extends ConsumerState<_DbPricing> {
  // Monthly by default (app_config.paywall_default_term can change it). Annual
  // used to be pre-selected, which asks a gym owner for a year up front at the
  // exact moment he is least convinced. Null until the owner taps a card.
  String? _selectedTerm;

  // Offer codes already reported as offer_viewed on this visit.
  final _loggedOffers = <String>{};

  @override
  Widget build(BuildContext context) {
    final pricingAsync = ref.watch(paywallPricingProvider(widget.coupon));
    final defaultTerm =
        ref.watch(appConfigProvider).valueOrNull?['paywall_default_term']
            as String? ??
        '1mo';

    return pricingAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      // No fallback prices: a stale hardcoded number is worse than a retry.
      error: (_, _) => _PricingUnavailable(
        onRetry: () => ref.invalidate(paywallPricingProvider(widget.coupon)),
      ),
      data: (pricing) {
        final plans = Map<String, dynamic>.from(
          (pricing['plans'] as Map?) ?? const {},
        );
        final plan = plans[widget.tier] == null
            ? null
            : Map<String, dynamic>.from(plans[widget.tier] as Map);
        _setBillingCurrency(plan?['currency'] as String?);
        final terms = _termsFrom(plan);
        if (terms.isEmpty) {
          return _PricingUnavailable(
            onRetry: () =>
                ref.invalidate(paywallPricingProvider(widget.coupon)),
          );
        }
        // Term ids are identical across tiers, so a tier switch keeps the
        // duration the owner already chose.
        final selected = terms.firstWhere(
          (t) => t.id == (_selectedTerm ?? widget.initialTerm ?? defaultTerm),
          orElse: () => terms.first,
        );
        for (final t in terms) {
          final code = t.offer?['code'] as String?;
          if (code != null && _loggedOffers.add(code)) {
            unawaited(AppEvents.offerViewed(code, t.id));
          }
        }
        // Each term carries its own offer (get_paywall_pricing resolves them
        // per term), matching what Dodo will actually discount on checkout.
        final offer = selected.offer;
        // In paise: 50% of ₹499 is ₹249.50, and the button must say what
        // Dodo will charge, not a rounded ₹250.
        final payNowPaise = _offerPaise(selected) ?? selected.totalPrice * 100;
        final payNow = _formatRupees(payNowPaise);

        final current = pricing['current'] == null
            ? null
            : Map<String, dynamic>.from(pricing['current'] as Map);
        // The term the gym is already subscribed to: its price box shows what
        // they actually pay, and its button can't sell it to them again.
        final isCurrentTerm =
            current != null &&
            current['plan'] == widget.tier &&
            current['term'] == selected.id;
        final currentPct = isCurrentTerm
            ? (current['discount_pct'] as num?)?.toInt()
            : null;
        final currentLeft = (current?['discount_cycles_left'] as num?)?.toInt();

        // What a card shows instead of its list price, in paise: the offer on
        // that term, or the gym's own running discount on the term it pays for.
        int? cardPaise(_TermOption t) {
          final offered = _offerPaise(t);
          if (offered != null) return offered;
          final ownPct =
              current != null &&
                  current['plan'] == widget.tier &&
                  current['term'] == t.id
              ? (current['discount_pct'] as num?)?.toInt()
              : null;
          return ownPct == null ? null : t.totalPrice * (100 - ownPct);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current != null && current['plan_price'] != null) ...[
              _CurrentPlanNote(current: current),
              const SizedBox(height: 14),
            ],
            if (widget.showTierToggle) ...[
              _TierToggle(tier: widget.tier, onChanged: widget.onTierChanged),
              const SizedBox(height: 12),
            ],
            const Text(
              'Choose your plan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 12),
            _TermGrid(
              terms: terms,
              selected: selected.id,
              onChanged: (id) => setState(() => _selectedTerm = id),
              discountedPaise: cardPaise,
            ),
            if (currentPct != null) ...[
              const SizedBox(height: 10),
              Text(
                currentLeft == null
                    ? 'Your $currentPct% discount applies every month.'
                    : 'Your $currentPct% discount: $currentLeft more '
                          '${currentLeft == 1 ? 'month' : 'months'}, then $_cur${selected.totalPrice}.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (offer != null) ...[
              const SizedBox(height: 12),
              _OfferNote(offer: offer, term: selected, payNow: payNow),
            ],
            const SizedBox(height: 16),
            _UpgradeButton(
              gym: widget.gym,
              plan: widget.tier,
              term: selected.id,
              price: payNow,
              coupon: widget.coupon,
              isCurrentTerm: isCurrentTerm,
              hasSubscription: current != null,
            ),
            // Dodo adds 18% GST on top (tax-exclusive products). The button
            // keeps the plan price; this line spells out the tax and total.
            // Outside India Dodo applies the buyer's local tax instead and
            // UPI/netbanking don't exist, so that gym gets a plain line.
            if (current == null) ...[
              const SizedBox(height: 8),
              Text(
                gymCountry == 'IN'
                    ? '$payNow + ${_formatRupees((payNowPaise * 18 / 100).round())} '
                          'GST = ${_formatRupees((payNowPaise * 118 / 100).round())} · '
                          'UPI, cards & netbanking'
                    : _cur == '₹'
                    ? '$payNow + local taxes · billed in Indian rupees · cards'
                    : '$payNow + local taxes · cards',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (current != null) ...[
              const SizedBox(height: 6),
              const _ManageSubscriptionLink(),
            ],
            // Coupons only apply to a new checkout, not to a plan change on a
            // live subscription.
            if (current == null) ...[
              const SizedBox(height: 6),
              _CouponField(
                coupon: widget.coupon,
                valid: pricing['coupon_valid'] as bool?,
                onApply: widget.onCouponChanged,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Two quiet text links under the subscribed button: our own cancel flow
/// (reason → save offer → confirm), and Dodo's customer portal for the card /
/// UPI mandate and invoices. Links, not a red button — findable, not
/// suggested.
class _ManageSubscriptionLink extends ConsumerStatefulWidget {
  const _ManageSubscriptionLink();

  @override
  ConsumerState<_ManageSubscriptionLink> createState() =>
      _ManageSubscriptionLinkState();
}

class _ManageSubscriptionLinkState
    extends ConsumerState<_ManageSubscriptionLink> {
  bool _loading = false;

  Future<void> _openCancel() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CancelSubscriptionScreen()),
    );
    if (changed == true) {
      ref.invalidate(paywallPricingProvider);
      ref.invalidate(staffProfileProvider);
    }
  }

  Future<void> _open() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse('$kBillingApiBase/api/billing/mobile/portal'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (response.statusCode != 200 || url == null) {
        throw Exception(data['error'] ?? 'portal ${response.statusCode}');
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open subscription settings. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 13,
      color: AppTheme.inkSoft,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppTheme.inkHint,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          onPressed: _loading ? null : _open,
          child: Text(
            _loading ? 'Opening…' : 'Payment method & invoices',
            style: style,
          ),
        ),
        TextButton(
          onPressed: _openCancel,
          child: const Text('Cancel subscription', style: style),
        ),
      ],
    );
  }
}

class _PricingUnavailable extends StatelessWidget {
  final VoidCallback onRetry;
  const _PricingUnavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Text(
            'Could not load prices.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// What a subscribed gym pays now: "~~₹499~~ ₹249.50/month for 5 more months,
/// then ₹499", or just "₹499/month". From get_paywall_pricing's `current`,
/// which the Dodo webhook keeps in step with the subscription's discount.
class _CurrentPlanNote extends StatelessWidget {
  final Map<String, dynamic> current;
  const _CurrentPlanNote({required this.current});

  @override
  Widget build(BuildContext context) {
    final price = (current['plan_price'] as num).toInt();
    final pct = (current['discount_pct'] as num?)?.toInt();
    final left = (current['discount_cycles_left'] as num?)?.toInt();
    final discounted = pct == null ? null : _formatRupees(price * (100 - pct));
    final period = left == null
        ? 'every month'
        : left == 1
        ? 'for 1 more month, then $_cur$price'
        : 'for $left more months, then $_cur$price';
    const ink = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppTheme.ink,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR PLAN',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          if (discounted == null)
            Text('$_cur$price/month', style: ink)
          else
            Text.rich(
              TextSpan(
                style: ink,
                children: [
                  TextSpan(
                    text: '$_cur$price',
                    style: const TextStyle(
                      decoration: TextDecoration.lineThrough,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                  TextSpan(text: ' $discounted/month $period'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// The billing currency of the plan on sale — what Dodo charges, not the gym's
// own display currency. ₹ for Indian plans; $ for the USD plan international
// gyms get (pricing_plans.currency). Set when get_paywall_pricing loads.
String _cur = '₹';
NumberFormat _priceFmt = NumberFormat.decimalPattern('en_IN');
void _setBillingCurrency(String? code) {
  final usd = code == 'USD';
  _cur = usd ? r'$' : '₹';
  _priceFmt = NumberFormat.decimalPattern(usd ? 'en_US' : 'en_IN');
}

/// "₹249.50" for paise (or cents) with a remainder, "₹299" otherwise.
String _formatRupees(int paise) => paise % 100 == 0
    ? '$_cur${_priceFmt.format(paise ~/ 100)}'
    : '$_cur${_priceFmt.format(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';

/// "50% OFF · ~~₹499~~ ₹249.50/month for your first 6 months, then ₹499".
/// Dodo applies the actual discount from the offer's code; this only restates
/// it, so it must say when the discount ends.
class _OfferNote extends StatelessWidget {
  final Map<String, dynamic> offer;
  final _TermOption term;
  final String payNow;
  const _OfferNote({
    required this.offer,
    required this.term,
    required this.payNow,
  });

  @override
  Widget build(BuildContext context) {
    final label = _offerLabel(offer).toUpperCase();
    final cycles = (offer['cycles'] as num?)?.toInt();
    final code = offer['code'] as String?;
    final unit = switch (term.months) {
      1 => 'month',
      12 => 'year',
      _ => '${term.months} months',
    };
    final full = _formatRupees(term.totalPrice * 100);
    // "₹249 for your first month, then ₹299/month." · "₹2,490 for your first
    // year, then ₹2,990/year." · "₹239.20/month for your first 3 months, …"
    final sentence = cycles == null
        ? ' $payNow every $unit.'
        : cycles == 1
        ? ' $payNow for your first $unit, then $full/$unit.'
        : ' $payNow/$unit for your first $cycles payments, then $full/$unit.';
    const gold = Color(0xFFE3C07A);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        gradient: AppTheme.darkGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${(offer['name'] as String? ?? 'Offer').toUpperCase()} · $label',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.4,
                color: AppTheme.onDark,
              ),
              children: [
                TextSpan(
                  text: _formatRupees(term.totalPrice * 100),
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onDarkSoft,
                  ),
                ),
                TextSpan(text: sentence),
              ],
            ),
          ),
          if (code != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(AppIcons.check, size: 14, color: gold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    offer['is_coupon'] == true
                        ? 'Coupon $code applied'
                        : 'Applied automatically at checkout',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: gold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsed by default so the paywall doesn't suggest everyone should go
/// hunting for a code before paying.
class _CouponField extends StatefulWidget {
  final String coupon;
  final bool? valid;
  final ValueChanged<String> onApply;
  const _CouponField({
    required this.coupon,
    required this.valid,
    required this.onApply,
  });

  @override
  State<_CouponField> createState() => _CouponFieldState();
}

class _CouponFieldState extends State<_CouponField> {
  late final _controller = TextEditingController(text: widget.coupon);
  late bool _open = widget.coupon.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() => _open = true),
          child: const Text(
            'Have a coupon code?',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'Coupon code'),
                onSubmitted: (v) => widget.onApply(v.trim().toUpperCase()),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              // Inline OutlinedButton in a Row: the theme's full-width
              // minimumSize would crush the field next to it.
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () =>
                  widget.onApply(_controller.text.trim().toUpperCase()),
              child: const Text('Apply'),
            ),
          ],
        ),
        if (widget.valid != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.valid! ? 'Coupon applied' : 'This code is not valid',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: widget.valid! ? AppTheme.accent : AppTheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

// Starter ₹299 / Pro ₹499. (Elite ₹999 stays defined but unreachable — the
// scaffold below was written for it and is now used for Starter instead.)
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
          Expanded(
            child: _TierTab(
              label: 'Starter',
              selected: tier == 'starter',
              onTap: () => onChanged('starter'),
            ),
          ),
          Expanded(
            child: _TierTab(
              label: 'Pro',
              selected: tier == 'pro',
              onTap: () => onChanged('pro'),
            ),
          ),
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
  const _TierTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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

// ── Plan cards ────────────────────────────────────────────────────────────────

/// Every term visible at once as a 2×2 grid, so the yearly saving sits next to
/// the monthly price instead of behind a tab. Each card carries its own price,
/// per-month figure and saving; the selected one gets the accent border.
class _TermGrid extends StatelessWidget {
  final List<_TermOption> terms;
  final String selected;
  final ValueChanged<String> onChanged;

  /// Price to show instead of the list price, in paise (offer or own discount).
  final int? Function(_TermOption) discountedPaise;
  const _TermGrid({
    required this.terms,
    required this.selected,
    required this.onChanged,
    required this.discountedPaise,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(int i) => i < terms.length
        ? _TermCard(
            term: terms[i],
            selected: terms[i].id == selected,
            discountedPaise: discountedPaise(terms[i]),
            onTap: () => onChanged(terms[i].id),
          )
        : const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < terms.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell(i)),
                const SizedBox(width: 10),
                Expanded(child: cell(i + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TermCard extends StatelessWidget {
  final _TermOption term;
  final bool selected;
  final int? discountedPaise;
  final VoidCallback onTap;
  const _TermCard({
    required this.term,
    required this.selected,
    required this.discountedPaise,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final offer = term.offer;
    final perMonth = (term.totalPrice / term.months).round();
    final free = term.freeMonths;
    final saving = free != null
        ? '$free ${free == 1 ? 'month' : 'months'} free'
        : term.discountPct != null
        ? 'save ${term.discountPct}%'
        : null;
    final sub = offer != null
        ? (offer['cycles'] == 1
              ? '${_offerLabel(offer)} first payment'
              : '${_offerLabel(offer)} with offer')
        : term.months == 1
        ? 'per month'
        : '$_cur$perMonth/mo${saving == null ? '' : ' · $saving'}';
    final badge = offer != null
        ? 'OFFER'
        : free != null
        ? '$free ${free == 1 ? 'MONTH' : 'MONTHS'} FREE'
        : null;

    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFF4F9F9) : AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppTheme.accent : AppTheme.border,
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.10),
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    term.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    children: [
                      Text(
                        discountedPaise == null
                            ? _formatRupees(term.totalPrice * 100)
                            : _formatRupees(discountedPaise!),
                        style: AppTheme.numberStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      if (discountedPaise != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            _formatRupees(term.totalPrice * 100),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.inkHint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: offer != null || saving != null
                          ? AppTheme.statusActive
                          : AppTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: -9,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: offer != null
                        ? const Color(0xFFE3C07A)
                        : AppTheme.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: offer != null ? AppTheme.ink : Colors.white,
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
// ── WhatsApp help (footer) ────────────────────────────────────────────────────

/// Was a full "Contact us for pricing" card sitting directly under the prices,
/// which told every visitor the listed price was negotiable and routed buyers
/// into a manual sales conversation. Demoted to a plain footer link: still an
/// escape hatch for people who genuinely need one, no longer the easier path
/// than paying.
class _WhatsAppFooterLink extends ConsumerWidget {
  const _WhatsAppFooterLink();

  Future<void> _openWhatsApp(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = supportWhatsAppUrl(ref);
    return Center(
      child: TextButton(
        onPressed: () => _openWhatsApp(context, url),
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

  /// What the owner pays today (after any offer), e.g. "₹249.50".
  final String price;

  final String coupon;

  /// The gym already pays for exactly this plan + term.
  final bool isCurrentTerm;

  /// A live subscription exists, so this button changes its plan rather than
  /// starting a new one. A cancelled gym still inside its paid period has
  /// access but no subscription, and must see "Subscribe".
  final bool hasSubscription;
  const _UpgradeButton({
    required this.gym,
    this.plan = 'pro',
    required this.term,
    required this.price,
    this.coupon = '',
    this.isCurrentTerm = false,
    this.hasSubscription = false,
  });

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
        Uri.parse('$kBillingApiBase/api/billing/mobile/checkout'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'plan': widget.plan,
          'term': widget.term,
          'platform': kIsWeb ? 'web' : 'mobile',
          if (widget.coupon.isNotEmpty) 'coupon': widget.coupon,
        }),
      );

      if (response.statusCode != 200) {
        final message = response.statusCode == 422
            ? ((jsonDecode(response.body) as Map<String, dynamic>)['error']
                      as String? ??
                  'Could not change plan.')
            : 'Could not start checkout. Please try again.';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (data['alreadyActive'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are already subscribed to this plan.'),
            ),
          );
        }
        ref.invalidate(staffProfileProvider);
        return;
      }

      if (url == null) {
        // Plan changed on the existing subscription directly — no checkout redirect.
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Plan updated.')));
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
          const SnackBar(
            content: Text('Could not start checkout. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Names the price so the button restates the commitment instead of the
  /// generic "Upgrade to Pro" it used to say.
  String get _ctaLabel => 'Subscribe · ${widget.price}';

  @override
  Widget build(BuildContext context) {
    final plan = widget.gym?['plan'] as String?;
    final planExpiresAt = widget.gym?['plan_expires_at'] as String?;
    final now = DateTime.now().toUtc();
    final hasExpiry =
        planExpiresAt != null &&
        (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false);
    final isActive = (plan == 'pro' && planExpiresAt == null) || hasExpiry;
    // Greyed out only while access is live. A gym whose subscription lapsed
    // (expired, or stuck with a past expiry) must be able to buy it again.
    final alreadyOwned = widget.isCurrentTerm && isActive;

    if (alreadyOwned) {
      return SizedBox(
        height: 52,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(AppIcons.checkCircle, size: 18),
          label: const Text(
            'Subscribed · your current plan',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loading ? null : _upgrade,
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.hasSubscription ? 'Change plan' : _ctaLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}
