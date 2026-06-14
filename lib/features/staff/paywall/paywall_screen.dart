import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

const _kAppUrl = 'https://www.gymcrm.in';
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
    if (Platform.isIOS) {
      return _IosManageOnWeb(gym: gym);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(gym: gym),
            const SizedBox(height: 24),
            _PlanCard(
              name: 'Starter',
              features: const [
                '1 staff login',
                'Up to 300 members',
                'QR code check-ins',
                'Lead tracking & follow-ups',
                'UPI payment collection',
                'Member portal app',
                'Earnings reports',
              ],
            ),
            const SizedBox(height: 16),
            _PlanCard(
              name: 'Pro',
              highlighted: true,
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
            const SizedBox(height: 24),
            _ContactForPricing(),
          ],
        ),
      ),
    );
  }
}

// ── iOS: manage subscription on the web ───────────────────────────────────────
// Apple does not allow selling our digital subscription via our own checkout
// inside the app, so on iOS we show the current status and a button that opens
// the website where the owner can subscribe / manage their plan.

class _IosManageOnWeb extends StatelessWidget {
  final Map<String, dynamic>? gym;
  const _IosManageOnWeb({required this.gym});

  Future<void> _openWeb(BuildContext context) async {
    final uri = Uri.parse('$_kAppUrl/dashboard');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the browser')),
        );
      }
    }
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
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manage your subscription',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Plans and billing are managed on the GymCRM website. '
                    'Sign in there to start or change your subscription — your '
                    'plan applies automatically across all your devices.',
                    style: TextStyle(fontSize: 14, color: AppTheme.inkSoft, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWeb(context),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text(
                        'Open gymcrm.in',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.ink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
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

    // Trial active
    final daysLeft = trialEndsAt != null
        ? DateTime.tryParse(trialEndsAt)?.toUtc().difference(now).inDays
        : null;
    if (daysLeft != null && daysLeft > 0) {
      return _Banner(
        icon: Icons.access_time_outlined,
        message: 'Your free trial ends in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}.',
        color: AppTheme.statusWarnBg,
        textColor: AppTheme.statusWarn,
      );
    }

    // Expired
    return _Banner(
      icon: Icons.lock_outline,
      message: 'Your free trial has ended. Subscribe to continue using GymCRM.',
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

  const _PlanCard({
    required this.name,
    required this.features,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? AppTheme.ink : AppTheme.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? const [BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: highlighted ? AppTheme.ink : AppTheme.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: highlighted ? Colors.white : AppTheme.ink,
                  ),
                ),
                if (highlighted) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Popular',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Features
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.statusActive),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(f, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
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
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline, size: 20, color: AppTheme.ink),
              SizedBox(width: 10),
              Text(
                'Contact us for pricing',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Reach out to our support team on WhatsApp to get the right plan for your gym and discuss pricing.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openWhatsApp(context),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text(
                'Chat on WhatsApp',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
