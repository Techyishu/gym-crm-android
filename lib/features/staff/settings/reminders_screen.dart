import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../auth/providers/auth_provider.dart';

// pack key → (Dodo checkout key [Android], App Store product ID [iOS]).
const _kCreditPacks = [
  (pack: 'pack_200', iosProductId: 'gymcrm_credits_200', label: '200 msgs', price: '₹100'),
  (pack: 'pack_300', iosProductId: 'gymcrm_credits_300', label: '300 msgs', price: '₹150'),
  (pack: 'pack_500', iosProductId: 'gymcrm_credits_500', label: '500 msgs', price: '₹250'),
];

const _kReminderDayOptions = [1, 2, 3, 5, 7, 14];

// Approved MSG91 WhatsApp templates. `id` must match a key in TEMPLATES in
// supabase/functions/whatsapp-reminders/index.ts — add to both when a new
// template is approved.
const _kWhatsAppTemplates = [
  (
    id: 'payment_reminder',
    label: 'English · short',
    preview: 'Hi Rahul! Your membership expires in 3 days. Please contact FitZone to renew.',
  ),
  (
    id: 'payment_due_3',
    label: 'English · polite',
    preview: 'Hi Rahul, just a quick reminder that your FitZone membership will expire in 3 days. '
        'Renew it before the expiry date to keep your access active',
  ),
  (
    id: 'payment_reminder_2',
    label: 'हिंदी',
    preview: 'Hi Rahul! 👋\n'
        'आपकी FitZone की मेंबरशिप 3 दिन में खत्म होने वाली है। '
        'बिना किसी रुकावट के वर्कआउट जारी रखने के लिए समय पर रिन्यू करवा लें.',
  ),
];

// One-screen accent colors distinguishing the two channels — push uses a
// warm orange, WhatsApp reuses AppTheme.darkCard (already a deep green).
const _pushAccent = Color(0xFFDD5A34);

int _planQuota(String? plan) => plan == 'pro' ? 100 : 0;

final _remindersGymProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  return await Supabase.instance.client.from('gyms').select().eq('id', gymId).maybeSingle();
});

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymAsync = ref.watch(_remindersGymProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Reminders'), leading: const BackButton()),
      body: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (gym) {
          if (gym == null) return const Center(child: Text('Gym not found'));
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Automatic nudges before a membership expires',
                  style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft),
                ),
                const SizedBox(height: 20),
                _PushReminderCard(gym: gym, onChanged: () => ref.invalidate(_remindersGymProvider)),
                const SizedBox(height: 16),
                _WhatsAppReminderCard(gym: gym, onChanged: () => ref.invalidate(_remindersGymProvider)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Shared channel card scaffold ───────────────────────────────────────────

class _ChannelCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final Widget child;

  const _ChannelCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.saving,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconFg, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, height: 1.3)),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: AppTheme.accent,
                onChanged: saving ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppTheme.border),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _DayPill({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? selectedColor : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppTheme.ink,
          ),
        ),
      ),
    );
  }
}

class _SendBeforeLabel extends StatelessWidget {
  const _SendBeforeLabel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'SEND BEFORE RENEWAL',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.inkHint, letterSpacing: 0.6),
    );
  }
}

// ── Push reminder card ──────────────────────────────────────────────────────

class _PushReminderCard extends StatefulWidget {
  final Map<String, dynamic> gym;
  final VoidCallback onChanged;
  const _PushReminderCard({required this.gym, required this.onChanged});

  @override
  State<_PushReminderCard> createState() => _PushReminderCardState();
}

class _PushReminderCardState extends State<_PushReminderCard> {
  bool _saving = false;

