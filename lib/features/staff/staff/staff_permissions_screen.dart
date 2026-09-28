import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/l10n.dart';

class StaffPermissionsScreen extends ConsumerStatefulWidget {
  const StaffPermissionsScreen({super.key});

  @override
  ConsumerState<StaffPermissionsScreen> createState() =>
      _StaffPermissionsScreenState();
}

class _StaffPermissionsScreenState
    extends ConsumerState<StaffPermissionsScreen> {
  bool _staffMode = false;
  String _selectedRole = 'manager';
  String? _selectedStaffId;
  Map<String, dynamic>? _matrix;
  String? _error;
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final raw = await ref
          .read(supabaseProvider)
          .rpc('get_permission_matrix', params: {'p_gym_id': gymId});
      final matrix = Map<String, dynamic>.from(raw as Map);
      final staff = (matrix['staff'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) => item['role'] != 'owner')
          .toList();
      if (_selectedStaffId == null && staff.isNotEmpty) {
        _selectedStaffId = staff.first['profile_id'] as String?;
      }
      if (!mounted) return;
      setState(() {
        _matrix = matrix;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _roleRows =>
      (_matrix?['roles'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  List<Map<String, dynamic>> get _staffRows =>
      (_matrix?['staff'] as List? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['role'] != 'owner')
          .toList();

  Map<String, dynamic> _permissionRow(GymModule module) {
    if (!_staffMode) {
      return Map<String, dynamic>.from(
        _roleRows.firstWhere(
          (row) => row['role'] == _selectedRole && row['module'] == module.name,
          orElse: () => const {},
        ),
      );
    }
    final staff = _staffRows.firstWhere(
      (row) => row['profile_id'] == _selectedStaffId,
      orElse: () => const {},
    );
    final overrides = (staff['overrides'] as List? ?? const []).map(
      (row) => Map<String, dynamic>.from(row as Map),
    );
    final override = overrides.where((row) => row['module'] == module.name);
    if (override.isNotEmpty) return Map<String, dynamic>.from(override.first);
    final role = staff['role'] as String? ?? 'staff';
    return Map<String, dynamic>.from(
      _roleRows.firstWhere(
        (row) => row['role'] == role && row['module'] == module.name,
        orElse: () => const {},
      ),
    );
  }

  bool _hasOverride(GymModule module) {
    if (!_staffMode) return false;
    final staff = _staffRows.firstWhere(
      (row) => row['profile_id'] == _selectedStaffId,
      orElse: () => const {},
    );
    return (staff['overrides'] as List? ?? const []).any(
      (row) => (row as Map)['module'] == module.name,
    );
  }

  Future<void> _toggle(GymModule module, GymAction action, bool value) async {
    final key = '${module.name}:${action.name}';
    if (_saving.contains(key)) return;
    final current = _permissionRow(module);
    current['can_${action.name}'] = value;
    setState(() => _saving.add(key));
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final params = <String, dynamic>{
        'p_gym_id': gymId,
        'p_module': module.name,
        for (final item in GymAction.values)
          'p_can_${item.name}': current['can_${item.name}'] == true,
      };
      if (_staffMode) {
        params['p_profile_id'] = _selectedStaffId;
        await ref
            .read(supabaseProvider)
            .rpc('set_staff_permissions', params: params);
      } else {
        params['p_role'] = _selectedRole;
        await ref
            .read(supabaseProvider)
            .rpc('set_role_permissions', params: params);
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_permissionError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Future<void> _clearOverride(GymModule module) async {
    try {
      final gymId = await ref.read(gymIdProvider.future);
      await ref
          .read(supabaseProvider)
          .rpc(
            'clear_staff_permission_override',
            params: {
              'p_gym_id': gymId,
              'p_profile_id': _selectedStaffId,
              'p_module': module.name,
            },
          );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_permissionError(context, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(context.l10n.staffPermissions)),
      body: ResponsiveContent(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ErrorState(what: 'staff permissions', onRetry: _load)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  StateMessage(
                    icon: AppIcons.lockPerson,
                    title: context.l10n.ownersKeepAccess,
                    body: context.l10n.permissionSetupHint,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(context.l10n.roleDefaults),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(context.l10n.staffOverride),
                      ),
                    ],
                    selected: {_staffMode},
                    onSelectionChanged: (value) =>
                        setState(() => _staffMode = value.first),
                  ),
                  const SizedBox(height: 14),
                  _staffMode ? _staffPicker() : _rolePicker(),
                  const SizedBox(height: 18),
                  Container(
                    decoration: AppTheme.cardDecoration(radius: 12),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < GymModule.values.length;
                          index++
                        ) ...[
                          _moduleRow(GymModule.values[index]),
                          if (index != GymModule.values.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _rolePicker() => DropdownButtonFormField<String>(
    value: _selectedRole,
    decoration: InputDecoration(labelText: context.l10n.configureRole),
    items: [
      DropdownMenuItem(value: 'manager', child: Text(context.l10n.manager)),
      DropdownMenuItem(value: 'trainer', child: Text(context.l10n.trainer)),
      DropdownMenuItem(value: 'staff', child: Text(context.l10n.staff)),
    ],
    onChanged: (value) => setState(() => _selectedRole = value ?? 'staff'),
  );

  Widget _staffPicker() {
    if (_staffRows.isEmpty) {
      return StateMessage(
        icon: AppIcons.groupOff,
        title: context.l10n.noStaffToConfigure,
        body: context.l10n.inviteStaffFirst,
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedStaffId,
      decoration: InputDecoration(labelText: context.l10n.configureStaffMember),
      items: _staffRows.map((staff) {
        final name = '${staff['first_name'] ?? ''} ${staff['last_name'] ?? ''}'
            .trim();
        return DropdownMenuItem(
          value: staff['profile_id'] as String?,
          child: Text('$name · ${staff['role']}'),
        );
      }).toList(),
      onChanged: (value) => setState(() => _selectedStaffId = value),
    );
  }

  Widget _moduleRow(GymModule module) {
    final row = _permissionRow(module);
    final hasOverride = _hasOverride(module);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  module.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (hasOverride)
                TextButton(
                  onPressed: () => _clearOverride(module),
                  child: Text(context.l10n.useRoleDefault),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: GymAction.values.map((action) {
              final key = '${module.name}:${action.name}';
              final selected = row['can_${action.name}'] == true;
              return FilterChip(
                label: Text(_actionLabel(context, action)),
                selected: selected,
                // The theme's selectedColor is near-black, same as its
                // labelStyle color — without this override, a selected
                // chip's text is invisible against its own background.
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                checkmarkColor: Colors.white,
                onSelected: _saving.contains(key)
                    ? null
                    : (value) => _toggle(module, action, value),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

String _actionLabel(BuildContext context, GymAction action) => switch (action) {
  GymAction.view => context.l10n.view,
  GymAction.add => context.l10n.add,
  GymAction.edit => context.l10n.edit,
  GymAction.delete => context.l10n.delete,
  GymAction.freeze => context.l10n.freeze,
  GymAction.export => context.l10n.export,
};

String _permissionError(BuildContext context, Object error) {
  final text = '$error';
  if (text.contains('owner_permissions_are_locked')) {
    return context.l10n.ownerPermissionsLocked;
  }
  if (text.contains('permission_denied')) {
    return context.l10n.permissionDeniedStaffAccess;
  }
  return context.l10n.permissionsSaveFailed;
}
