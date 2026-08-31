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
import '../../../core/utils/platform_info.dart';
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

  @override
  void initState() {
    super.initState();
    final user = ref.read(supabaseProvider).auth.currentUser;
    final meta = user?.userMetadata ?? {};
    final phone = (meta['phone'] ?? '').toString();
    if (phone.isNotEmpty) {
      _phoneCtrl.text = phone;
    } else {
      // No phone field on iOS (App Review 5.1.1).
      _needsPhone = !isIOS;
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
      setState(() => _error = 'Gym name is required.');
      return;
    }
    if (_needsPhone) {
      final digits = _phoneCtrl.text.trim();
      // Optional (App Review 5.1.1) — validate format only when provided.
      if (digits.isNotEmpty && !_digitsOnly.hasMatch(digits)) {
        setState(() => _error = 'Enter a valid mobile number.');
        return;
      }
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
    unawaited(AppEvents.gymSetupCompleted());

    final prefs = await SharedPreferences.getInstance();
    // home_route stays the real destination for future cold starts — the
    // wizard below is a one-time interstitial, not where a returning
    // session should land.
    await prefs.setString('home_route', '/staff/dashboard');
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Set up your gym',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                        const Text(
                          'Step 1 of 4',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.inkHint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(4, (i) {
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                            height: 5,
                            decoration: BoxDecoration(
                              color: i == 0 ? AppTheme.ink : AppTheme.surface2,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Tell us about your gym',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.2,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'This is what members will see.',
                      style: TextStyle(fontSize: 14.5, color: AppTheme.inkSoft),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.statusDangerBg,
                          border: Border.all(color: AppTheme.statusDanger),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.statusDanger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _field(
                      label: 'Gym name',
                      child: TextField(
                        controller: _gymNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'FitZone Gym',
                        ),
                        onChanged: (_) {
                          if (_error.isNotEmpty) setState(() => _error = '');
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _field(
                      label: 'Country and currency',
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                              const Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.inkHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_needsPhone) ...[
                      const SizedBox(height: 16),
                      _field(
                        label: 'Mobile number',
                        optional: true,
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 14,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '9876543210',
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
                    SizedBox(
                      height: 52,
                      child: Stack(
                        children: [
                          ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(isIOS ? 'Create Gym' : 'Continue'),
                          ),
                          if (_submitting)
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppTheme.accentDark,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Saving…',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isIOS) ...[
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          '3-day free trial · No credit card needed',
                          style: TextStyle(
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

  Widget _field({
    required String label,
    required Widget child,
    bool optional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              const Text(
                '— optional',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkHint,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
