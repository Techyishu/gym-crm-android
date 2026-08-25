import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../billing/billing_access.dart';
import '../theme/app_theme.dart';
import '../utils/platform_info.dart';

const _kDismissedKeyPrefix = 'plan_expiry_popup_dismissed_';

/// Own in-app "notification" for plan/trial expiry — no OneSignal, no cost.
/// Pops a dialog once per calendar day per gym; reappears the next day if not renewed.
class PlanExpiryBanner extends StatefulWidget {
  final Map<String, dynamic> gym;
  const PlanExpiryBanner({super.key, required this.gym});

  @override
  State<PlanExpiryBanner> createState() => _PlanExpiryBannerState();
}

class _PlanExpiryBannerState extends State<PlanExpiryBanner> {
  bool _shown = false;

  String get _todayKey {
    final now = DateTime.now();
    final gymId = widget.gym['id'] as String? ?? '';
    return '$_kDismissedKeyPrefix${gymId}_${now.year}-${now.month}-${now.day}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shown) {
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
    }
  }

  Future<void> _maybeShow() async {
    // iOS billing is entirely StoreKit-driven — Apple already sends its own
    // renewal/expiry notices, so this custom nag popup never shows on iOS.
    if (isIOS) return;

    // Never show this the moment a brand-new gym lands on its own dashboard —
    // with a 1-day trial, "days left <= 3" is true from the very first
    // second, so this used to be the first thing a new owner ever saw.
    final createdAt = DateTime.tryParse(widget.gym['created_at'] as String? ?? '');
    if (createdAt != null &&
        DateTime.now().toUtc().difference(createdAt.toUtc()) < const Duration(hours: 1)) {
      return;
    }

    final daysLeft = planExpiryDaysRemaining(widget.gym);
    if (daysLeft == null || daysLeft > 3) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_todayKey) ?? false) return;
    await prefs.setBool(_todayKey, true);

    if (!mounted) return;

    final isTrial = widget.gym['trial_ends_at'] != null && widget.gym['plan_expires_at'] == null;
    final expired = daysLeft < 0;

    final String title;
    final String body;
    if (expired) {
      title = isTrial ? 'Your trial has ended' : 'Your plan has expired';
      body = 'Renew now to avoid losing access to your gym data.';
    } else if (daysLeft == 0) {
      title = isTrial ? 'Trial ends today' : 'Plan expires today';
      body = 'Renew now to keep everything running smoothly.';
    } else {
      title = isTrial ? 'Trial ends in $daysLeft day${daysLeft == 1 ? '' : 's'}' : 'Plan expires in $daysLeft day${daysLeft == 1 ? '' : 's'}';
      body = 'Renew soon to avoid any interruption.';
    }

    final tint = expired || daysLeft == 0 ? AppTheme.statusDanger : AppTheme.statusWarn;
    final tintBg = expired || daysLeft == 0 ? AppTheme.statusDangerBg : AppTheme.statusWarnBg;
    final icon = expired || daysLeft == 0 ? Icons.error_outline : Icons.schedule;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: tintBg, borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, size: 26, color: tint),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.4)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(dialogContext),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: const Text('Maybe later',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(dialogContext);
                        context.push('/staff/subscription');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: const Text('Renew now',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
