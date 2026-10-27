import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:country_picker/country_picker.dart';
import 'package:currency_picker/currency_picker.dart';
import '../../../core/services/app_events.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../../../core/utils/platform_info.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/widgets/redesign.dart' show SelectChip;
import '../../auth/providers/auth_provider.dart';

/// Step 1 of the "Set up your gym" wizard — canvas `w1`. Reached ONLY by the
/// Google-signup path: `signup_screen.dart` collects gym name inline on the
/// email-signup form and calls `setupGym()` directly, so an email signup
/// never routes here (see router.dart's user-resolution redirect).
class GymSetupScreen extends ConsumerStatefulWidget {
  const GymSetupScreen({super.key});

  @override
  ConsumerState<GymSetupScreen> createState() => _GymSetupScreenState();
}

final _digitsOnly = RegExp(r'^\d{4,14}$');

class _CurrencyServiceHolder {
  static final service = CurrencyService();
}

class _GymSetupScreenState extends ConsumerState<GymSetupScreen> {
  bool _submitting = false;
  String _error = '';

  final _gymNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  Country _country = Country.parse('IN');
  String _currencyCode = 'INR';

  bool _needsPhone = false;

  // Gym size, one tap. Saved as gyms.settings.member_count and used to tell
  // Google Ads which signups are real gyms (AppEvents.qualifiedGym).
  String? _memberCount;
  static const _sizes = ['under_30', '30_100', '100_300', 'over_300'];

  @override
  void initState() {
    super.initState();
    final user = ref.read(supabaseProvider).auth.currentUser;
    final meta = user?.userMetadata ?? {};
    final phone = (meta['phone'] ?? '').toString();
    if (phone.isNotEmpty) {
      _phoneCtrl.text = phone;
    } else {
      _needsPhone = true;
    }
  }

  @override
  void dispose() {
    _gymNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _gymNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.gymNameRequired);
      return;
    }
    if (_needsPhone) {
      final digits = _phoneCtrl.text.trim();
      if (!_digitsOnly.hasMatch(digits)) {
        setState(() => _error = context.l10n.validMobile);
        return;
      }
    }
    if (_memberCount == null) {
      setState(() => _error = context.l10n.memberCountRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });

    final error = await ref
        .read(authNotifierProvider.notifier)
        .setupGym(
          gymName: name,
          phone: _needsPhone && _phoneCtrl.text.trim().isNotEmpty
              ? '+${_country.phoneCode}${_phoneCtrl.text.trim()}'
              : null,
          gymType: null,
          memberCount: _memberCount,
          currency: _currencyCode,
          goals: [],
        );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    // This screen only renders for a brand-new account (the router only
    // sends users here when no profile exists yet), so registration and gym
    // setup are genuinely completing here for the first time.
    unawaited(AppEvents.signUpCompleted());
    unawaited(AppEvents.gymSetupCompleted(memberCount: _memberCount));
    if (_memberCount != 'under_30') {
      unawaited(AppEvents.qualifiedGym(_memberCount!));
    }

    final prefs = await SharedPreferences.getInstance();
    // home_route stays the real destination for future cold starts — the
    // wizard below is a one-time interstitial, not where a returning
    // session should land.
    await prefs.setString('home_route', '/staff/home');
    if (!mounted) return;
    ref.invalidate(userTypeProvider);
    ref.invalidate(staffProfileProvider);
    context.go('/staff/first-setup');
  }

  Future<void> _cancelSetup() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) _cancelSetup();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          // Same shell as FirstSetupScreen (steps 2-4) so the wizard reads as
          // one flow: top-aligned, 440 max width, canvas kit fields.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          context.l10n.setupStep(1),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.inkHint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const CanvasProgress(total: 4, filled: 1),
                    const SizedBox(height: 8),
                    CanvasHeading(
                      title: context.l10n.tellUsAboutGym,
                      subtitle: context.l10n.membersWillSee,
                    ),
                    const SizedBox(height: 18),
                    if (_error.isNotEmpty) ...[
                      CanvasBanner(message: _error),
                      const SizedBox(height: 16),
                    ],
                    CanvasField(
                      label: context.l10n.gymName,
                      child: TextField(
                        controller: _gymNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: canvasFieldDecoration(hint: 'FitZone Gym'),
                        onChanged: (_) {
                          if (_error.isNotEmpty) setState(() => _error = '');
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    CanvasField(
                      label: context.l10n.countryCurrency,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => showCountryPicker(
                          context: context,
                          showPhoneCode: true,
                          exclude: const ['PK', 'BD'],
                          onSelect: (c) => setState(() {
                            _country = c;
                            final match = _CurrencyServiceHolder.service
                                .getAll()
                                .where((cur) => cur.flag == c.countryCode)
                                .toList();
                            if (match.isNotEmpty) {
                              _currencyCode = match.first.code;
                            }
                          }),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 9, 10, 11),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_country.flagEmoji}  ${_country.name} · $_currencyCode',
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: AppTheme.ink,
                                ),
                              ),
                              Text(
                                context.l10n.change,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.inkHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.gymSizeQuestion,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final s in _sizes)
                          SelectChip(
                            label: switch (s) {
                              'under_30' => context.l10n.sizeUnder30,
                              '30_100' => '30–100',
                              '100_300' => '100–300',
                              _ => '300+',
                            },
                            selected: _memberCount == s,
                            onTap: () => setState(() {
                              _memberCount = s;
                              if (_error.isNotEmpty) _error = '';
                            }),
                          ),
                      ],
                    ),
                    if (_needsPhone) ...[
                      const SizedBox(height: 16),
                      CanvasField(
                        label: context.l10n.mobileNumber,
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 14,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: canvasFieldDecoration(hint: '9876543210')
                              .copyWith(
                                counterText: '',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Text(
                                    '+${_country.phoneCode}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.inkSoft,
                                    ),
                                  ),
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0,
                                ),
                              ),
                          onChanged: (_) {
                            if (_error.isNotEmpty) setState(() => _error = '');
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    CanvasButton(
                      label: isIOS
                          ? context.l10n.createGym
                          : context.l10n.continueLabel,
                      loadingLabel: context.l10n.saving,
                      loading: _submitting,
                      onPressed: _submit,
                    ),
                    if (!isIOS) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          context.l10n.freeTrialNoCard,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.inkHint,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
