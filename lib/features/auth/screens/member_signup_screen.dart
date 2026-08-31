import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../providers/auth_provider.dart';

const _msg91WidgetId = '366668696645313837343130';
const _msg91TokenAuth = '513484TSm4YfunB6a26866aP1';

/// Member self-serve portal signup: gym code -> phone -> OTP -> set password.
/// Reached from the login screen's member mode. Staff must have already
/// added the member (with a phone) — this only claims/verifies an existing
/// `members` row via `verify-phone-otp`'s gym-scoped path, it never creates
/// a member record itself.
class MemberSignupScreen extends ConsumerStatefulWidget {
  const MemberSignupScreen({super.key});

  @override
  ConsumerState<MemberSignupScreen> createState() => _MemberSignupScreenState();
}

enum _Step { gymCode, phone, otp, password }

class _MemberSignupScreenState extends ConsumerState<MemberSignupScreen> {
  _Step _step = _Step.gymCode;
  bool _busy = false;
  String? _error;

  final _codeCtrl = TextEditingController();
  String? _gymId;
  String? _gymName;

  final _phoneCtrl = TextEditingController();
  String? _reqId;
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  int _resendCooldown = 0;
  Timer? _resendTimer;

  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  static final _digitsOnly = RegExp(r'^\d{4,14}$');
  String get _fullIdentifier => '91${_phoneCtrl.text.trim()}';

  @override
  void initState() {
    super.initState();
    OTPWidget.initializeWidget(_msg91WidgetId, _msg91TokenAuth);
  }

