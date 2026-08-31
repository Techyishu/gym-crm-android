import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:country_picker/country_picker.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_blob_background.dart';
import '../../../core/widgets/auth_form_kit.dart';
import '../providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

// MSG91 widget keys — client-facing widget config, not the sensitive
// server authkey (that lives only as the MSG91_AUTHKEY Supabase secret,
// used by the verify-phone-otp edge function).
const _msg91WidgetId = '366668696645313837343130';
const _msg91TokenAuth = '513484TSm4YfunB6a26866aP1';

/// Mobile OTP login (Android only) — reached from the login screen. Handles
/// both login and signup in one flow: verified phone maps to an existing
/// account if one exists, otherwise a new one is created and the router
/// sends the user to /gym-setup, same as a first-time Google sign-in.
class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  final _phoneCtrl = TextEditingController();
  Country _country = Country.parse('IN');

  bool _sending = false;
  String? _error;
  String? _reqId; // set once OTP has been sent — switches to code entry

  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _verifying = false;
  String? _otpError;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  static final _digitsOnly = RegExp(r'^\d{4,14}$');

  @override
  void initState() {
    super.initState();
    OTPWidget.initializeWidget(_msg91WidgetId, _msg91TokenAuth);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
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

  String get _fullIdentifier =>
      '${_country.phoneCode}${_phoneCtrl.text.trim()}';

  Future<void> _sendOtp() async {
    final digits = _phoneCtrl.text.trim();
    if (!_digitsOnly.hasMatch(digits)) {
      setState(() => _error = 'Enter a valid mobile number');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final response = await OTPWidget.sendOTP({'identifier': _fullIdentifier});
      if (response != null && response['type'] == 'success') {
        setState(() {
          _reqId = response['message'] as String;
          _sending = false;
        });
        _startResendTimer();
      } else {
        setState(() {
          _error = 'Could not send OTP. Please try again.';
          _sending = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not send OTP. Please try again.';
        _sending = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0 || _reqId == null) return;
    try {
      await OTPWidget.retryOTP({'reqId': _reqId});
      _startResendTimer();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Code resent via SMS.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resend code. Please try again.'),
        ),
      );
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6 || _reqId == null) return;
    setState(() {
      _verifying = true;
      _otpError = null;
    });

    try {
      final response = await OTPWidget.verifyOTP({
        'reqId': _reqId,
        'otp': code,
      });
      final accessToken =
          response?['access-token'] as String? ??
          (response?['message'] is String
              ? response!['message'] as String
              : null);
      if (response == null ||
          response['type'] != 'success' ||
          accessToken == null) {
        _failOtp('Incorrect code. Please try again.');
        return;
      }

      final error = await ref
          .read(authNotifierProvider.notifier)
          .verifyPhoneOtpToken(
            phone: _fullIdentifier,
            msg91AccessToken: accessToken,
          );

      if (!mounted) return;
      if (error != null) {
        _failOtp(error);
        return;
      }
      // Router redirect handles navigation from here (staff vs member vs
      // brand-new /gym-setup), same as email OTP login.
    } catch (e) {
      _failOtp('Verification failed. Please try again.');
    }
  }

  void _failOtp(String message) {
    if (!mounted) return;
    for (final c in _otpControllers) {
      c.clear();
    }
    _otpFocusNodes[0].requestFocus();
    setState(() {
      _otpError = message;
      _verifying = false;
    });
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
                child: _reqId != null ? _buildOtpStep() : _buildPhoneStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(AppIcons.arrowBack, color: AppTheme.textPrimary),
              onPressed: () => context.pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const AuthLogoBadge(),
        const SizedBox(height: 28),
        Text(
          'Log in with mobile',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "We'll text you a one-time code.",
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 28),
        if (_error != null) ...[
          _PhoneErrorBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        const AuthFieldLabel('Mobile number'),
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
                onSelect: (c) => setState(() => _country = c),
              ),
              child: Text(
                '${_country.flagEmoji} +${_country.phoneCode}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
        ),
        const SizedBox(height: 24),
        AuthGradientButton(
          label: 'Send code',
          loading: _sending,
          onPressed: _sending ? null : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final allFilled = _otpControllers.every((c) => c.text.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        const AuthLogoBadge(),
        const SizedBox(height: 28),
        Container(
          height: 56,
          width: 56,
          decoration: const BoxDecoration(
            color: AppTheme.accentSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            AppIcons.sms,
            color: AppTheme.accent,
            size: 26,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter verification code',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to\n',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
            children: [
              TextSpan(
                text: '+$_fullIdentifier',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
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
          _PhoneErrorBanner(message: _otpError!),
        ],
        const SizedBox(height: 22),
        AuthGradientButton(
          label: 'Verify',
          loading: _verifying,
          onPressed: (_verifying || !allFilled) ? null : _verifyOtp,
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: _resendCooldown > 0 ? null : _resendOtp,
          child: Text(
            _resendCooldown > 0
                ? 'Resend code in ${_resendCooldown}s'
                : 'Resend code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _resendCooldown > 0 ? AppTheme.inkHint : AppTheme.accent,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            _resendTimer?.cancel();
            for (final c in _otpControllers) {
              c.clear();
            }
            setState(() {
              _reqId = null;
              _otpError = null;
              _resendCooldown = 0;
            });
          },
          child: const Text(
            'Change number',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.inkHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// Duplicated from signup_screen.dart's private _OtpBox rather than shared,
// so this screen doesn't require touching signup_screen.dart.
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
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
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

class _PhoneErrorBanner extends StatelessWidget {
  final String message;
  const _PhoneErrorBanner({required this.message});

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
          const Icon(AppIcons.error, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.error, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
