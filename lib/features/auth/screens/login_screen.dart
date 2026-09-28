import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/platform_info.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../../../core/widgets/auth_form_kit.dart' show AuthGoogleButton;
import '../providers/auth_provider.dart';
import '../../../l10n/l10n.dart';

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
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CanvasBack(onTap: () => context.go('/welcome')),
                      const SizedBox(height: 8),
                      OrbitBrandPanel(
                        label: context.l10n.gymTeams,
                        headline: context.l10n.runFloorHeadline,
                      ),
                      const SizedBox(height: 12),
                      OrbitFormCard(
                        children: [
                          CanvasKicker(context.l10n.gymOwner),
                          const SizedBox(height: 5),
                          CanvasHeading(
                            title: context.l10n.welcomeBack,
                            subtitle: context.l10n.loginSubtitle,
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) ...[
                            CanvasBanner(message: _error!),
                            const SizedBox(height: 16),
                          ],
                          CanvasField(
                            label: context.l10n.email,
                            child: TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: canvasFieldDecoration(
                                hint: 'rahul@ironhouse.in',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return context.l10n.emailRequired;
                                }
                                if (!v.contains('@')) {
                                  return context.l10n.validEmail;
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          CanvasField(
                            label: context.l10n.password,
                            child: TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
                              decoration:
                                  canvasFieldDecoration(
                                    hint: '••••••••',
                                  ).copyWith(
                                    suffixIcon: CanvasShowToggle(
                                      obscured: _obscure,
                                      onTap: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? context.l10n.passwordRequired
                                  : null,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push('/forgot-password'),
                              child: Text(
                                context.l10n.forgotPassword,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ),
                          ),
                          CanvasButton(
                            label: context.l10n.login,
                            loadingLabel: context.l10n.loggingIn,
                            loading: _loading,
                            onPressed: _submit,
                          ),
                          if (!isIOS) ...[
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: const Divider(color: AppTheme.border),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    context.l10n.or,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.inkHint,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: const Divider(color: AppTheme.border),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            AuthGoogleButton(
                              loading: _googleLoading,
                              label: context.l10n.continueGoogle,
                              onPressed: (_loading || _googleLoading)
                                  ? null
                                  : _signInWithGoogle,
                            ),
                          ],
                          const SizedBox(height: 18),
                          Center(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  context.l10n.newGym,
                                  style: const TextStyle(
                                    color: AppTheme.inkSoft,
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go('/signup'),
                                  child: Text(
                                    context.l10n.createAccount,
                                    style: const TextStyle(
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
