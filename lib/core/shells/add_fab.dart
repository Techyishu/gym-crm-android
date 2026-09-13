import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/gym_permissions.dart';
import '../services/data_refresh.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../../features/staff/billing/billing_screen.dart'
    show showCreateInvoiceSheet, showPlanFormSheet;
import '../../features/staff/classes/classes_screen.dart'
    show showClassFormSheet;
import '../../features/staff/expenses/expenses_screen.dart'
    show showAddExpenseSheet;
import '../../features/staff/leads/leads_screen.dart' show showAddLeadSheet;
import '../../features/staff/members/members_screen.dart'
    show showAddMemberSheet;
import '../../features/staff/staff/staff_screen.dart' show showInviteStaffSheet;
import '../../shared/widgets/adaptive_sheet.dart';
import '../../shared/widgets/redesign.dart';

/// One "add" action: what it creates, which screen owns it, and the sheet it
/// opens. The shell FAB picks an entry by route; the dashboard shows them all.
typedef AddAction = ({
  /// The screen this add belongs to, or null when no screen owns it (it then
  /// appears in the dashboard menu only). A screen may own more than one —
  /// Money creates both invoices and plans — and the FAB opens a short menu
  /// rather than a form when it does.
  String? route,
  GymModule module,
  IconData icon,
  String label,
  String hint,
  Future<void> Function(BuildContext) open,
});

const _actions = <AddAction>[
  (
    route: '/staff/members',
    module: GymModule.members,
    icon: AppIcons.personAdd,
    label: 'Member',
    hint: 'New joining, plan and first payment',
    open: showAddMemberSheet,
  ),
  (
    route: '/staff/billing',
    module: GymModule.payments,
    icon: AppIcons.receipt,
    label: 'Invoice',
    hint: 'Bill a member for a plan or service',
    open: showCreateInvoiceSheet,
  ),
  (
    route: '/staff/billing',
    module: GymModule.memberships,
    icon: AppIcons.cardMembership,
    label: 'Plan',
    hint: 'Monthly, quarterly or yearly membership',
    open: showPlanFormSheet,
  ),
  (
    route: '/staff/leads',
    module: GymModule.leads,
    icon: AppIcons.personSearch,
    label: 'Lead',
    hint: 'Walk-in or enquiry to follow up',
    open: showAddLeadSheet,
  ),
  (
    route: '/staff/classes',
    module: GymModule.batches,
    icon: AppIcons.event,
    label: 'Batch',
    hint: 'Morning, evening or a class with fixed timing',
    open: showClassFormSheet,
  ),
  (
    route: '/staff/staff',
    module: GymModule.staff,
    icon: AppIcons.groups,
    label: 'Staff',
    hint: 'Invite a trainer, manager or front desk',
    open: showInviteStaffSheet,
  ),
  (
    route: '/staff/expenses',
    module: GymModule.expenses,
    icon: AppIcons.payments,
    label: 'Expense',
    hint: 'Rent, salary, equipment, utilities',
    open: showAddExpenseSheet,
  ),
];

/// The adds a screen owns — none, one, or (Money) two.
List<AddAction> addActionsForRoute(String location) =>
    _actions.where((a) => a.route == location).toList();

/// The single floating "Add" button for the staff portal.
///
/// It is context-aware rather than one global menu everywhere: on a screen
/// that owns exactly one kind of add (members, billing, leads, expenses) it
/// opens that sheet in one tap, and on the dashboard — where nothing is in
/// context — it opens the full list. Screens with no add of their own, or one
/// that needs on-screen state (the attendance calendar's selected date), keep
/// their own button and get no FAB here.
class AddFab extends ConsumerWidget {
  const AddFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    return _build(context, ref, location);
  }

  Widget _build(BuildContext context, WidgetRef ref, String location) {
    bool allowed(AddAction a) =>
        ref.watch(gymPermissionProvider((a.module, GymAction.add)));

    // Exact match only: a member's detail page is not a place to offer "add
    // member", and leads/expenses are full-screen routes outside this shell —
    // they are reachable from the dashboard menu below.
    // The dashboard is not "in" any one feature, so it offers everything;
    // every other screen offers only what it owns.
    final owned = location == '/staff/dashboard'
        ? _actions
        : addActionsForRoute(location);
    final available = owned.where(allowed).toList();
    if (available.isEmpty) return const SizedBox.shrink();

    // One add — open its form straight away. Members is the only screen that
    // names what it adds: it is where staff spend the day and the label
    // doubles as the prompt. Elsewhere a plain "Add" keeps the button narrow
    // over a busy list.
    if (available.length == 1) {
      final only = available.single;
      return _Fab(
        label: only.module == GymModule.members ? 'Add member' : 'Add',
        onTap: () => _run(context, only),
      );
    }
    return _Fab(label: 'Add', onTap: () => _openMenu(context, available));
  }

  Future<void> _run(BuildContext context, AddAction action) async {
    await action.open(context);
    // Sheets write straight to Supabase; every screen caches its own rows, so
    // tell them all to refetch instead of reaching for one screen's provider.
    notifyGymDataChanged();
  }

  void _openMenu(BuildContext context, List<AddAction> available) {
    showAdaptiveSheet(
      context: context,
      builder: (sheetContext) => _AddMenuSheet(
        actions: available,
        onPick: (action) {
          Navigator.of(sheetContext).pop();
          _run(context, action);
        },
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Fab({required this.label, required this.onTap});

  @override
  // Deliberately smaller than a stock extended FAB (48h, 20pt padding): this
  // one sits above a list on every screen, so it stays an affordance rather
  // than a slab covering the row behind it.
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: AppTheme.accent,
      foregroundColor: Colors.white,
      elevation: 3,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
      extendedIconLabelSpacing: 7,
      icon: const Icon(AppIcons.add, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _AddMenuSheet extends StatelessWidget {
  final List<AddAction> actions;
  final void Function(AddAction) onPick;
  const _AddMenuSheet({required this.actions, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Add', subtitle: 'What do you want to add?'),
          const SizedBox(height: 12),
          Container(
            decoration: AppTheme.cardDecoration(radius: 14),
            child: Column(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppTheme.border,
                    ),
                  _AddRow(action: actions[i], onTap: () => onPick(actions[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final AddAction action;
  final VoidCallback onTap;
  const _AddRow({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(action.icon, size: 19, color: AppTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.hint,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              AppIcons.chevronRight,
              size: 16,
              color: AppTheme.inkHint,
            ),
          ],
        ),
      ),
    );
  }
}
