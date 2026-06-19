import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
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

  // OTP verification state
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  String? _otpError;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // Mirrors web INDIAN_MOBILE = /^[6-9]\d{9}$/
  static final _indianMobile = RegExp(r'^[6-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
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

    final error = await ref
        .read(authNotifierProvider.notifier)
        .verifyEmailOtp(email: _sentTo!, token: code);

    if (!mounted) return;
    if (error != null) {
      for (final c in _otpControllers) { c.clear(); }
      _otpFocusNodes[0].requestFocus();
      setState(() {
        _otpError = error;
        _verifying = false;
      });
    }
    // On success the auth state change fires → GoRouter redirects automatically
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
    final error = await notifier.signUp(
      firstName: _firstCtrl.text.trim(),
      lastName: _lastCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
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
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _sentTo != null ? _buildOtpScreen() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header (dark brand bar) ───────────────────────────────────────────────
  Widget _header({String? tagline}) {
    return Container(
      width: double.infinity,
      color: AppTheme.ink,
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 28),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fitness_center, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'GymCRM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (tagline != null) ...[
            const SizedBox(height: 8),
            Text(
              tagline,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  // ── Sign-up form ──────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(tagline: '1-day free trial · No card needed'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Container(
            decoration: AppTheme.cardDecoration(radius: 16),
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Start your free trial',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1 day full access. No credit card required.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 16),
                  ],

                  // Continue with Google — hidden on iOS (Apple guideline 4.8
                  // would then require Sign in with Apple too).
                  if (!Platform.isIOS) ...[
                    OutlinedButton.icon(
                      onPressed: (_googleLoading || _loading) ? null : _signUpWithGoogle,
                      icon: _googleLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const _GoogleIcon(),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or', style: TextStyle(color: AppTheme.inkHint, fontSize: 13)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // First + last name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LabeledField(
                          label: 'First name',
                          child: TextFormField(
                            controller: _firstCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(hintText: 'Rahul'),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LabeledField(
                          label: 'Last name',
                          child: TextFormField(
                            controller: _lastCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(hintText: 'Sharma'),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _LabeledField(
                    label: 'Email',
                    child: TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'you@example.com'),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                        return ok ? null : 'Enter a valid email address';
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mobile number with +91 prefix
                  _LabeledField(
                    label: 'Mobile number',
                    helper: '10 digits starting with 6, 7, 8, or 9',
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '9876543210',
                        prefixIcon: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Text('🇮🇳 +91', style: TextStyle(fontSize: 14)),
                        ),
                        prefixIconConstraints: BoxConstraints(minWidth: 0),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        return _indianMobile.hasMatch(value)
                            ? null
                            : 'Enter a valid 10-digit mobile number';
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Password + strength meter
                  _LabeledField(
                    label: 'Password',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            hintText: 'Min. 8 characters',
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 8)
                              ? 'Password must be at least 8 characters'
                              : null,
                        ),
                        if (_strength > 0) ...[
                          const SizedBox(height: 8),
                          _StrengthMeter(strength: _strength),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Terms & privacy acceptance (required)
                  _TermsCheckbox(
                    value: _acceptedTerms,
                    showError: _termsError,
                    onChanged: (v) => setState(() {
                      _acceptedTerms = v;
                      if (v) _termsError = false;
                    }),
                  ),
                  const SizedBox(height: 18),

                  ElevatedButton(
                    onPressed: (_loading || _googleLoading) ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Already have an account?  ',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              color: AppTheme.ink,
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
            ),
          ),
        ),
      ],
    );
  }

  // ── OTP verification screen ───────────────────────────────────────────────
  Widget _buildOtpScreen() {
    final allFilled = _otpControllers.every((c) => c.text.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Container(
            decoration: AppTheme.cardDecoration(radius: 16),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: const BoxDecoration(color: AppTheme.activeBg, shape: BoxShape.circle),
                  child: const Icon(Icons.mark_email_read_outlined, color: AppTheme.ink, size: 26),
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

                ElevatedButton(
                  onPressed: (_verifying || !allFilled) ? null : _verifyOtp,
                  child: _verifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Verify'),
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
                          _resendCooldown > 0 ? AppTheme.inkHint : AppTheme.ink,
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;
  const _LabeledField({required this.label, required this.child, this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ),
        child,
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(helper!, style: TextStyle(fontSize: 12, color: AppTheme.inkHint)),
          ),
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
        border: Border.all(color: const Color(0xFFFECACA)),
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

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();
  @override
  Widget build(BuildContext context) {
    return const Text('G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
        ));
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
