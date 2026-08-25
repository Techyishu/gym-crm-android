import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/adaptive_sheet.dart';
import '../billing/billing_screen.dart' show PlanFormSheet;
import '../members/members_screen.dart' show showAddMemberSheet;

/// Shown once, right after a brand-new gym is created (both the email and
/// Google signup paths route here instead of straight to the dashboard).
///
/// Forces exactly two pieces of *real* data before the owner ever sees an
/// empty dashboard: one membership plan (without which "Add member" dead-ends
/// on "No plans yet" anyway) and one real member. Both steps stay skippable —
/// this app's own funnel data shows friction added before value is shown
/// kills signups, so the moment either step feels like work instead of
/// progress, the owner can leave and land on the dashboard's own
/// "Getting started" checklist instead.
class FirstSetupScreen extends StatefulWidget {
  const FirstSetupScreen({super.key});

  @override
  State<FirstSetupScreen> createState() => _FirstSetupScreenState();
}

class _FirstSetupScreenState extends State<FirstSetupScreen> {
  bool _planCreated = false;
  bool _busy = false;

  void _goToDashboard() {
    if (mounted) context.go('/staff/dashboard');
  }

  Future<void> _setMonthlyFee() async {
    setState(() => _busy = true);
    final created = await showAdaptiveSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PlanFormSheet(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (created != null) _planCreated = true;
    });
  }

  Future<void> _addFirstMember() async {
    setState(() => _busy = true);
    await showAddMemberSheet(context);
    // The sheet closes the same way whether the member was saved or the
    // sheet was dismissed — there's no separate signal to distinguish them,
    // and forcing that distinction here isn't worth the extra complexity.
    // Either way, this screen's job is done.
    _goToDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _planCreated ? 1 : 0.5,
                        minHeight: 4,
                        backgroundColor: AppTheme.surface2,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  TextButton(
                    onPressed: _busy ? null : _goToDashboard,
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _planCreated ? _AddMemberStep(busy: _busy, onAdd: _addFirstMember) : _SetFeeStep(busy: _busy, onSet: _setMonthlyFee),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetFeeStep extends StatelessWidget {
  final bool busy;
  final VoidCallback onSet;
  const _SetFeeStep({required this.busy, required this.onSet});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(color: AppTheme.accentSoft, shape: BoxShape.circle),
          child: const Icon(Icons.sell_outlined, color: AppTheme.accent, size: 26),
        ),
        const SizedBox(height: 20),
        const Text(
          'Set your monthly fee',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.ink, height: 1.2, letterSpacing: -0.4),
        ),
        const SizedBox(height: 10),
        const Text(
          'This is what most memberships will cost. You can add more plans — quarterly, annual — anytime from Billing.',
          style: TextStyle(fontSize: 14.5, color: AppTheme.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: busy ? null : onSet,
            child: busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Set monthly fee'),
          ),
        ),
      ],
    );
  }
}

class _AddMemberStep extends StatelessWidget {
  final bool busy;
  final VoidCallback onAdd;
  const _AddMemberStep({required this.busy, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(color: AppTheme.accentSoft, shape: BoxShape.circle),
          child: const Icon(Icons.person_add_alt_1_outlined, color: AppTheme.accent, size: 26),
        ),
        const SizedBox(height: 20),
        const Text(
          'Add your first member',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.ink, height: 1.2, letterSpacing: -0.4),
        ),
        const SizedBox(height: 10),
        const Text(
          'See your dashboard come alive the moment you do — dues, renewals and check-ins all start working from here.',
          style: TextStyle(fontSize: 14.5, color: AppTheme.inkSoft, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: busy ? null : onAdd,
            child: busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add a member'),
          ),
        ),
      ],
    );
  }
}