  @override
  void dispose() {
    // Safety net: if this screen is torn down mid-signup (session created,
    // password not yet set), don't leave the router stuck ignoring auth
    // changes forever.
    signupHandshakeInProgress.value = false;
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
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

  Future<void> _resolveGymCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit gym code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client.rpc(
        'resolve_gym_by_member_code',
        params: {'code': code},
      );
      final rows = res as List<dynamic>;
      if (rows.isEmpty) {
        setState(() {
          _error = 'No gym found with this code';
          _busy = false;
        });
        return;
      }
      final row = rows.first as Map<String, dynamic>;
      setState(() {
        _gymId = row['id'] as String;
        _gymName = row['name'] as String;
        _step = _Step.phone;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not look up gym. Please try again.';
        _busy = false;
      });
    }
  }

  Future<void> _sendOtp() async {
    final digits = _phoneCtrl.text.trim();
    if (!_digitsOnly.hasMatch(digits)) {
      setState(() => _error = 'Enter a valid mobile number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await OTPWidget.sendOTP({'identifier': _fullIdentifier});
      if (response != null && response['type'] == 'success') {
        setState(() {
          _reqId = response['message'] as String;
          _step = _Step.otp;
          _busy = false;
        });
        _startResendTimer();
      } else {
        setState(() {
          _error = 'Could not send OTP. Please try again.';
          _busy = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not send OTP. Please try again.';
        _busy = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0 || _reqId == null) return;
    try {
      await OTPWidget.retryOTP({'reqId': _reqId});
      _startResendTimer();
    } catch (_) {}
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6 || _reqId == null) return;
    setState(() {
      _busy = true;
      _error = null;
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

      // Set before verifyPhoneOtpToken — that call creates a real session via
      // verifyOTP(), and the router redirects on every auth change. Without
      // this guard it navigates straight to the member portal before the
      // password step ever renders (same issue signUp() has, see
      // [signupHandshakeInProgress]'s doc comment). Cleared once password is
      // actually set (or in dispose() as a safety net).
      signupHandshakeInProgress.value = true;
      final error = await ref
          .read(authNotifierProvider.notifier)
          .verifyPhoneOtpToken(
            phone: _fullIdentifier,
            msg91AccessToken: accessToken,
            gymId: _gymId,
          );

      if (!mounted) return;
      if (error != null) {
        signupHandshakeInProgress.value = false;
        _failOtp(error);
        return;
      }
      setState(() {
        _step = _Step.password;
        _busy = false;
      });
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
      _error = message;
      _busy = false;
    });
  }

  Future<void> _setPassword() async {
    if (_passwordCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authNotifierProvider.notifier)
        .setPassword(_passwordCtrl.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _busy = false;
      });
      return;
    }
    // Password is set — safe to let the router take over now.
    signupHandshakeInProgress.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: switch (_step) {
                _Step.gymCode => _buildGymCodeStep(),
                _Step.phone => _buildPhoneStep(),
                _Step.otp => _buildOtpStep(),
                _Step.password => _buildPasswordStep(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGymCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CanvasBack(onTap: () => context.pop()),
        const SizedBox(height: 16),
        const CanvasProgress(total: 4, filled: 1),
        const SizedBox(height: 18),
        const CanvasHeading(
          title: 'Enter your gym code',
          subtitle:
              'A 6-digit code from your gym. Ask at the desk if you do not '
              'have it.',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        CanvasField(
          label: 'Gym code',
          child: TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
            ),
            decoration: canvasFieldDecoration(
              hint: '123456',
            ).copyWith(counterText: ''),
          ),
        ),
        const SizedBox(height: 18),
        CanvasButton(
          label: 'Continue',
          loading: _busy,
          onPressed: _resolveGymCode,
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CanvasBack(
          onTap: () => setState(() {
            _step = _Step.gymCode;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        const CanvasProgress(total: 4, filled: 2),
        const SizedBox(height: 18),
        CanvasKicker(_gymName ?? 'Your gym'),
        const SizedBox(height: 5),
        const CanvasHeading(
          title: 'Your mobile number',
          subtitle:
              'Use the number your gym registered. We will text a '
              'one-time code.',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        CanvasField(
          label: 'Mobile number',
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: canvasFieldDecoration(hint: '9876543210').copyWith(
              counterText: '',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '+91',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
            ),
          ),
        ),
        const SizedBox(height: 18),
        CanvasButton(label: 'Send code', loading: _busy, onPressed: _sendOtp),
      ],
    );
  }

  Widget _buildOtpStep() {
    final allFilled = _otpControllers.every((c) => c.text.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CanvasBack(
          onTap: () => setState(() {
            _step = _Step.phone;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        const CanvasProgress(total: 4, filled: 3),
        const SizedBox(height: 18),
        CanvasHeading(
          title: 'Enter the code',
          subtitle: 'Sent by SMS to +$_fullIdentifier',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            6,
            (i) => _OtpBox(
              controller: _otpControllers[i],
              focusNode: _otpFocusNodes[i],
              onChanged: (v) {
                if (v.isNotEmpty && i < 5) _otpFocusNodes[i + 1].requestFocus();
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
        const SizedBox(height: 18),
        CanvasButton(
          label: 'Verify',
          loadingLabel: 'Verifying…',
          loading: _busy,
          onPressed: allFilled ? _verifyOtp : null,
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _resendCooldown > 0 ? null : _resendOtp,
            child: Text(
              _resendCooldown > 0
                  ? 'Resend code in ${_resendCooldown}s'
                  : 'Resend code',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _resendCooldown > 0 ? AppTheme.inkHint : AppTheme.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CanvasProgress(total: 4, filled: 4),
        const SizedBox(height: 18),
        const CanvasHeading(
          title: 'Set a password',
          subtitle:
              'Next time you can log in with your mobile number and this '
              'password. No code needed.',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        CanvasField(
          label: 'Password',
          child: TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: canvasFieldDecoration(hint: 'Min. 6 characters')
                .copyWith(
                  suffixIcon: CanvasShowToggle(
                    obscured: _obscure,
                    onTap: () => setState(() => _obscure = !_obscure),
                  ),
                ),
          ),
        ),
        const SizedBox(height: 18),
        CanvasButton(label: 'Finish', loading: _busy, onPressed: _setPassword),
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
