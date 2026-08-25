import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_picker/country_picker.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/app_events.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/widgets/auth_blob_background.dart';
import '../../../core/widgets/auth_form_kit.dart';
import '../providers/auth_provider.dart';

/// Matches the web `/(auth)/signup` form 1:1 in fields, validation and flow:
/// first name, last name, email, +91 mobile, password (with strength meter),
/// "Continue with Google", and the post-submit "Check your email" state.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gymNameCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;
  bool _acceptedTerms = false;
  bool _termsError = false;
  String? _error;
  String? _sentTo; // when set → render OTP verification screen
  Country _country = Country.parse('IN');
  String _currencyCode = 'INR'; // follows _country; set gym currency at signup

  // One place to change country: keeps the phone dial code and the gym's
  // currency in sync whether the user taps the Country row or the phone flag.
  void _selectCountry(Country c) {
    setState(() {
      _country = c;
      final match = CurrencyService()
          .getAll()
          .where((cur) => cur.flag == c.countryCode)
          .toList();
      if (match.isNotEmpty) _currencyCode = match.first.code;
    });
  }

  // OTP verification state
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  String? _otpError;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // Optional field — only length is validated once a country is picked,
  // since digit rules vary per country.
  static final _digitsOnly = RegExp(r'^\d{4,14}$');

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _gymNameCtrl.dispose();
    _firstCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    for (final c in _otpControllers) { c.dispose(); }
    for (final f in _otpFocusNodes) { f.dispose(); }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6) return;
    setState(() {
      _verifying = true;
      _otpError = null;
    });

    final notifier = ref.read(authNotifierProvider.notifier);
    // Hold the router guard through verify + gym creation so the redirect
    // doesn't briefly land the user on /gym-setup between the two calls.
    signupHandshakeInProgress.value = true;

    final error = await notifier.verifyEmailOtp(email: _sentTo!, token: code);

    if (!mounted) {
      signupHandshakeInProgress.value = false;
      return;
    }
    if (error != null) {
      signupHandshakeInProgress.value = false;
      for (final c in _otpControllers) { c.clear(); }
      _otpFocusNodes[0].requestFocus();
      setState(() {
        _otpError = error;
        _verifying = false;
      });
      return;
    }

    // Session now exists — account creation is genuinely done here, distinct
    // from gym setup below (a signed-up user with a setup failure should
    // still count as a registration).
    unawaited(AppEvents.signUpCompleted());

    // Session now exists — create the gym + owner profile inline (was the
    // separate /gym-setup screen).
    final phoneDigits = _phoneCtrl.text.trim();
    final setupError = await notifier.setupGym(
      gymName: _gymNameCtrl.text.trim(),
      phone: phoneDigits.isEmpty ? null : '+${_country.phoneCode}$phoneDigits',
      currency: _currencyCode,
      goals: [],
    );

    if (!mounted) {
      signupHandshakeInProgress.value = false;
      return;
    }
    if (setupError != null) {
      // Setup failed but the session is live and has no profile — release the
      // guard and let the router route to /gym-setup so the user can retry.
      signupHandshakeInProgress.value = false;
      setState(() {
        _otpError = setupError;
        _verifying = false;
      });
      return;
    }

    unawaited(AppEvents.gymSetupCompleted());

    final prefs = await SharedPreferences.getInstance();
    // home_route stays the real destination for future cold starts — the
    // first-setup screen below is a one-time interstitial, not where a
    // returning session should land.
    await prefs.setString('home_route', '/staff/dashboard');
    ref.invalidate(userTypeProvider);
    ref.invalidate(staffProfileProvider);
    signupHandshakeInProgress.value = false;
    if (!mounted) return;
    context.go('/staff/first-setup');
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    final error = await ref
        .read(authNotifierProvider.notifier)
        .resendEmailOtp(_sentTo!);
    if (!mounted) return;
    if (error == null) {
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code resent — check your email.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  // 0 empty · 1 weak · 2 fair · 3 strong — same rule as the web meter
  int get _strength {
    final p = _passwordCtrl.text;
    if (p.isEmpty) return 0;
    if (p.length < 8) return 1;
    return RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[0-9]').hasMatch(p) ? 3 : 2;
  }

  Future<void> _signUpWithGoogle() async {
    if (!_acceptedTerms) {
      setState(() => _termsError = true);
      return;
    }
    setState(() => _googleLoading = true);
    final error = await ref.read(authNotifierProvider.notifier).signUpWithGoogle();
    if (!mounted) return;
    setState(() => _googleLoading = false);
    if (error != null) setState(() => _error = error);
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    if (!_acceptedTerms) {
      setState(() => _termsError = true);
      return;
    }
    if (!valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final notifier = ref.read(authNotifierProvider.notifier);
    final phoneDigits = _phoneCtrl.text.trim();
    final error = await notifier.signUp(
      firstName: _firstCtrl.text.trim(),
      lastName: '',
      email: _emailCtrl.text.trim(),
      phone: phoneDigits.isEmpty ? '' : '+${_country.phoneCode}$phoneDigits',
      password: _passwordCtrl.text,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _loading = false;
      });
      return;
    }

    // If email confirmation is disabled the user is now signed in and the
    // router redirect will carry them to gym-setup automatically.
    if (notifier.hasSession) return;

    setState(() {
      _sentTo = _emailCtrl.text.trim();
      _loading = false;
    });
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AuthBlobBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _sentTo != null ? _buildOtpScreen() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sign-up form ──────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Create your gym',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 28),
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],

          // Continue with Google — hidden on iOS (Apple guideline 4.8
          // would then require Sign in with Apple too). Shown on web despite
          // a known Safari-only OAuth bug — Google-only accounts need this
          // to reach the web dashboard; fix needs a server-side callback.
          // Google signups finish gym creation on the /gym-setup screen
          // (they never fill this form).
          if (!isIOS) ...[
            AuthGoogleButton(
              loading: _googleLoading,
              onPressed: (_googleLoading || _loading) ? null : _signUpWithGoogle,
              label: 'Sign up with Google',
            ),
            const SizedBox(height: 20),
            const AuthOrDivider(),
            const SizedBox(height: 20),
          ],

          // Gym name — was a separate onboarding screen; merged in here so
          // email signups land straight on the dashboard after OTP verify.
          const AuthFieldLabel('Gym name'),
          const SizedBox(height: 6),
          AuthPillField(
            controller: _gymNameCtrl,
            textCapitalization: TextCapitalization.words,
            hint: 'FitZone Gym',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Gym name is required' : null,
          ),
          const SizedBox(height: 16),

          // Country & currency — one pick sets the gym's currency (and the
          // phone dial code below). Always visible: iOS hides the phone field,
          // so this is the only place iOS owners set their currency.
          const AuthFieldLabel('Country & currency'),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => showCountryPicker(
              context: context,
              showPhoneCode: true,
              exclude: const ['PK', 'BD'],
              onSelect: _selectCountry,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_country.flagEmoji}  ${_country.name}  ($_currencyCode)',
                        style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: AppTheme.inkHint, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Labelled "Name" (not "First name") — last name isn't collected
          // here, so calling this "first" would promise a field that doesn't
          // exist. Still wired to the same firstName param/column; asked
          // later in Settings if the owner wants a last name filled in, and
          // setup_gym already tolerates it being blank.
          const AuthFieldLabel('Name'),
          const SizedBox(height: 6),
          AuthPillField(
            controller: _firstCtrl,
            textCapitalization: TextCapitalization.words,
            hint: 'Rahul',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),

          const AuthFieldLabel('Email'),
          const SizedBox(height: 6),
          AuthPillField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            hint: 'rahul@ironhouse.in',
            validator: (v) {
              final value = v?.trim() ?? '';
              final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
              return ok ? null : 'Enter a valid email address';
            },
          ),
          const SizedBox(height: 16),

          // Mobile number with +91 prefix — hidden on iOS (App Review 5.1.1:
          // phone is not required for core functionality).
          if (!isIOS) ...[
            const AuthFieldLabel('Mobile number (optional)'),
            const SizedBox(height: 6),
            AuthPillField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 14,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              hint: '9876543210',
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: GestureDetector(
                  onTap: () => showCountryPicker(
                    context: context,
                    showPhoneCode: true,
                    exclude: const ['PK', 'BD'],
                    onSelect: _selectCountry,
                  ),
                  child: Text('${_country.flagEmoji} +${_country.phoneCode}',
                      style: const TextStyle(fontSize: 14)),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null; // optional
                return _digitsOnly.hasMatch(value)
                    ? null
                    : 'Enter a valid mobile number';
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('Tap the flag to change country',
                  style: TextStyle(fontSize: 12, color: AppTheme.inkHint)),
            ),
          ],
          const SizedBox(height: 16),

          // Password + strength meter
          const AuthFieldLabel('Password'),
          const SizedBox(height: 6),
          AuthPillField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            hint: 'Min. 8 characters',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppTheme.inkHint, size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (v) => (v == null || v.length < 8)
                ? 'Password must be at least 8 characters'
                : null,
          ),
          if (_strength > 0) ...[
            const SizedBox(height: 8),
            _StrengthMeter(strength: _strength),
          ],
          const SizedBox(height: 20),

          // Terms & privacy acceptance (required)
          _TermsCheckbox(
            value: _acceptedTerms,
            showError: _termsError,
            onChanged: (v) => setState(() {
              _acceptedTerms = v;
              if (v) _termsError = false;
            }),
          ),
          const SizedBox(height: 24),

          AuthGradientButton(
            label: 'Create your gym  →',
            loading: _loading,
            onPressed: (_loading || _googleLoading) ? null : _submit,
          ),
          const SizedBox(height: 24),
          Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Already on GymCRM? ',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: const Text(
                    'Log in',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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

  // ── OTP verification screen ───────────────────────────────────────────────
  Widget _buildOtpScreen() {
    final allFilled = _otpControllers.every((c) => c.text.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        Container(
          height: 56,
          width: 56,
          decoration: const BoxDecoration(color: AppTheme.accentSoft, shape: BoxShape.circle),
          child: const Icon(Icons.mark_email_read_outlined, color: AppTheme.accent, size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter verification code',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to\n',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
            children: [
              TextSpan(
                text: _sentTo,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // 6-digit OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            6,
            (i) => _OtpBox(
              controller: _otpControllers[i],
              focusNode: _otpFocusNodes[i],
              onChanged: (v) {
                if (v.isNotEmpty && i < 5) {
                  _otpFocusNodes[i + 1].requestFocus();
                }
                // Auto-submit when last digit entered
                if (_otpControllers.every((c) => c.text.isNotEmpty)) {
                  _verifyOtp();
                } else {
                  setState(() {});
                }
              },
              onBackspace: () {
                if (i > 0) {
                  _otpControllers[i - 1].clear();
                  _otpFocusNodes[i - 1].requestFocus();
                  setState(() {});
                }
              },
            ),
          ),
        ),

        if (_otpError != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(message: _otpError!),
        ],
        const SizedBox(height: 22),

        AuthGradientButton(
          label: 'Verify',
          loading: _verifying,
          onPressed: (_verifying || !allFilled) ? null : _verifyOtp,
        ),
        const SizedBox(height: 18),

        // Resend
        GestureDetector(
          onTap: _resendCooldown > 0 ? null : _resendOtp,
          child: Text(
            _resendCooldown > 0
                ? 'Resend code in ${_resendCooldown}s'
                : 'Resend code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color:
                  _resendCooldown > 0 ? AppTheme.inkHint : AppTheme.accent,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Change email
        GestureDetector(
          onTap: () {
            _resendTimer?.cancel();
            for (final c in _otpControllers) { c.clear(); }
            setState(() {
              _sentTo = null;
              _otpError = null;
              _resendCooldown = 0;
            });
          },
          child: const Text(
            'Change email',
            style: TextStyle(
                fontSize: 13,
                color: AppTheme.inkHint,
                fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  final int strength; // 1..3
  const _StrengthMeter({required this.strength});

  @override
  Widget build(BuildContext context) {
    const colors = [Colors.transparent, AppTheme.statusDanger, AppTheme.statusWarn, AppTheme.ink];
    const labels = ['', 'Weak', 'Fair', 'Strong'];
    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              final filled = (i + 1) <= strength;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: filled ? colors[strength] : AppTheme.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 8),
        Text(labels[strength],
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors[strength])),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 54,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspace();
          }
        },
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.ink),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.ink, width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.statusDangerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEBC0B2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(color: AppTheme.error, fontSize: 14))),
        ],
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final bool showError;
  final ValueChanged<bool> onChanged;

  const _TermsCheckbox({
    required this.value,
    required this.showError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: AppTheme.ink,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: showError
                    ? const BorderSide(color: AppTheme.error, width: 2)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'I agree to the ',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => onChanged(!value),
                  children: [
                    TextSpan(
                      text: 'Terms of Service',
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.push('/legal/terms'),
                    ),
                    TextSpan(
                      text: ' and ',
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => onChanged(!value),
                    ),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.push('/legal/privacy'),
                    ),
                    TextSpan(
                      text: '.',
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => onChanged(!value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (showError)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 34),
            child: Text(
              'Please accept the Terms of Service and Privacy Policy to continue.',
              style: TextStyle(fontSize: 12, color: AppTheme.error),
            ),
          ),
      ],
    );
  }
}
