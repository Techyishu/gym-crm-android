import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// Lists every gym branch the current owner/staff member is linked to,
/// lets them switch the active branch (every screen re-scopes to it), and
/// lets an owner add a new branch via the create_gym_branch RPC.
class GymBranchesSheet extends ConsumerWidget {
  const GymBranchesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(myGymBranchesProvider);
    final activeGymIdAsync = ref.watch(gymIdProvider);
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final isOwner = role == 'owner';

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Gym Branches',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ),
            ),
            Flexible(
              child: branchesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load branches: $e', style: const TextStyle(color: AppTheme.statusDanger)),
                ),
                data: (branches) {
                  final activeGymId = activeGymIdAsync.valueOrNull;
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: branches.length,
                    itemBuilder: (context, i) {
                      final row = branches[i];
                      final gym = row['gyms'] as Map<String, dynamic>?;
                      final gymId = row['gym_id'] as String;
                      final name = (gym?['name'] as String?) ?? 'Gym';
                      final active = gymId == activeGymId;
                      return ListTile(
                        leading: Icon(
                          active ? Icons.check_circle : Icons.business_outlined,
                          color: active ? AppTheme.accent : AppTheme.inkHint,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                            color: AppTheme.ink,
                          ),
                        ),
                        subtitle: Text((row['role'] as String?) ?? ''),
                        onTap: active
                            ? null
                            : () async {
                                await ref.read(authNotifierProvider.notifier).switchActiveGym(gymId);
                                if (context.mounted) Navigator.of(context).pop();
                              },
                      );
                    },
                  );
                },
              ),
            ),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showAdaptiveSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => const _AddGymBranchSheet(),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Branch'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddGymBranchSheet extends ConsumerStatefulWidget {
  const _AddGymBranchSheet();

  @override
  ConsumerState<_AddGymBranchSheet> createState() => _AddGymBranchSheetState();
}

class _AddGymBranchSheetState extends ConsumerState<_AddGymBranchSheet> {
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Branch name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref.read(authNotifierProvider.notifier).createGymBranch(
          gymName: name,
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        );
    if (!mounted) return;
    if (result is String && !_looksLikeUuid(result)) {
      setState(() {
        _saving = false;
        _error = result;
      });
      return;
    }
    // Switch straight into the newly created branch.
    await ref.read(authNotifierProvider.notifier).switchActiveGym(result as String);
    if (mounted) Navigator.of(context).pop();
  }

  bool _looksLikeUuid(String s) => RegExp(r'^[0-9a-f-]{36}$').hasMatch(s);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add Gym Branch', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Branch name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'City (optional)', border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.statusDanger)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Branch'),
            ),
          ),
        ],
      ),
    );
  }
}
