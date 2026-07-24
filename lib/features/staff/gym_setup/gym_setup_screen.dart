import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:country_picker/country_picker.dart';
import 'package:currency_picker/currency_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';

class GymSetupScreen extends ConsumerStatefulWidget {
  const GymSetupScreen({super.key});

  @override
  ConsumerState<GymSetupScreen> createState() => _GymSetupScreenState();
}

const _gymTypes = [
  ('strength', '🏋️', 'Strength & Fitness'),
  ('crossfit', '⚡', 'CrossFit / Functional'),
  ('yoga', '🧘', 'Yoga / Wellness'),
  ('martial_arts', '🥊', 'Martial Arts'),
  ('swimming', '🏊', 'Swimming'),
  ('sports', '🏆', 'Sports Academy'),
  ('dance', '💃', 'Dance / Zumba'),
  ('other', '🏃', 'Other'),
];

const _setupSteps = [
  'Creating your gym profile',
  'Setting up your dashboard',
  'Preparing your workspace',
];

final _digitsOnly = RegExp(r'^\d{4,14}$');

class _CurrencyServiceHolder {
  static final service = CurrencyService();
}

class _GymSetupScreenState extends ConsumerState<GymSetupScreen> {
  bool _submitting = false;
  bool _submitted = false;
  int _setupStepIndex = 0;
  String _error = '';

  final _gymNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _gymType = '';
  Country _country = Country.parse('IN');
  String _currencyCode = 'INR';

  String _prefillName = '';
  bool _needsPhone = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(supabaseProvider).auth.currentUser;
    final meta = user?.userMetadata ?? {};
    final first = (meta['first_name'] ?? meta['given_name'] ?? '').toString().trim();
    final last = (meta['last_name'] ?? meta['family_name'] ?? '').toString().trim();
    if (first.isNotEmpty) _prefillName = last.isNotEmpty ? '$first $last' : first;
    final phone = (meta['phone'] ?? '').toString();
    if (phone.isNotEmpty) {
      _phoneCtrl.text = phone;
    } else {
      // No phone field on iOS (App Review 5.1.1).
      _needsPhone = !Platform.isIOS;
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
      _setupStepIndex = 0;
      _error = '';
    });

    // Animate through setup steps while the RPC runs.
    final ticker = Stream.periodic(const Duration(milliseconds: 900))
        .take(_setupSteps.length - 1)
        .listen((_) {
      if (mounted) setState(() => _setupStepIndex++);
    });

    final error = await ref.read(authNotifierProvider.notifier).setupGym(
          gymName: name,
          phone: _needsPhone && _phoneCtrl.text.trim().isNotEmpty
              ? '+${_country.phoneCode}${_phoneCtrl.text.trim()}'
              : null,
          gymType: _gymType.isEmpty ? null : _gymType,
          currency: _currencyCode,
          goals: [],
        );

    ticker.cancel();
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    setState(() {
      _submitted = true;
      _setupStepIndex = _setupSteps.length - 1;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_route', '/staff/dashboard');
    if (!mounted) return;
    ref.invalidate(userTypeProvider);
    ref.invalidate(staffProfileProvider);
    context.go('/staff/dashboard');
  }

  Future<void> _cancelSetup() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go('/login');
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
          child: _submitting || _submitted ? _buildSubmitting() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Brand
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                      color: AppTheme.accent, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.fitness_center, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('GymCRM',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Container(
                decoration: AppTheme.cardDecoration(radius: 16),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppTheme.border))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SET UP YOUR GYM',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: AppTheme.inkSoft)),
                          const SizedBox(height: 4),
                          Text(
                            _prefillName.isNotEmpty
                                ? 'Welcome, $_prefillName!'
                                : 'Almost there!',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.ink),
                          ),
                          const SizedBox(height: 4),
                          Text("Tell us about your gym and you're in.",
                              style:
                                  TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Gym name
                          _label('Gym name'),
                          TextField(
                            controller: _gymNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration:
                                const InputDecoration(hintText: 'e.g. FitZone Gym'),
                            onChanged: (_) {
                              if (_error.isNotEmpty) setState(() => _error = '');
                            },
                          ),

                          // Country — drives both the phone dial code and
                          // the gym's currency (via Currency.flag, which is
                          // the ISO2 country code in the currency_picker data).
                          const SizedBox(height: 16),
                          _label('Country'),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
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
                                if (match.isNotEmpty) _currencyCode = match.first.code;
                              }),
                            ),
                            child: InputDecorator(
                              decoration: const InputDecoration(),
                              child: Text('${_country.flagEmoji}  ${_country.name}  ($_currencyCode)',
                                  style: const TextStyle(fontSize: 14, color: AppTheme.ink)),
                            ),
                          ),

                          // Phone (Google users only)
                          if (_needsPhone) ...[
                            const SizedBox(height: 16),
                            _label('Mobile number (optional)'),
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              maxLength: 14,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: '98765 43210',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  child: Text('${_country.flagEmoji} +${_country.phoneCode}',
                                      style: const TextStyle(fontSize: 14)),
                                ),
                                prefixIconConstraints: const BoxConstraints(minWidth: 0),
                              ),
                              onChanged: (_) {
                                if (_error.isNotEmpty) setState(() => _error = '');
                              },
                            ),
                          ],

                          // Gym type (optional)
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _label('Gym type'),
                              const SizedBox(width: 6),
                              Text('optional',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.inkHint,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _gymTypes.map((t) {
                              final sel = _gymType == t.$1;
                              return PillChip(
                                label: '${t.$2}  ${t.$3}',
                                selected: sel,
                                onTap: () => setState(() {
                                  _gymType = sel ? '' : t.$1;
                                }),
                              );
                            }).toList(),
                          ),

                          // Error
                          if (_error.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(_error,
                                style: const TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],

                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _submit,
                            child: Text(Platform.isIOS ? 'Create Gym' : 'Start Free Trial'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              if (!Platform.isIOS)
                Center(
                  child: Text('1-day free trial · No credit card needed',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.inkHint,
                          letterSpacing: 0.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitting() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                    color: AppTheme.accent, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.fitness_center, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('GymCRM',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Setting up your gym',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink)),
            const SizedBox(height: 4),
            Text('This only takes a second…',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.cardDecoration(radius: 12),
              child: Column(
                children: List.generate(_setupSteps.length, (i) {
                  final done = i < _setupStepIndex;
                  final active = i == _setupStepIndex;
                  return Padding(
                    padding: EdgeInsets.only(
                        bottom: i < _setupSteps.length - 1 ? 12 : 0),
                    child: Row(
                      children: [
                        Container(
                          height: 24,
                          width: 24,
                          decoration: BoxDecoration(
                            color: done || active
                                ? AppTheme.accent
                                : AppTheme.surface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: done
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 14)
                              : active
                                  ? const SizedBox(
                                      height: 12,
                                      width: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : Text('${i + 1}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.inkHint)),
                        ),
                        const SizedBox(width: 12),
                        Text(_setupSteps[i],
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: done || active
                                    ? AppTheme.ink
                                    : AppTheme.inkHint)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.inkSoft)),
      );
}
