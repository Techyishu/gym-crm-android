import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../../../core/widgets/auth_form_kit.dart' show AuthGoogleButton;
import '../providers/auth_provider.dart';

/// Canvas `oLogin` — owner-only. The member path split out to
/// [MemberLoginScreen] (`/login/member`) once [WelcomeScreen] became the
/// real entry point; this screen no longer has a Staff/Member toggle.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    final error = await ref
        .read(authNotifierProvider.notifier)
        .signUpWithGoogle();
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _googleLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await ref
        .read(authNotifierProvider.notifier)
        .signIn(_emailCtrl.text.trim(), _passwordCtrl.text);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
    // Router redirect handles navigation after successful sign-in.
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/welcome');
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CanvasBack(onTap: () => context.go('/welcome')),
                      const SizedBox(height: 16),
                      const CanvasKicker('Gym owner'),
                      const SizedBox(height: 5),
                      const CanvasHeading(
                        title: 'Welcome back',
                        subtitle: "Log in to run today's floor.",
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        CanvasBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],
                      CanvasField(
                        label: 'Email',
                        child: TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: canvasFieldDecoration(
                            hint: 'rahul@ironhouse.in',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      CanvasField(
                        label: 'Password',
                        child: TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          decoration: canvasFieldDecoration(hint: '••••••••')
                              .copyWith(
                                suffixIcon: CanvasShowToggle(
                                  obscured: _obscure,
                                  onTap: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Password is required'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.push('/forgot-password'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CanvasButton(
                        label: 'Log in',
                        loadingLabel: 'Logging in…',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      // Google sign-in is hidden on iOS: Apple guideline 4.8
                      // would then require Sign in with Apple too, so iOS
                      // uses email/password only. Shown on web despite a
                      // known Safari-only OAuth bug (client-side PKCE
                      // exchange collides with ITP) — Google-only accounts
                      // need this to reach the web dashboard at all; Safari
                      // fix needs a server-side callback, not done yet.
                      if (!isIOS) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: const [
                            Expanded(child: Divider(color: AppTheme.border)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.inkHint,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: AppTheme.border)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        AuthGoogleButton(
                          loading: _googleLoading,
                          onPressed: (_loading || _googleLoading)
                              ? null
                              : _signInWithGoogle,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'New gym? ',
                              style: TextStyle(
                                color: AppTheme.inkSoft,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.go('/signup'),
                              child: const Text(
                                'Create an account',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
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
    );
  }
}
