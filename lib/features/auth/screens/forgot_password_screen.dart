import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../providers/auth_provider.dart';

/// Canvas `forgot` / `forgotSent`. There's no `reset` (set-new-password)
/// counterpart here — Supabase's reset-link email opens the web app, not
/// this one, so a Flutter screen for it would have nothing to deep-link
/// into. See [[canvas-auth-gym-setup]].
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await ref
        .read(authNotifierProvider.notifier)
        .resetPassword(_emailCtrl.text.trim());

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (error != null) {
        _error = error;
      } else {
        _sent = true;
        _startResendTimer();
      }
    });
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
              child: _sent ? _buildSent() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CanvasBack(onTap: () => context.pop()),
          const SizedBox(height: 16),
          const CanvasHeading(
            title: 'Reset your password',
            subtitle:
                'Enter the email you signed up with. We will send a reset '
                'link.',
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            CanvasBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          CanvasField(
            label: 'Email',
            child: TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: canvasFieldDecoration(hint: 'rahul@ironhouse.in'),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          CanvasButton(
            label: 'Send reset link',
            loading: _loading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: const Text(
            '✓',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.accent,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.2,
              color: AppTheme.ink,
            ),
            text: 'Link sent',
          ),
        ),
        const SizedBox(height: 7),
        Text.rich(
          TextSpan(
            text: 'Check ',
            style: const TextStyle(
              fontSize: 14.5,
              color: AppTheme.inkSoft,
              height: 1.6,
            ),
            children: [
              TextSpan(
                text: _emailCtrl.text.trim(),
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(
                text: ' and open the reset link. It expires in one hour.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text.rich(
            TextSpan(
              text: 'Not in your inbox? Check spam',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.inkSoft,
                height: 1.6,
              ),
              children: [
                TextSpan(
                  text: _resendCooldown > 0
                      ? ', or send it again in ${_resendCooldown}s.'
                      : '.',
                ),
              ],
            ),
          ),
        ),
        if (_resendCooldown == 0) ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _submit,
              child: const Text(
                'Send again',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        CanvasSecondaryButton(
          label: 'Back to log in',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
