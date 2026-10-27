import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/app_events.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/l10n.dart';

/// Shown on Home when a gym's WhatsApp reminders have stopped: this cycle's
/// quota (gyms.whatsapp_quota, the DB computed column) is used up and there
/// are no purchased credits left. The daily push says it once or twice; this
/// stays visible until the owner tops up. Renders nothing otherwise.
///
/// The X hides it for a day, not for good: members still aren't getting
/// reminders, so it comes back tomorrow if nothing changed.
class WhatsAppPausedBanner extends StatefulWidget {
  final Map<String, dynamic>? gym;
  const WhatsAppPausedBanner({super.key, required this.gym});

  @override
  State<WhatsAppPausedBanner> createState() => _WhatsAppPausedBannerState();
}

class _WhatsAppPausedBannerState extends State<WhatsAppPausedBanner> {
  static const _hideFor = Duration(days: 1);
  // Hidden until the stored dismiss time is read, so a dismissed banner never
  // flashes on screen for a frame.
  bool _hidden = true;
  bool _logged = false;

  String get _key => 'wa_paused_dismissed_${widget.gym?['id']}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_key);
    final dismissed =
        at != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) <
            _hideFor;
    if (mounted) setState(() => _hidden = dismissed);
  }

  Future<void> _dismiss() async {
    setState(() => _hidden = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final g = widget.gym;
    final quota = (g?['whatsapp_quota'] as num?)?.toInt() ?? 0;
    final used = (g?['whatsapp_monthly_quota_used'] as num?)?.toInt() ?? 0;
    final credits = (g?['whatsapp_credits'] as num?)?.toInt() ?? 0;
    final paused =
        g?['whatsapp_reminder_enabled'] == true &&
        quota > 0 &&
        used >= quota &&
        credits <= 0;
    if (!paused) return const SizedBox.shrink();
    if (!_logged) {
      _logged = true;
      AppEvents.whatsappPaused();
    }

    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.statusDangerBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  AppIcons.chat,
                  size: 20,
                  color: AppTheme.statusDanger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.whatsappPausedTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                // 44px tap target pulled into the card's corner padding.
                Transform.translate(
                  offset: const Offset(8, 0),
                  child: IconButton(
                    onPressed: _dismiss,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(
                      AppIcons.close,
                      size: 18,
                      color: AppTheme.ink,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.whatsappPausedBody(quota),
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                // Inline button: keep it content-width, not the theme's full width.
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  backgroundColor: AppTheme.statusDanger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.push('/staff/reminders'),
                child: Text(
                  l.whatsappBuyMore,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
