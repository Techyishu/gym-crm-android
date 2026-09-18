import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import 'workout_plan_sheet.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/member_multi_picker.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/theme/app_icons.dart';

// All workout plans in the gym, grouped by member.
final _gymWorkoutPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select(
        'id, first_name, last_name, workout_plans(id, name, type, days, is_active, created_at)',
      )
      .eq('gym_id', gymId)
      .order('first_name');
  return (data as List).cast<Map<String, dynamic>>();
});

// All members in the gym (for the member picker when creating a plan).
final _gymMembersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select('id, first_name, last_name')
      .eq('gym_id', gymId)
      .order('first_name');
  return (data as List).cast<Map<String, dynamic>>();
});

/// Copies one workout plan onto several members at once.
///
/// Each member gets their own row rather than a shared one, so a trainer can
/// then adjust one person's copy without touching anybody else's. Editing the
/// original later does not reach the copies — copy again for that.
///
/// Lives at the top level because two places need it: the card's own button
/// and the prompt shown right after a new plan is saved.
Future<void> copyWorkoutPlanToMembers({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> plan,
  required String sourceMemberId,
  required VoidCallback onDone,
}) async {
  final all = await ref.read(_gymMembersProvider.future);
  if (!context.mounted) return;
  // The plan's own member is not offered: they already have it.
  final others = all.where((m) => m['id'] != sourceMemberId).toList();
  if (others.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No other members to copy this to')),
    );
    return;
  }

  final picked = await showMemberMultiPicker(
    context: context,
    members: others,
    title: 'Copy plan to members',
    subtitle:
        'Each member gets their own copy of "${plan['name']}" — edit one later without changing the rest.',
    confirmLabel: 'Copy plan',
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  final client = Supabase.instance.client;
  final ids = picked.map((m) => m['id'] as String).toList();
  try {
    // The member portal shows the active plan, so a member can only have one
    // — retire whatever they were on before the copy lands.
    await client
        .from('workout_plans')
        .update({'is_active': false})
        .inFilter('member_id', ids)
        .eq('is_active', true);

    await client.from('workout_plans').insert([
      for (final id in ids)
        {
          'member_id': id,
          'name': plan['name'],
          'type': plan['type'],
          'days': plan['days'],
          'is_active': true,
          'created_by': client.auth.currentUser?.id,
        },
    ]);

    notifyGymDataChanged();
    onDone();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plan copied to ${ids.length} member${ids.length == 1 ? '' : 's'}',
          ),
          backgroundColor: AppTheme.statusActive,
        ),
      );
    }
  } catch (e) {
    debugPrint('[GymCRM] Copy workout plan error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not copy the plan')));
    }
  }
}

class StaffWorkoutPlansScreen extends ConsumerStatefulWidget {
  const StaffWorkoutPlansScreen({super.key});

  @override
  ConsumerState<StaffWorkoutPlansScreen> createState() =>
      _StaffWorkoutPlansScreenState();
}

