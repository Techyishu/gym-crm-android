import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_events.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';

/// Completes once per app launch: true when the offer popup is shown. The
/// generic "Trial ends in N days" dialog (PlanExpiryBanner) waits on it and
/// steps aside, so a trial owner never gets two popups stacked.
final promotionShown = Completer<bool>();

void markNoPromotion() {
  if (!promotionShown.isCompleted) promotionShown.complete(false);
}

/// Shows the highest-priority live row of public.promotions that fits this
/// gym ('all' / 'trial' / 'expired' / 'paying') and hasn't been seen too
/// recently on this device (frequency: once / daily / always). One popup per
/// app session at most; the caller makes sure of that.
Future<void> maybeShowPromotion(
  BuildContext context, {
  required String billingState,
}) async {
  try {
    await _showPromotion(context, billingState);
  } finally {
    markNoPromotion();
  }
}

Future<void> _showPromotion(BuildContext context, String billingState) async {
  List<Map<String, dynamic>> rows;
  try {
    // RLS already limits this to active rows inside their dates.
    rows = await Supabase.instance.client
        .from('promotions')
        .select()
        .inFilter('audience', ['all', billingState])
        .order('priority', ascending: false)
        .order('created_at', ascending: false);
  } catch (_) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  Map<String, dynamic>? promo;
  for (final p in rows) {
    final seen = prefs.getInt('promo_seen_${p['id']}');
    final due = switch (p['frequency']) {
      'once' => seen == null,
      'daily' =>
        seen == null ||
            now.difference(DateTime.fromMillisecondsSinceEpoch(seen)).inHours >=
                24,
      _ => true,
    };
    if (due) {
      promo = p;
      break;
    }
  }
  if (promo == null || !context.mounted) return;

  final id = promo['id'] as String;
  if (!promotionShown.isCompleted) promotionShown.complete(true);
  await prefs.setInt('promo_seen_$id', now.millisecondsSinceEpoch);
  await AppEvents.promotionViewed(id);
  if (!context.mounted) return;

  final tapped = await showDialog<bool>(
    context: context,
    builder: (_) => _PromotionDialog(promo: promo!),
  );
  if (tapped != true || !context.mounted) return;

  await AppEvents.promotionClicked(id);
  final value = promo['cta_value'] as String?;
  if (!context.mounted) return;
  switch (promo['cta_action']) {
    case 'route' when value != null && value.startsWith('/'):
      context.push(value);
    case 'url' when value != null:
      await launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
    // 'paywall': cta_value, when set, is the plan length to pre-select —
    // e.g. '12mo' for a yearly offer, so the owner lands on the discounted card.
    default:
      context.push(
        value != null && RegExp(r'^(1|3|6|12)mo$').hasMatch(value)
            ? '/staff/subscription?term=$value'
            : '/staff/subscription',
      );
  }
}

class _PromotionDialog extends StatelessWidget {
  final Map<String, dynamic> promo;
  const _PromotionDialog({required this.promo});

  // Photo card: image (16:10) with a gold badge and the close button on it,
  // then headline, text, optional price row, one main button and a quiet
  // dismiss. Every part except the title is optional in public.promotions.
  static const _gold = Color(0xFFE3C07A);

  String? _str(String key) {
    final v = promo[key] as String?;
    return v == null || v.trim().isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final image = _str('image_url');
    final body = _str('body');
    final badge = _str('badge');
    final priceNow = _str('price_now');
    final priceWas = _str('price_was');
    final endsAt = DateTime.tryParse(promo['ends_at'] as String? ?? '');
    final ends = endsAt == null
        ? null
        : 'Ends ${DateFormat('d MMM').format(endsAt.toLocal())}';

    final close = IconButton(
      onPressed: () => Navigator.pop(context, false),
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.surface.withValues(alpha: 0.92),
        minimumSize: const Size(40, 40),
      ),
      icon: const Icon(AppIcons.close, size: 18, color: AppTheme.ink),
    );
    final badgeChip = badge == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _gold,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badge.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppTheme.ink,
              ),
            ),
          );

    return Dialog(
      backgroundColor: AppTheme.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image != null)
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Container(color: AppTheme.accent),
                      ),
                      if (badgeChip != null)
                        Positioned(left: 14, bottom: 14, child: badgeChip),
                      Positioned(top: 10, right: 10, child: close),
                    ],
                  ),
                )
              else
                // No image: badge and close share a top row instead.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 10, 0),
                  child: Row(children: [?badgeChip, const Spacer(), close]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      promo['title'] as String,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.5,
                          color: AppTheme.inkSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (priceNow != null || ends != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          if (priceNow != null)
                            Text(
                              priceNow,
                              style: AppTheme.numberStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.ink,
                              ),
                            ),
                          if (priceWas != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              priceWas,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.inkHint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (ends != null)
                            Text(
                              ends,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.statusActive,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          promo['cta_label'] as String? ?? 'See plans',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        promo['dismiss_label'] as String? ?? 'Maybe later',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ),
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