  Future<void> _save({bool? enabled, Set<int>? days}) async {
    final gymId = widget.gym['id'] as String;
    final nextEnabled = enabled ?? (widget.gym['push_reminder_enabled'] as bool? ?? false);
    final nextDays = days ?? _currentDays();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('gyms').update({
        'push_reminder_enabled': nextEnabled,
        'push_reminder_days': nextDays.toList()..sort(),
      }).eq('id', gymId);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<int> _currentDays() {
    final raw = widget.gym['push_reminder_days'] as List?;
    return raw != null ? raw.map((d) => d as int).toSet() : {3, 7};
  }

  void _toggleDay(int day) {
    final next = Set<int>.from(_currentDays());
    if (next.contains(day)) {
      if (next.length == 1) return;
      next.remove(day);
    } else {
      next.add(day);
    }
    _save(days: next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.gym['push_reminder_enabled'] as bool? ?? false;
    final days = _currentDays();

    return _ChannelCard(
      icon: Icons.notifications_outlined,
      iconBg: _pushAccent.withValues(alpha: 0.12),
      iconFg: _pushAccent,
      title: 'Push reminders',
      subtitle: 'In-app notification to the member',
      enabled: enabled,
      saving: _saving,
      onToggle: (v) => _save(enabled: v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SendBeforeLabel(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kReminderDayOptions.map((d) => _DayPill(
              label: '$d day${d == 1 ? '' : 's'}',
              selected: days.contains(d),
              selectedColor: _pushAccent,
              onTap: _saving ? () {} : () => _toggleDay(d),
            )).toList(),
          ),
          const SizedBox(height: 14),
          const Text(
            'Reminders are sent once a day for members whose renewal date matches one of the selected windows.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkHint, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── WhatsApp reminder card ──────────────────────────────────────────────────

class _WhatsAppReminderCard extends StatefulWidget {
  final Map<String, dynamic> gym;
  final VoidCallback onChanged;
  const _WhatsAppReminderCard({required this.gym, required this.onChanged});

  @override
  State<_WhatsAppReminderCard> createState() => _WhatsAppReminderCardState();
}

class _WhatsAppReminderCardState extends State<_WhatsAppReminderCard> {
  bool _saving = false;
  bool _sendingNow = false;
  String? _buyingPack;

  Future<void> _buyCredits(String pack, String iosProductId) async {
    setState(() => _buyingPack = pack);
    try {
      if (isIOS) {
        await _buyCreditsIos(iosProductId);
      } else {
        await _buyCreditsAndroid(pack);
      }
    } finally {
      if (mounted) setState(() => _buyingPack = null);
    }
  }

  // Android — Dodo checkout via Custom Tab (mirrors the Pro-plan upgrade flow).
  Future<void> _buyCreditsAndroid(String pack) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    try {
      final response = await http.post(
        Uri.parse('https://www.gymcrm.in/api/billing/mobile/checkout-credits'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'pack': pack}),
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
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start checkout. Please try again.')),
        );
      }
    }
  }

  // iOS — StoreKit consumable IAP via RevenueCat. Credits are added server-side
  // by the revenuecat-webhook edge function once the purchase event lands, so
  // this just triggers the purchase and lets the user know to check back.
  Future<void> _buyCreditsIos(String productId) async {
    try {
      final products = await Purchases.getProducts([productId]);
      if (products.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This pack is not available right now.')),
          );
        }
        return;
      }
      await Purchases.purchaseStoreProduct(products.first);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase successful — credits will appear shortly.')),
        );
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: ${e.message}')),
        );
      }
    }
  }

  Future<void> _sendNow() async {
    setState(() => _sendingNow = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'whatsapp-reminders',
        body: {'gym_id': widget.gym['id']},
      );
      final raw = res.data;
      final parsed = raw is String ? jsonDecode(raw) as Map<String, dynamic> : raw as Map<String, dynamic>?;
      final sent = parsed?['sent'] as int? ?? 0;
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent > 0
              ? 'Sent $sent reminder${sent == 1 ? '' : 's'}'
              : 'No members due for a reminder right now'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingNow = false);
    }
  }

  Future<void> _save({bool? enabled, Set<int>? days, String? template}) async {
    final gymId = widget.gym['id'] as String;
    final nextEnabled = enabled ?? (widget.gym['whatsapp_reminder_enabled'] as bool? ?? false);
    final nextDays = days ?? _currentDays();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('gyms').update({
        'whatsapp_reminder_enabled': nextEnabled,
        'whatsapp_reminder_days': nextDays.toList()..sort(),
        'whatsapp_template': template ?? _currentTemplate(),
      }).eq('id', gymId);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<int> _currentDays() {
    final raw = widget.gym['whatsapp_reminder_days'] as List?;
    return raw != null ? raw.map((d) => d as int).toSet() : {3};
  }

  String _currentTemplate() {
    final raw = widget.gym['whatsapp_template'] as String?;
    return _kWhatsAppTemplates.any((t) => t.id == raw) ? raw! : _kWhatsAppTemplates.first.id;
  }

  void _toggleDay(int day) {
    final next = Set<int>.from(_currentDays());
    if (next.contains(day)) {
      if (next.length == 1) return;
      next.remove(day);
    } else {
      next.add(day);
    }
    _save(days: next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.gym['whatsapp_reminder_enabled'] as bool? ?? false;
    final days = _currentDays();
    final quota = _planQuota(widget.gym['plan'] as String?);
    final quotaUsed = widget.gym['whatsapp_monthly_quota_used'] as int? ?? 0;
    final credits = widget.gym['whatsapp_credits'] as int? ?? 0;
    final templateId = _currentTemplate();
    final template = _kWhatsAppTemplates.firstWhere((t) => t.id == templateId);

    return _ChannelCard(
      icon: Icons.chat_bubble_outline,
      iconBg: AppTheme.darkCard,
      iconFg: AppTheme.mintOnDark,
      title: 'WhatsApp reminders',
      subtitle: "Message sent to the member's WhatsApp",
      enabled: enabled,
      saving: _saving,
      onToggle: (v) => _save(enabled: v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SendBeforeLabel(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kReminderDayOptions.map((d) => _DayPill(
              label: '$d day${d == 1 ? '' : 's'}',
              selected: days.contains(d),
              selectedColor: AppTheme.darkCard,
              onTap: _saving ? () {} : () => _toggleDay(d),
            )).toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'MESSAGE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.inkHint, letterSpacing: 0.6),
          ),
          const SizedBox(height: 10),
          // Picker only earns its space once there's a real choice.
          if (_kWhatsAppTemplates.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kWhatsAppTemplates.map((t) => _DayPill(
                label: t.label,
                selected: t.id == template.id,
                selectedColor: AppTheme.darkCard,
                onTap: _saving ? () {} : () => _save(template: t.id),
              )).toList(),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(14)),
            child: Text(
              template.preview,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, height: 1.45),
            ),
          ),
          const SizedBox(height: 16),
          _CreditsBlock(quota: quota, quotaUsed: quotaUsed, credits: credits),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kCreditPacks.map((p) => OutlinedButton(
              onPressed: _buyingPack != null ? null : () => _buyCredits(p.pack, p.iosProductId),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.darkCard,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: _buyingPack == p.pack
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('${p.label} · ${p.price}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            )).toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sendingNow ? null : _sendNow,
              icon: _sendingNow
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 17),
              label: Text(_sendingNow ? 'Sending…' : 'Send reminders now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.ink,
                side: const BorderSide(color: AppTheme.border),
                minimumSize: const Size(0, 46),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Credits display ──────────────────────────────────────────────────────────

class _CreditsBlock extends StatelessWidget {
  final int quota;
  final int quotaUsed;
  final int credits;
  const _CreditsBlock({required this.quota, required this.quotaUsed, required this.credits});

  @override
  Widget build(BuildContext context) {
    final progress = quota > 0 ? (quotaUsed / quota).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quota > 0) ...[
            Row(
              children: [
                const Expanded(
                  child: Text('Free monthly quota', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                ),
                Text('$quotaUsed/$quota used', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.border,
                valueColor: const AlwaysStoppedAnimation(AppTheme.darkCard),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Resets on the 1st of the month', style: TextStyle(fontSize: 11.5, color: AppTheme.inkHint)),
            const SizedBox(height: 14),
            Container(height: 1, color: AppTheme.border),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Purchased credits', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.ink)),
              Text('$credits credits remaining', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.ink)),
            ],
          ),
        ],
      ),
    );
  }
}
