import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router.dart' show kPendingFirstSetup;

import '../../../core/billing/advance_payment_date.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/auth_canvas_kit.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/redesign.dart' show SelectChip;

/// Canvas `w2`/`w3`/`w4` — steps 2–4 of the "Set up your gym" wizard. Step 1
/// (gym details) is either collected inline on the signup form (email path)
/// or on `/gym-setup` (Google path); see [[canvas-auth-gym-setup]].
///
/// Every field here is inline on the page, matching the canvas — not a
/// button that opens a sheet. Forces exactly two pieces of *real* data
/// before the owner ever sees an empty dashboard: one membership plan
/// (without which "Add member" dead-ends on "No plans yet" anyway) and one
/// real member. The plan step isn't skippable — matching the canvas, which
/// offers no skip there either — but the member step stays skippable.
class FirstSetupScreen extends ConsumerStatefulWidget {
  const FirstSetupScreen({super.key});

  @override
  ConsumerState<FirstSetupScreen> createState() => _FirstSetupScreenState();
}

class _FirstSetupScreenState extends ConsumerState<FirstSetupScreen> {
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _member;
  bool _reachedReady = false;

  int get _stepIndex => _reachedReady ? 4 : (_plan != null ? 3 : 2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Step $_stepIndex of 4',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CanvasProgress(total: 4, filled: _stepIndex),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: _reachedReady
                      ? _ReadyStep(plan: _plan, member: _member)
                      : _plan != null
                      ? _AddMemberStep(
                          plan: _plan!,
                          onDone: (member) => setState(() {
                            _member = member;
                            _reachedReady = true;
                          }),
                          onSkip: () => setState(() => _reachedReady = true),
                        )
                      : _CreatePlanStep(
                          onCreated: (plan) => setState(() => _plan = plan),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 2 — create the first plan (canvas w2) ───────────────────────────────

class _CreatePlanStep extends ConsumerStatefulWidget {
  final ValueChanged<Map<String, dynamic>> onCreated;
  const _CreatePlanStep({required this.onCreated});

  @override
  ConsumerState<_CreatePlanStep> createState() => _CreatePlanStepState();
}

class _CreatePlanStepState extends ConsumerState<_CreatePlanStep> {
  final _nameCtrl = TextEditingController(text: 'Monthly membership');
  final _priceCtrl = TextEditingController();
  final _featureCtrl = TextEditingController();
  String _interval = 'monthly';
  final List<String> _features = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final f = _featureCtrl.text.trim();
    if (f.isEmpty) return;
    setState(() {
      _features.add(f);
      _featureCtrl.clear();
    });
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Plan name is required.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _error = 'Enter a price for this plan.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final created = Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
              'create_membership_plan_secure',
              params: {
                'p_gym_id': gymId,
                'p_name': name,
                'p_price': price,
                'p_billing_interval': _interval,
                'p_features': _features,
                'p_is_active': true,
              },
            )
            as Map,
      );
      widget.onCreated(created);
    } catch (e) {
      setState(() => _error = 'Could not create the plan. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CanvasHeading(
          title: 'Create your first membership plan',
          subtitle: 'Set the plan your members will join.',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        CanvasField(
          label: 'Plan name',
          child: TextField(
            controller: _nameCtrl,
            decoration: canvasFieldDecoration(hint: 'Monthly membership'),
          ),
        ),
        const SizedBox(height: 16),
        CanvasField(
          label: 'Price',
          child: TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: canvasFieldDecoration(hint: '1500').copyWith(
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  currencySymbol,
                  style: const TextStyle(
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
        const SizedBox(height: 16),
        const Text(
          'Billing cycle',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final i in const [
              ('monthly', 'Monthly'),
              ('quarterly', 'Quarterly'),
              ('annual', 'Yearly'),
            ])
              SelectChip(
                label: i.$2,
                selected: _interval == i.$1,
                onTap: () => setState(() => _interval = i.$1),
              ),
          ],
        ),
        const SizedBox(height: 16),
        CanvasField(
          label: "What's included",
          optional: true,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _featureCtrl,
                  decoration: canvasFieldDecoration(hint: 'Add a feature'),
                  onSubmitted: (_) => _addFeature(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addFeature,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_features.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final f in _features)
                GestureDetector(
                  onTap: () => setState(() => _features.remove(f)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$f  ✕',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        CanvasButton(
          label: 'Create plan & continue',
          loadingLabel: 'Creating plan…',
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ── Step 3 — add the first member (canvas w3) ────────────────────────────────

class _AddMemberStep extends ConsumerStatefulWidget {
  final Map<String, dynamic> plan;
  final ValueChanged<Map<String, dynamic>> onDone;
  final VoidCallback onSkip;
  const _AddMemberStep({
    required this.plan,
    required this.onDone,
    required this.onSkip,
  });

  @override
  ConsumerState<_AddMemberStep> createState() => _AddMemberStepState();
}

class _AddMemberStepState extends ConsumerState<_AddMemberStep> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _customIdCtrl = TextEditingController();
  final _paidCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _moreDetails = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _customIdCtrl.dispose();
    _paidCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_firstCtrl.text.trim().isEmpty) {
      setState(() => _error = 'First name is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;
      final today = DateTime.now().toIso8601String().split('T').first;
      final interval = switch (widget.plan['billing_interval'] as String?) {
        'quarterly' => 3,
        'annual' => 12,
        _ => 1,
      };
      final nextPaymentDate = advancePaymentDate(today, months: interval);

      final member = await client
          .from('members')
          .insert({
            'gym_id': gymId,
            'first_name': _firstCtrl.text.trim(),
            if (_lastCtrl.text.trim().isNotEmpty)
              'last_name': _lastCtrl.text.trim(),
            if (_phoneCtrl.text.trim().isNotEmpty)
              'phone': phoneWithCountryCode(_phoneCtrl.text),
            if (_emailCtrl.text.trim().isNotEmpty)
              'email': _emailCtrl.text.trim(),
            if (_customIdCtrl.text.trim().isNotEmpty)
              'custom_id': _customIdCtrl.text.trim(),
            if (_notesCtrl.text.trim().isNotEmpty)
              'notes': _notesCtrl.text.trim(),
            'status': 'active',
            'joined_at': today,
            if (nextPaymentDate != null) 'next_payment_date': nextPaymentDate,
            'billing_interval_months': interval,
          })
          .select('id')
          .single();

      await client.from('memberships').insert({
        'member_id': member['id'],
        'plan_id': widget.plan['id'],
        'status': 'active',
        'starts_at': DateTime.now().toUtc().toIso8601String(),
        'discount_amount': 0,
      });

      final paid = double.tryParse(_paidCtrl.text.trim()) ?? 0;
      if (paid > 0) {
        final invoice = await client
            .from('invoices')
            .select('id')
            .eq('member_id', member['id'])
            .eq('status', 'open')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (invoice != null) {
          await recordInvoicePayment(
            invoiceId: invoice['id'] as String,
            amount: paid,
            method: 'cash',
            recordedBy: client.auth.currentUser?.id,
          );
        }
      }

      widget.onDone({
        'name': [
          _firstCtrl.text.trim(),
          _lastCtrl.text.trim(),
        ].where((s) => s.isNotEmpty).join(' '),
      });
    } catch (e) {
      setState(() => _error = 'Could not add this member. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CanvasHeading(
          title: 'Add your first member',
          subtitle: 'You can add more members anytime.',
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[
          CanvasBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: CanvasField(
                label: 'First name',
                child: TextField(
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: canvasFieldDecoration(hint: 'Amit'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CanvasField(
                label: 'Last name',
                optional: true,
                child: TextField(
                  controller: _lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: canvasFieldDecoration(hint: 'Sharma'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CanvasField(
          label: 'Mobile number',
          optional: true,
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: canvasFieldDecoration(hint: '9876543210').copyWith(
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
        const SizedBox(height: 16),
        CanvasField(
          label: 'Email',
          optional: true,
          child: TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: canvasFieldDecoration(hint: 'amit@example.com'),
          ),
        ),
        const SizedBox(height: 16),
        CanvasField(
          label: 'Plan',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${widget.plan['name']} · ${formatCurrency((widget.plan['price'] as num).toDouble())}',
              style: const TextStyle(fontSize: 15, color: AppTheme.ink),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!_moreDetails)
          GestureDetector(
            onTap: () => setState(() => _moreDetails = true),
            behavior: HitTestBehavior.opaque,
            child: const Text(
              'More details — member ID, amount paid, notes',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkSoft,
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CanvasField(
                label: 'Member ID',
                optional: true,
                child: TextField(
                  controller: _customIdCtrl,
                  decoration: canvasFieldDecoration(hint: 'GYM-001'),
                ),
              ),
              const SizedBox(height: 14),
              CanvasField(
                label: 'Amount paid',
                optional: true,
                child: TextField(
                  controller: _paidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: canvasFieldDecoration(hint: '0').copyWith(
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        currencySymbol,
                        style: const TextStyle(
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
              const SizedBox(height: 14),
              CanvasField(
                label: 'Notes',
                optional: true,
                child: TextField(
                  controller: _notesCtrl,
                  decoration: canvasFieldDecoration(
                    hint: 'Anything to remember',
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        CanvasButton(
          label: 'Add member',
          loadingLabel: 'Adding member…',
          loading: _loading,
          onPressed: _submit,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _loading ? null : widget.onSkip,
            child: const Text(
              'Skip for now',
              style: TextStyle(
                color: AppTheme.inkSoft,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step 4 — ready (canvas w4) ───────────────────────────────────────────────

class _ReadyStep extends ConsumerWidget {
  final Map<String, dynamic>? plan;
  final Map<String, dynamic>? member;
  const _ReadyStep({required this.plan, required this.member});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymName =
        (ref.watch(staffProfileProvider).valueOrNull?['gyms']
                as Map<String, dynamic>?)?['name']
            as String? ??
        'Your gym';
    final planName = plan?['name'] as String?;
    final planPrice = (plan?['price'] as num?)?.toDouble();
    final planInterval = plan?['billing_interval'] as String?;
    final memberName = member?['name'] as String?;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppTheme.mintOnDark,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '✓',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkCard,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your gym is ready',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: AppTheme.onDark,
                  ),
                ),
                const SizedBox(height: 18),
                _ReadyRow(label: 'Gym created', detail: gymName),
                if (planName != null && planPrice != null) ...[
                  const SizedBox(height: 11),
                  _ReadyRow(
                    label: 'First plan created',
                    detail:
                        '${formatCurrency(planPrice)}'
                        '${planInterval != null ? ' $planInterval' : ''}',
                  ),
                ],
                if (memberName != null) ...[
                  const SizedBox(height: 11),
                  _ReadyRow(label: 'First member added', detail: memberName),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () async {
                // Clear before navigating, or the router redirects straight
                // back here.
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(kPendingFirstSetup);
                if (context.mounted) context.go('/staff/dashboard');
              },
              child: const Text('Go to dashboard'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'You can add more plans, members and staff from the dashboard.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.inkHint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  final String label;
  final String detail;
  const _ReadyRow({required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 19,
          height: 19,
          decoration: const BoxDecoration(
            color: AppTheme.darkCard2,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            '✓',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.mintOnDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.onDark,
              ),
              children: [
                TextSpan(
                  text: ' — $detail',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppTheme.onDarkSoft,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
