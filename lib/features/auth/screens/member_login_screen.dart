import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../providers/auth_provider.dart';

/// Canvas `mLogin` — split out of the old combined [LoginScreen] toggle once
/// [WelcomeScreen] became the real entry point.
class MemberLoginScreen extends ConsumerStatefulWidget {
  const MemberLoginScreen({super.key});

  @override
  ConsumerState<MemberLoginScreen> createState() => _MemberLoginScreenState();
}

class _MemberLoginScreenState extends ConsumerState<MemberLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = memberSyntheticEmail(_phoneCtrl.text.trim());
    final error = await ref
        .read(authNotifierProvider.notifier)
        .signIn(email, _passwordCtrl.text);

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
                      const CanvasKicker('Gym member'),
                      const SizedBox(height: 5),
                      const CanvasHeading(
                        title: 'Log in',
                        subtitle: 'Use the mobile number your gym has on file.',
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        CanvasBanner(message: _error!),
                        const SizedBox(height: 16),
                      ],
                      CanvasField(
                        label: 'Mobile number',
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: canvasFieldDecoration(hint: '98765 43210')
                              .copyWith(
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
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0,
                                ),
                              ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Mobile number is required';
                            }
                            if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                              return 'Enter a valid mobile number';
                            }
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
                          onPressed: () => context.push('/login/member/help'),
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
                      const SizedBox(height: 20),
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'First time here? ',
                              style: TextStyle(
                                color: AppTheme.inkSoft,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/login/member-signup'),
                              child: const Text(
                                'Create your account',
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
