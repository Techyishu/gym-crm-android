import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/billing/plan_limits.dart';
import '../../../core/services/app_events.dart';
import '../../../core/services/coachmark_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../core/utils/platform_info.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';

// pack key → (Dodo checkout key [Android], App Store product ID [iOS]).
const _kCreditPacks = [
  (
    pack: 'pack_200',
    iosProductId: 'gymcrm_credits_200',
    label: '200 msgs',
    price: '₹100',
  ),
  (
    pack: 'pack_300',
    iosProductId: 'gymcrm_credits_300',
    label: '300 msgs',
    price: '₹150',
  ),
  (
    pack: 'pack_500',
    iosProductId: 'gymcrm_credits_500',
    label: '500 msgs',
    price: '₹250',
  ),
];

const _kReminderDayOptions = [1, 2, 3, 5, 7, 14];

// Approved MSG91 WhatsApp templates. `id` must match a key in TEMPLATES in
// supabase/functions/whatsapp-reminders/index.ts — add to both when a new
// template is approved.
const _kWhatsAppTemplates = [
  (
    id: 'payment_reminder',
    label: 'English · short',
    preview:
        'Hi Rahul! Your membership expires in 3 days. Please contact FitZone to renew.',
  ),
  (
    id: 'payment_due_3',
    label: 'English · polite',
    preview:
        'Hi Rahul, just a quick reminder that your FitZone membership will expire in 3 days. '
        'Renew it before the expiry date to keep your access active',
  ),
  (
    id: 'payment_reminder_2',
    label: 'हिंदी',
    preview:
        'Hi Rahul! 👋\n'
        'आपकी FitZone की मेंबरशिप 3 दिन में खत्म होने वाली है। '
        'बिना किसी रुकावट के वर्कआउट जारी रखने के लिए समय पर रिन्यू करवा लें.',
  ),
];

// Quota lives in lib/core/billing/plan_limits.dart, shared with the DB
// (plan_whatsapp_quota) and the edge functions (_shared/plan_limits.ts).
int _planQuota(Map<String, dynamic> gym) => whatsappQuota(gym);

