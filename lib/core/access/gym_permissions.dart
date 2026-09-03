import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../billing/plan_limits.dart';

enum GymModule {
  members,
  memberships,
  pt,
  services,
  attendance,
  payments,
  reports,
  batches,
  leads,
  expenses,
  staff,
  settings,
}

enum GymAction { view, add, edit, delete, freeze, export }

extension GymModuleLabel on GymModule {
  String get label => switch (this) {
    GymModule.members => 'Members',
    GymModule.memberships => 'Memberships & plans',
    GymModule.pt => 'PT & workout plans',
    GymModule.services => 'Services & diet plans',
    GymModule.attendance => 'Check-in & biometric',
    GymModule.payments => 'Payments',
    GymModule.reports => 'Reports & exports',
    GymModule.batches => 'Batches',
    GymModule.leads => 'Leads & enquiries',
    GymModule.expenses => 'Expenses',
    GymModule.staff => 'Staff',
    GymModule.settings => 'Settings',
  };
}

class GymPermissions {
  final Map<GymModule, Set<GymAction>> _allowed;

  const GymPermissions(this._allowed);

  bool can(GymModule module, GymAction action) =>
      _allowed[module]?.contains(action) ?? false;

  factory GymPermissions.fromJson(Map<String, dynamic> json) {
    final resolved = <GymModule, Set<GymAction>>{};
    for (final module in GymModule.values) {
      final raw = json[module.name];
      if (raw is! Map) continue;
      resolved[module] = {
        for (final action in GymAction.values)
          if (raw[action.name] == true) action,
      };
    }
    return GymPermissions(resolved);
  }

  factory GymPermissions.roleDefaults(String? role) {
    bool allowed(GymModule module, GymAction action) {
      if (role == 'owner') return true;
      if (role == 'manager') {
        return switch (action) {
          GymAction.view => true,
          GymAction.add || GymAction.edit => module != GymModule.reports,
          GymAction.delete => {
            GymModule.members,
            GymModule.memberships,
            GymModule.pt,
            GymModule.services,
            GymModule.batches,
            GymModule.leads,
          }.contains(module),
          GymAction.freeze => module == GymModule.members,
          GymAction.export => true,
        };
      }
      if (role == 'trainer') {
        return switch (action) {
          GymAction.view => {
            GymModule.members,
            GymModule.memberships,
            GymModule.pt,
            GymModule.services,
            GymModule.attendance,
            GymModule.batches,
          }.contains(module),
          GymAction.add || GymAction.edit => {
            GymModule.pt,
            GymModule.services,
            GymModule.attendance,
            GymModule.batches,
          }.contains(module),
          GymAction.delete => {
            GymModule.pt,
            GymModule.services,
            GymModule.batches,
          }.contains(module),
          GymAction.freeze || GymAction.export => false,
        };
      }
      if (role == 'staff') {
        return switch (action) {
          GymAction.view => {
            GymModule.members,
            GymModule.memberships,
            GymModule.pt,
            GymModule.services,
            GymModule.attendance,
            GymModule.payments,
            GymModule.batches,
          }.contains(module),
          GymAction.add => {
            GymModule.pt,
            GymModule.services,
            GymModule.attendance,
            GymModule.payments,
            GymModule.batches,
          }.contains(module),
          GymAction.edit => {
            GymModule.pt,
            GymModule.services,
            GymModule.attendance,
            GymModule.batches,
          }.contains(module),
          GymAction.delete => {
            GymModule.pt,
            GymModule.services,
            GymModule.batches,
          }.contains(module),
          GymAction.freeze || GymAction.export => false,
        };
      }
      return false;
    }

    return GymPermissions({
      for (final module in GymModule.values)
        module: {
          for (final action in GymAction.values)
            if (allowed(module, action)) action,
        },
    });
  }
}

final staffPermissionsProvider = FutureProvider<GymPermissions>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final role = await ref.watch(staffRoleProvider.future);
  try {
    final raw = await ref
        .watch(supabaseProvider)
        .rpc('get_my_permissions', params: {'p_gym_id': gymId});
    if (raw is Map) {
      return GymPermissions.fromJson(Map<String, dynamic>.from(raw));
    }
  } catch (_) {
    // During a staged rollout the app can briefly precede the migration. Keep
    // existing role behavior until the authoritative RPC is available.
  }
  return GymPermissions.roleDefaults(role);
});

/// The gym's current plan tier. `free` until the profile loads, which is the
/// unrestricted tier — a momentary null must not flash a locked UI at someone
/// who has paid.
final planTierProvider = Provider<PlanTier>((ref) {
  final profile = ref.watch(staffProfileProvider).valueOrNull;
  return planTierOf(profile?['gyms'] as Map<String, dynamic>?);
});

/// Role permission only. No plan gating here: Starter and Pro expose the same
/// modules and actions — they differ by the caps in plan_limits.dart, plus
/// biometric, which is gated at its own sheet.
final gymPermissionProvider = Provider.family<bool, (GymModule, GymAction)>((
  ref,
  permission,
) {
  final resolved = ref.watch(staffPermissionsProvider).valueOrNull;
  if (resolved != null) return resolved.can(permission.$1, permission.$2);
  final role = ref.watch(staffRoleProvider).valueOrNull;
  return GymPermissions.roleDefaults(role).can(permission.$1, permission.$2);
});
