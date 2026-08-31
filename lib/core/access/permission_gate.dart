import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/staff/no_access_screen.dart';
import 'gym_permissions.dart';

class PermissionGate extends ConsumerWidget {
  final GymModule module;
  final GymAction action;
  final Widget child;

  const PermissionGate({
    super.key,
    required this.module,
    this.action = GymAction.view,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(staffPermissionsProvider);
    return permissions.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => NoAccessScreen(feature: module.label),
      data: (resolved) => resolved.can(module, action)
          ? child
          : NoAccessScreen(feature: module.label),
    );
  }
}