class _StaffWorkoutPlansScreenState
    extends ConsumerState<StaffWorkoutPlansScreen> {
  String _query = '';

  Future<void> _pickMemberAndCreate({Map<String, dynamic>? preselected}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    Map<String, dynamic>? selected = preselected;
    if (selected == null) {
      final members = await ref.read(_gymMembersProvider.future);
      if (!mounted) return;
      selected = await showAdaptiveSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _MemberPickerSheet(members: members),
      );
    }
    if (selected == null || !mounted) return;

    final memberId = selected['id'] as String;
    final memberName =
        '${selected['first_name'] ?? ''} ${selected['last_name'] ?? ''}'.trim();

    final saved = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          WorkoutPlanSheet(memberId: memberId, memberName: memberName),
    );
    if (saved != true) return;
    container.invalidate(_gymWorkoutPlansProvider);

    // Offer the copy here, while whoever built the plan is still thinking
    // about who else trains on it.
    if (!mounted) return;
    if (!await askToCopyToOthers(context, memberName)) return;
    if (!mounted) return;
    final fresh = await ref.read(_gymWorkoutPlansProvider.future);
    final row = fresh.firstWhere(
      (m) => m['id'] == memberId,
      orElse: () => const <String, dynamic>{},
    );
    final plans = (row['workout_plans'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (plans.isEmpty || !mounted) return;
    // Newest first — the one just saved.
    plans.sort(
      (a, b) => (b['created_at'] as String? ?? '').compareTo(
        a['created_at'] as String? ?? '',
      ),
    );
    await copyWorkoutPlanToMembers(
      context: context,
      ref: ref,
      plan: plans.first,
      sourceMemberId: memberId,
      onDone: () => container.invalidate(_gymWorkoutPlansProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(_gymWorkoutPlansProvider);
    final container = ProviderScope.containerOf(context, listen: false);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ResponsiveContent(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(AppIcons.arrowBackIosNew, size: 18),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Workout plans',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _pickMemberAndCreate(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          AppIcons.add,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search members',
                    prefixIcon: Icon(AppIcons.search, size: 20),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: plansAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const ErrorState(what: 'workout plans'),
                  data: (members) {
                    final filtered = _query.trim().isEmpty
                        ? members
                        : members
                              .where(
                                (m) =>
                                    '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
                                        .toLowerCase()
                                        .contains(_query.toLowerCase()),
                              )
                              .toList();

                    if (filtered.isEmpty) return const _EmptyState();

                    return RefreshIndicator(
                      color: AppTheme.accent,
                      onRefresh: () async =>
                          ref.invalidate(_gymWorkoutPlansProvider),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final m = filtered[i];
                          final memberId = m['id'] as String;
                          final memberName =
                              '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
                                  .trim();
                          final plans = (m['workout_plans'] as List? ?? [])
                              .cast<Map<String, dynamic>>();
                          if (plans.isEmpty) {
                            return _NoPlanRow(
                              name: memberName,
                              onAssign: () =>
                                  _pickMemberAndCreate(preselected: m),
                            );
                          }
                          return _MemberPlanGroup(
                            memberId: memberId,
                            memberName: memberName,
                            plans: plans,
                            onChanged: () => container.invalidate(
                              _gymWorkoutPlansProvider,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── No plan row (Assign) ──────────────────────────────────────────────────────

class _NoPlanRow extends StatelessWidget {
  final String name;
  final VoidCallback onAssign;
  const _NoPlanRow({required this.name, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          InitialsAvatar(name: name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const Text(
                  'No plan assigned',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.statusDanger,
                  ),
                ),
              ],
            ),
          ),
          PillButton(label: 'Assign', onTap: onAssign),
        ],
      ),
    );
  }
}

// ── Member plan group ─────────────────────────────────────────────────────────

class _MemberPlanGroup extends StatelessWidget {
  final String memberId;
  final String memberName;
  final List<Map<String, dynamic>> plans;
  final VoidCallback onChanged;

  const _MemberPlanGroup({
    required this.memberId,
    required this.memberName,
    required this.plans,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              const Icon(AppIcons.person, size: 14, color: AppTheme.inkHint),
              const SizedBox(width: 6),
              Text(
                memberName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkSoft,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${plans.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...plans.map(
          (plan) => _StaffPlanCard(
            plan: plan,
            memberId: memberId,
            memberName: memberName,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Plan card with edit/delete ────────────────────────────────────────────────

class _StaffPlanCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> plan;
  final String memberId;
  final String memberName;
  final VoidCallback onChanged;

  const _StaffPlanCard({
    required this.plan,
    required this.memberId,
    required this.memberName,
    required this.onChanged,
  });

  @override
  ConsumerState<_StaffPlanCard> createState() => _StaffPlanCardState();
}

class _StaffPlanCardState extends ConsumerState<_StaffPlanCard> {
  bool _expanded = false;

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete plan?',
      body: 'Delete "${widget.plan['name']}"? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: AppIcons.delete,
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('workout_plans')
          .delete()
          .eq('id', widget.plan['id'] as String);
      widget.onChanged();
    } catch (e) {
      debugPrint('[GymCRM] Delete workout plan error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete plan')));
      }
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WorkoutPlanSheet(
        memberId: widget.memberId,
        memberName: widget.memberName,
        plan: widget.plan,
      ),
    );
    if (saved == true) widget.onChanged();
  }

  Future<void> _assignToOthers(BuildContext context, WidgetRef ref) =>
      copyWorkoutPlanToMembers(
        context: context,
        ref: ref,
        plan: widget.plan,
        sourceMemberId: widget.memberId,
        onDone: widget.onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final name = widget.plan['name'] as String? ?? 'Plan';
    final type = (widget.plan['type'] as String? ?? 'weekly').toLowerCase();
    final rawDays = widget.plan['days'];
    final days = rawDays is List
        ? rawDays.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    final totalEx = days.fold<int>(0, (s, d) {
      final exList = d['exercises'];
      return s + (exList is List ? exList.length : 0);
    });
    final createdAt = widget.plan['created_at'] as String?;

    final (typeBg, typeFg) = switch (type) {
      'daily' => (const Color(0xFFDDEFE2), const Color(0xFF2E7D4F)),
      'monthly' => (const Color(0xFFF4E8CD), const Color(0xFFB07C1F)),
      _ => (const Color(0xFFE9E6DD), const Color(0xFF6E6A60)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: typeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: typeFg,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppTheme.ink,
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            'Created ${formatDateFromString(createdAt)}',
                            // Without these the date wraps a letter at a time
                            // the moment the row runs out of width.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.inkHint,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '$totalEx ex',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? AppIcons.keyboardArrowUp
                        : AppIcons.keyboardArrowDown,
                    size: 18,
                    color: AppTheme.inkHint,
                  ),
                  // ⋮ menu
                  PopupMenuButton<String>(
                    icon: const Icon(
                      AppIcons.moreVert,
                      size: 18,
                      color: AppTheme.inkSoft,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'edit') _edit(context);
                      if (v == 'assign') _assignToOthers(context, ref);
                      if (v == 'delete') _delete(context);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(AppIcons.edit, size: 16),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'assign',
                        child: Row(
                          children: [
                            Icon(AppIcons.groups, size: 16),
                            SizedBox(width: 10),
                            Text('Assign to members'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.delete,
                              size: 16,
                              color: AppTheme.statusDanger,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: AppTheme.statusDanger),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Its own line rather than the header row, which already carries the
          // type pill, name, date, exercise count and two icons — a labelled
          // button on top of that has no room left on a phone.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CopyToOthersButton(
                onTap: () => _assignToOthers(context, ref),
              ),
            ),
          ),
          // Expanded days view
          if (_expanded && days.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: days
                    .where((d) {
                      final exList = d['exercises'];
                      return exList is List && exList.isNotEmpty;
                    })
                    .map((day) => _DayView(day: day))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Day view (read-only) ──────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  final Map<String, dynamic> day;
  const _DayView({required this.day});

  @override
  Widget build(BuildContext context) {
    final label = day['label'] as String? ?? '';
    final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkHint,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...exercises.asMap().entries.map((e) {
            final ex = e.value;
            final parts = <String>[
              if ((ex['sets'] as String? ?? '').isNotEmpty)
                '${ex['sets']} sets',
              if ((ex['reps'] as String? ?? '').isNotEmpty)
                '${ex['reps']} reps',
              if ((ex['weight'] as String? ?? '').isNotEmpty)
                ex['weight'] as String,
            ];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key + 1}. ',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex['name'] as String? ?? '—',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.ink,
                          ),
                        ),
                        if (parts.isNotEmpty)
                          Text(
                            parts.join(' · '),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.inkHint,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Member picker ─────────────────────────────────────────────────────────────

class _MemberPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  const _MemberPickerSheet({required this.members});

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.members.where((m) {
      final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
          .toLowerCase();
      return name.contains(_query.toLowerCase());
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeader(title: 'Assign plan to'),
          const SizedBox(height: 14),
          TextFormField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search members',
              prefixIcon: Icon(AppIcons.search, size: 18),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final m = filtered[i];
                final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'
                    .trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          InitialsAvatar(name: name, size: 38),
                          const SizedBox(width: 12),
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.fitnessActive, size: 56, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No workout plans yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap + to create a plan for a member',
            style: TextStyle(color: AppTheme.inkSoft),
          ),
        ],
      ),
    );
  }
}
