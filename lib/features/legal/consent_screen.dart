import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// DPDP Act 2023 consent keys. Bump the `_v1` suffix to re-prompt everyone
/// after a material change to what we collect or who we share it with.
const kConsentGiven = 'dpdp_consent_v1';
const kConsentAnalytics = 'consent_analytics';
const kConsentMarketing = 'consent_marketing';

/// Applies stored consent to the SDKs that read it. Called at startup and
/// whenever the user changes their choice.
Future<void> applyStoredConsent(SharedPreferences prefs) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
    prefs.getBool(kConsentAnalytics) ?? false,
  );
}

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _analytics = true;
  bool _marketing = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // First run defaults to opt-in-looking switches, but nothing is stored
      // (and nothing collected) until the user actually taps a button.
      _analytics = prefs.getBool(kConsentAnalytics) ?? true;
      _marketing = prefs.getBool(kConsentMarketing) ?? true;
      _loaded = true;
    });
  }

  Future<void> _save({required bool analytics, required bool marketing}) async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kConsentAnalytics, analytics);
    await prefs.setBool(kConsentMarketing, marketing);
    await prefs.setBool(kConsentGiven, true);
    await applyStoredConsent(prefs);
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Privacy choices saved')),
      );
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: canPop
          ? AppBar(title: const Text('Privacy & data'))
          : null,
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(20, canPop ? 8 : 24, 20, 8),
                      children: [
                        if (!canPop) ...[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppTheme.accentSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.lock_outline,
                                color: AppTheme.accent, size: 26),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Your data,\nyour choice',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.8,
                              color: AppTheme.ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const Text(
                          'Under the Digital Personal Data Protection Act, 2023 we need '
                          'your consent before we collect anything. Pick what you are '
                          'comfortable with — you can change it any time in Settings.',
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.5,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 22),

                        _ConsentTile(
                          icon: Icons.people_outline,
                          title: 'Run your gym',
                          body:
                              'Your name, email, phone, gym details, member records, '
                              'attendance and payments. Stored on Supabase servers. '
                              'The app cannot work without this.',
                          value: true,
                          locked: true,
                          onChanged: null,
                        ),
                        const SizedBox(height: 12),
                        _ConsentTile(
                          icon: Icons.info_outline,
                          title: 'Improve the app',
                          body:
                              'Anonymous usage and crash reports via Google Firebase '
                              'and Sentry, so we can find bugs and slow screens.',
                          value: _analytics,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _analytics = v),
                        ),
                        const SizedBox(height: 12),
                        _ConsentTile(
                          icon: Icons.notifications_outlined,
                          title: 'Product updates',
                          body:
                              'Push notifications about new features, offers and tips, '
                              'sent through OneSignal. Never sold or shared with '
                              'advertisers.',
                          value: _marketing,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _marketing = v),
                        ),

                        const SizedBox(height: 22),
                        _RightsNote(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ── Actions ────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      color: AppTheme.surface,
                      border: Border(top: BorderSide(color: AppTheme.border)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () => _save(
                                    analytics: _analytics,
                                    marketing: _marketing,
                                  ),
                          child: Text(canPop ? 'Save choices' : 'Agree & continue'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => _save(analytics: false, marketing: false),
                          child: const Text('Essential only'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => context.push('/legal/privacy'),
                              child: const Text('Privacy Policy'),
                            ),
                            TextButton(
                              onPressed: () => context.push('/legal/terms'),
                              child: const Text('Terms'),
                            ),
                          ],
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

class _ConsentTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  const _ConsentTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: AppTheme.inkSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.statusNeutralBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'REQUIRED',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppTheme.statusNeutral,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.accentFg,
            activeTrackColor: AppTheme.accent,
          ),
        ],
      ),
    );
  }
}

class _RightsNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your rights',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'You can ask us to show, correct or delete your data, nominate someone '
            'to act for you, or withdraw consent — from Settings, or by writing to '
            'our Grievance Officer at privacy@gymcrm.app. If we do not resolve it, '
            'you may complain to the Data Protection Board of India.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
