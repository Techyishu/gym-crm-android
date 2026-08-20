import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/widgets/auth_blob_background.dart';
import '../../../core/widgets/auth_form_kit.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;
  bool _memberMode = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    final error = await ref.read(authNotifierProvider.notifier).signUpWithGoogle();
    if (!mounted) return;
    if (error != null) setState(() { _error = error; _googleLoading = false; });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final email = _memberMode
        ? memberSyntheticEmail(_phoneCtrl.text.trim())
        : _emailCtrl.text.trim();
    final error = await ref.read(authNotifierProvider.notifier).signIn(
      email,
      _passwordCtrl.text,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() { _error = error; _loading = false; });
    }
    // Router redirect handles navigation after successful sign-in
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: AppTheme.background,
      body: AuthBlobBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Log in to see what's new today.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _AuthModeToggle(
                        memberMode: _memberMode,
                        onChanged: (v) => setState(() { _memberMode = v; _error = null; }),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],
                      // Google sign-in is hidden on iOS: Apple guideline 4.8
                      // would then require Sign in with Apple too, so iOS
                      // uses email/password only. Shown on web despite a
                      // known Safari-only OAuth bug (client-side PKCE
                      // exchange collides with ITP) — Google-only accounts
                      // need this to reach the web dashboard at all; Safari
                      // fix needs a server-side callback, not done yet.
                      if (!_memberMode && !isIOS) ...[
                        AuthGoogleButton(
                          loading: _googleLoading,
                          onPressed: (_loading || _googleLoading) ? null : _signInWithGoogle,
                        ),
                        const SizedBox(height: 20),
                        const AuthOrDivider(),
                        const SizedBox(height: 20),
                      ],
                      // Mobile OTP login — Android only. Hidden for now (feature
                      // disabled, not removed — flip back to `Platform.isAndroid`
                      // to re-enable).
                      // if (Platform.isAndroid) ...[
                      //   OutlinedButton.icon(
                      //     onPressed: (_loading || _googleLoading)
                      //         ? null
                      //         : () => context.push('/login/phone-otp'),
                      //     icon: const Icon(Icons.sms_outlined, size: 18),
                      //     label: const Text('Log in with mobile number'),
                      //     style: OutlinedButton.styleFrom(
                      //       minimumSize: const Size.fromHeight(52),
                      //       foregroundColor: AppTheme.textPrimary,
                      //       side: BorderSide(color: AppTheme.border),
                      //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      //       textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      //     ),
                      //   ),
                      //   const SizedBox(height: 20),
                      // ],
                      if (_memberMode) ...[
                        const AuthFieldLabel('Mobile number'),
                        const SizedBox(height: 6),
                        AuthPillField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          autocorrect: false,
                          hint: '98765 43210',
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Mobile number is required';
                            if (v.replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter a valid mobile number';
                            return null;
                          },
                        ),
                      ] else ...[
                        const AuthFieldLabel('Email'),
                        const SizedBox(height: 6),
                        AuthPillField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          hint: 'rahul@ironhouse.in',
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Email is required';
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      const AuthFieldLabel('Password'),
                      const SizedBox(height: 6),
                      AuthPillField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppTheme.inkHint, size: 20),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _memberMode
                            ? Text(
                                'Forgot password? Ask your gym for help.',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              )
                            : TextButton(
                                onPressed: () => context.push('/forgot-password'),
                                child: const Text('Forgot password?'),
                              ),
                      ),
                      const SizedBox(height: 12),
                      AuthGradientButton(
                        label: 'Log in',
                        loading: _loading,
                        onPressed: _loading ? null : _submit,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: _memberMode
                              ? [
                                  Text("New here? ",
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                                  GestureDetector(
                                    onTap: () => context.push('/login/member-signup'),
                                    child: const Text(
                                      'Create your account',
                                      style: TextStyle(
                                        color: AppTheme.accent,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ]
                              : [
                                  Text("Don't have an account? ",
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                                  GestureDetector(
                                    onTap: () => context.go('/signup'),
                                    child: const Text(
                                      'Create one',
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
                ),
              ),
            ),
          ),
        ),
      ),
    ),   // PopScope
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  final bool memberMode;
  final ValueChanged<bool> onChanged;
  const _AuthModeToggle({required this.memberMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'Staff', !memberMode, () => onChanged(false))),
          Expanded(child: _segment(context, 'Member', memberMode, () => onChanged(true))),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.background : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
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
        color: const Color(0xFFF8DFD7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEBC0B2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppTheme.error, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