final _remindersGymProvider = FutureProvider.autoDispose<Map<String, dynamic>?>(
  (ref) async {
    final gymId = await ref.watch(gymIdProvider.future);
    return await Supabase.instance.client
        .from('gyms')
        .select()
        .eq('id', gymId)
        .maybeSingle();
  },
);

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(_remindersGymProvider);
    final container = ProviderScope.containerOf(context, listen: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.l10n.reminders),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(
        child: gymAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ErrorState(what: 'your message settings'),
          data: (gym) {
            if (gym == null)
              return Center(child: Text(context.l10n.gymNotFound));
            void onChanged() => container.invalidate(_remindersGymProvider);
            final coachmark = ref.watch(coachmarkServiceProvider).valueOrNull;
            final showInvoiceBadge =
                coachmark?.shouldShow('feature_invoice_whatsapp') ?? false;

            final tabs = [
              (
                icon: AppIcons.notifications,
                label: context.l10n.push,
                on: gym['push_reminder_enabled'] as bool? ?? false,
                isNew: false,
              ),
              (
                icon: AppIcons.chat,
                label: context.l10n.whatsapp,
                on: gym['whatsapp_reminder_enabled'] as bool? ?? false,
                isNew: false,
              ),
              (
                icon: AppIcons.receipt,
                label: context.l10n.invoices,
                on: gym['whatsapp_invoice_enabled'] as bool? ?? false,
                isNew: showInvoiceBadge,
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                  child: Text(
                    context.l10n.automaticRenewalNudges,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _ChannelTab(
                            icon: tabs[i].icon,
                            label: tabs[i].label,
                            on: tabs[i].on,
                            active: _tab == i,
                            isNew: tabs[i].isNew,
                            onTap: () {
                              if (tabs[i].isNew)
                                coachmark?.markSeen('feature_invoice_whatsapp');
                              setState(() => _tab = i);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    child: switch (_tab) {
                      0 => _PushReminderCard(gym: gym, onChanged: onChanged),
                      1 => _WhatsAppReminderCard(
                        gym: gym,
                        onChanged: onChanged,
                      ),
                      _ => _InvoiceWhatsAppCard(gym: gym, onChanged: onChanged),
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Channel tab ────────────────────────────────────────────────────────────

class _ChannelTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final bool active;
  final bool isNew;
  final VoidCallback onTap;

  const _ChannelTab({
    required this.icon,
    required this.label,
    required this.on,
    required this.active,
    required this.onTap,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final dot = on
        ? (active ? AppTheme.mintOnDark : AppTheme.accent)
        : (active ? Colors.white24 : AppTheme.inkHint);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(6, 11, 6, 10),
            decoration: BoxDecoration(
              color: active ? AppTheme.ink : AppTheme.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: active ? AppTheme.ink : AppTheme.border,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: active
                      ? Colors.white
                      : (on ? AppTheme.accent : AppTheme.inkHint),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      on ? context.l10n.on : context.l10n.off,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: active
                            ? Colors.white70
                            : (on ? AppTheme.inkSoft : AppTheme.inkHint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isNew)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'NEW',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared channel panel scaffold ──────────────────────────────────────────

class _ChannelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onToggle;
  final Widget child;

  const _ChannelCard({
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
      decoration: AppTheme.cardDecoration(radius: 20),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkHint,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: Colors.white,
                activeTrackColor: AppTheme.accent,
                onChanged: saving ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppTheme.border),
          const SizedBox(height: 16),
          // Panel content dims out when the channel is off — same affordance as
          // the design: settings stay visible but are not editable.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1 : 0.4,
            child: IgnorePointer(ignoring: !enabled, child: child),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedColor : AppTheme.surface2,
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.inkHint,
      letterSpacing: 0.6,
    ),
  );
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    color: AppTheme.border,
    margin: const EdgeInsets.symmetric(vertical: 16),
  );
}

class _CreditPack extends StatelessWidget {
  final String price;
  final String msgs;
  final bool busy;
  final VoidCallback? onTap;

  const _CreditPack({
    required this.price,
    required this.msgs,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: busy
            ? const SizedBox(
                height: 32,
                child: Center(
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : Column(
                children: [
                  Text(
                    price,
                    style: AppTheme.numberStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    msgs,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkHint,
                    ),
                  ),
                ],
              ),
      ),
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
    final nextEnabled =
        enabled ?? (widget.gym['push_reminder_enabled'] as bool? ?? false);
    final nextDays = days ?? _currentDays();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('gyms')
          .update({
            'push_reminder_enabled': nextEnabled,
            'push_reminder_days': nextDays.toList()..sort(),
          })
          .eq('id', gymId);
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
      title: context.l10n.pushReminders,
      subtitle: context.l10n.pushReminderSubtitle,
      enabled: enabled,
      saving: _saving,
      onToggle: (v) => _save(enabled: v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(context.l10n.sendBeforeRenewal),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kReminderDayOptions
                .map(
                  (d) => _DayPill(
                    label: '$d day${d == 1 ? '' : 's'}',
                    selected: days.contains(d),
                    selectedColor: AppTheme.accent,
                    onTap: _saving ? () {} : () => _toggleDay(d),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.reminderWindowsHint,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.inkHint,
              height: 1.5,
            ),
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
            SnackBar(content: Text(context.l10n.checkoutStartFailed)),
          );
        }
        return;
      }

      final url =
          (jsonDecode(response.body) as Map<String, dynamic>)['url'] as String?;
      if (url == null) return;
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.checkoutStartFailed)),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.l10n.packUnavailable)));
        }
        return;
      }
      await Purchases.purchaseStoreProduct(products.first);
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.purchaseSuccessful)),
        );
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.purchaseFailed(e.message ?? e.code)),
          ),
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
      final parsed = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : raw as Map<String, dynamic>?;
      final sent = parsed?['sent'] as int? ?? 0;
      widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sent > 0
                  ? 'Sent $sent reminder${sent == 1 ? '' : 's'}'
                  : 'No members due for a reminder right now',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.sendFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _sendingNow = false);
    }
  }

  Future<void> _save({bool? enabled, Set<int>? days, String? template}) async {
    final gymId = widget.gym['id'] as String;
    final wasEnabled =
        widget.gym['whatsapp_reminder_enabled'] as bool? ?? false;
    final nextEnabled = enabled ?? wasEnabled;
    final nextDays = days ?? _currentDays();
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('gyms')
          .update({
            'whatsapp_reminder_enabled': nextEnabled,
            'whatsapp_reminder_days': nextDays.toList()..sort(),
            'whatsapp_template': template ?? _currentTemplate(),
          })
          .eq('id', gymId);
      if (nextEnabled && !wasEnabled)
        unawaited(AppEvents.whatsappRemindersEnabled());
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
    return _kWhatsAppTemplates.any((t) => t.id == raw)
        ? raw!
        : _kWhatsAppTemplates.first.id;
  }

  void _toggleDay(int day) {
    final next = Set<int>.from(_currentDays());
    if (next.contains(day)) {
      if (next.length == 1) return;
      next.remove(day);
    } else {
      // Each offset is one message per member per cycle, so the number of
      // offsets — not the credit balance — is what multiplies a gym's WhatsApp
      // cost. Capped by tier here so a Starter gym can't configure a month it
      // will run out of credits halfway through. Push reminders above are
      // deliberately uncapped — they cost us nothing.
      final limit = reminderDaysLimit(planTierOf(widget.gym));
      if (next.length >= limit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Starter includes $limit reminder per member. Upgrade to Pro for '
              'up to ${reminderDaysLimit(PlanTier.pro)}.',
            ),
          ),
        );
        return;
      }
      next.add(day);
    }
    _save(days: next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.gym['whatsapp_reminder_enabled'] as bool? ?? false;
    final days = _currentDays();
    final quota = _planQuota(widget.gym);
    final quotaUsed = widget.gym['whatsapp_monthly_quota_used'] as int? ?? 0;
    final credits = widget.gym['whatsapp_credits'] as int? ?? 0;
    final templateId = _currentTemplate();
    final template = _kWhatsAppTemplates.firstWhere((t) => t.id == templateId);

    return _ChannelCard(
      title: context.l10n.whatsappReminders,
      subtitle: context.l10n.whatsappReminderSubtitle,
      enabled: enabled,
      saving: _saving,
      onToggle: (v) => _save(enabled: v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(context.l10n.sendBeforeRenewal),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kReminderDayOptions
                .map(
                  (d) => _DayPill(
                    label: '$d day${d == 1 ? '' : 's'}',
                    selected: days.contains(d),
                    selectedColor: AppTheme.accent,
                    onTap: _saving ? () {} : () => _toggleDay(d),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.oneMessagePerWindow,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.inkHint,
              height: 1.5,
            ),
          ),
          const _PanelDivider(),
          _SectionLabel(context.l10n.message),
          const SizedBox(height: 10),
          // Picker only earns its space once there's a real choice.
          if (_kWhatsAppTemplates.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kWhatsAppTemplates
                  .map(
                    (t) => _DayPill(
                      label: t.label,
                      selected: t.id == template.id,
                      selectedColor: AppTheme.accent,
                      onTap: _saving ? () {} : () => _save(template: t.id),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 11),
          ],
          // Chat-bubble preview on the dark hero surface, per the design.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
            decoration: AppTheme.darkCardDecoration(radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.preview,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.onDarkSoft,
                  ),
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 11, 13, 9),
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      template.preview,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.ink,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _PanelDivider(),
          _SectionLabel(context.l10n.credits),
          const SizedBox(height: 11),
          _CreditsBlock(quota: quota, quotaUsed: quotaUsed, credits: credits),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < _kCreditPacks.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _CreditPack(
                    price: _kCreditPacks[i].price,
                    msgs: _kCreditPacks[i].label,
                    busy: _buyingPack == _kCreditPacks[i].pack,
                    onTap: _buyingPack != null
                        ? null
                        : () => _buyCredits(
                            _kCreditPacks[i].pack,
                            _kCreditPacks[i].iosProductId,
                          ),
                  ),
                ),
              ],
            ],
          ),
          const _PanelDivider(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sendingNow ? null : _sendNow,
              icon: _sendingNow
                  ? const SizedBox(
                      height: 15,
                      width: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(AppIcons.send, size: 17),
              label: Text(
                _sendingNow
                    ? context.l10n.sending
                    : context.l10n.sendRemindersNow,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.accentFg,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Invoice WhatsApp card ────────────────────────────────────────────────────
// Gates trg_notify_invoice_whatsapp / trg_notify_invoice_paid_whatsapp
// (supabase/migrations/20260805_invoice_whatsapp_trigger.sql) on
// gyms.whatsapp_invoice_enabled — off by default so no gym spends WhatsApp
// credits on invoice messages without opting in here.

class _InvoiceWhatsAppCard extends StatefulWidget {
  final Map<String, dynamic> gym;
  final VoidCallback onChanged;
  const _InvoiceWhatsAppCard({required this.gym, required this.onChanged});

  @override
  State<_InvoiceWhatsAppCard> createState() => _InvoiceWhatsAppCardState();
}

class _InvoiceWhatsAppCardState extends State<_InvoiceWhatsAppCard> {
  bool _saving = false;

  Future<void> _save(bool enabled) async {
    final gymId = widget.gym['id'] as String;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('gyms')
          .update({'whatsapp_invoice_enabled': enabled})
          .eq('id', gymId);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.gym['whatsapp_invoice_enabled'] as bool? ?? false;

    return _ChannelCard(
      title: context.l10n.invoiceWhatsappMessages,
      subtitle: context.l10n.invoiceWhatsappSubtitle,
      enabled: enabled,
      saving: _saving,
      onToggle: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'When a new invoice is generated or a payment is collected, the member '
            'gets a WhatsApp message with a link to download the invoice/receipt.',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.l10n.sameWhatsappCredits,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppTheme.inkHint,
                      fontWeight: FontWeight.w600,
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

// ── Credits display ──────────────────────────────────────────────────────────

class _CreditsBlock extends StatelessWidget {
  final int quota;
  final int quotaUsed;
  final int credits;
  const _CreditsBlock({
    required this.quota,
    required this.quotaUsed,
    required this.credits,
  });

  @override
  Widget build(BuildContext context) {
    final progress = quota > 0 ? (quotaUsed / quota).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quota > 0) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.freeMonthlyQuota,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
              Text(
                '$quotaUsed/$quota used',
                style: AppTheme.numberStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.surface2,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.resetsFirstMonth,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.inkHint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 13),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.purchasedCredits,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
            Text(
              '$credits credits remaining',
              style: AppTheme.numberStyle(fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}
