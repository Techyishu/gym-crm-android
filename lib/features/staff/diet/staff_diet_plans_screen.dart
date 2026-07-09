import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/redesign.dart';
import 'diet_plan_sheet.dart';

final _gymDietPlansProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select(
          'id, first_name, last_name, diet_plans(id, name, goal, calories, meals, is_active, created_at)')
      .eq('gym_id', gymId)
      .order('first_name');
  return (data as List).cast<Map<String, dynamic>>();
});

final _gymMembersForDietProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select('id, first_name, last_name')
      .eq('gym_id', gymId)
      .order('first_name');
  return (data as List).cast<Map<String, dynamic>>();
});

class StaffDietPlansScreen extends ConsumerStatefulWidget {
  const StaffDietPlansScreen({super.key});

  @override
  ConsumerState<StaffDietPlansScreen> createState() => _StaffDietPlansScreenState();
}

class _StaffDietPlansScreenState extends ConsumerState<StaffDietPlansScreen> {
  String _query = '';

  Future<void> _pickMemberAndCreate({Map<String, dynamic>? preselected}) async {
    Map<String, dynamic>? selected = preselected;
    if (selected == null) {
      final members = await ref.read(_gymMembersForDietProvider.future);
      if (!mounted) return;
      selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _MemberPickerSheet(members: members),
      );
    }
    if (selected == null || !mounted) return;

    final memberId = selected['id'] as String;
    final memberName = '${selected['first_name']} ${selected['last_name']}'.trim();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          DietPlanSheet(memberId: memberId, memberName: memberName),
    );
    if (saved == true) ref.invalidate(_gymDietPlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(_gymDietPlansProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.of(context).maybePop()),
                const Expanded(
                  child: Text('Diet plans',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
                ),
                GestureDetector(
                  onTap: () => _pickMemberAndCreate(),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.add, size: 21, color: Colors.white),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Search members', prefixIcon: Icon(Icons.search, size: 20)),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: plansAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (members) {
                  final filtered = _query.trim().isEmpty
                      ? members
                      : members.where((m) =>
                          '${m['first_name']} ${m['last_name']}'.toLowerCase().contains(_query.toLowerCase())).toList();

                  if (filtered.isEmpty) return const _EmptyState();

                  return RefreshIndicator(
                    color: AppTheme.accent,
                    onRefresh: () async => ref.invalidate(_gymDietPlansProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final m = filtered[i];
                        final memberId = m['id'] as String;
                        final memberName = '${m['first_name']} ${m['last_name']}'.trim();
                        final plans = (m['diet_plans'] as List? ?? []).cast<Map<String, dynamic>>();
                        if (plans.isEmpty) {
                          return _NoPlanRow(
                            name: memberName,
                            onAssign: () => _pickMemberAndCreate(preselected: m),
                          );
                        }
                        return _MemberPlanGroup(
                          memberId: memberId,
                          memberName: memberName,
                          plans: plans,
                          onChanged: () => ref.invalidate(_gymDietPlansProvider),
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
      child: Row(children: [
        InitialsAvatar(name: name, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            const Text('No plan assigned',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.statusDanger)),
          ]),
        ),
        PillButton(label: 'Assign', onTap: onAssign),
      ]),
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
              const Icon(Icons.person_outline, size: 14, color: AppTheme.inkHint),
              const SizedBox(width: 6),
              Text(
                memberName,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.3),
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
                      color: AppTheme.inkSoft),
                ),
              ),
            ],
          ),
        ),
        ...plans.map((plan) => _StaffDietPlanCard(
              plan: plan,
              memberId: memberId,
              memberName: memberName,
              onChanged: onChanged,
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Plan card with edit/delete ────────────────────────────────────────────────

class _StaffDietPlanCard extends StatefulWidget {
  final Map<String, dynamic> plan;
  final String memberId;
  final String memberName;
  final VoidCallback onChanged;

  const _StaffDietPlanCard({
    required this.plan,
    required this.memberId,
    required this.memberName,
    required this.onChanged,
  });

  @override
  State<_StaffDietPlanCard> createState() => _StaffDietPlanCardState();
}

class _StaffDietPlanCardState extends State<_StaffDietPlanCard> {
  bool _expanded = false;

  static const _goalColors = {
    'weight_loss': (Color(0xFFF8DFD7), Color(0xFFC2492F)),
    'muscle_gain': (Color(0xFFDDEFE2), Color(0xFF2E7D4F)),
    'maintenance': (Color(0xFFF4E8CD), Color(0xFFB07C1F)),
    'general':     (Color(0xFFE9E6DD), Color(0xFF6E6A60)),
  };

  static const _goalLabels = {
    'weight_loss': 'Weight Loss',
    'muscle_gain': 'Muscle Gain',
    'maintenance': 'Maintenance',
    'general':     'General',
  };

  Future<void> _delete(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete plan?',
      body: 'Delete "${widget.plan['name']}"? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('diet_plans')
          .delete()
          .eq('id', widget.plan['id'] as String);
      widget.onChanged();
    } catch (e) {
      debugPrint('[GymCRM] Delete diet plan error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete plan')),
        );
      }
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DietPlanSheet(
        memberId: widget.memberId,
        memberName: widget.memberName,
        plan: widget.plan,
      ),
    );
    if (saved == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.plan['name'] as String? ?? 'Plan';
    final goal = (widget.plan['goal'] as String? ?? 'general').toLowerCase();
    final calories = widget.plan['calories'] as int?;
    final createdAt = widget.plan['created_at'] as String?;
    final rawMeals = widget.plan['meals'];
    final meals = rawMeals is List
        ? rawMeals.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

    final (goalBg, goalFg) = _goalColors[goal] ?? _goalColors['general']!;
    final goalLabel = _goalLabels[goal] ?? 'General';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: goalBg, borderRadius: BorderRadius.circular(20)),
                    child: Text(goalLabel.toUpperCase(),
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: goalFg,
                            letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppTheme.ink)),
                        if (createdAt != null)
                          Text('Created ${formatDateFromString(createdAt)}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.inkHint)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${meals.length} meals',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.inkHint)),
                      if (calories != null)
                        Text('$calories kcal',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.inkSoft)),
                    ],
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppTheme.inkHint,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: AppTheme.inkSoft),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'edit') _edit(context);
                      if (v == 'delete') _delete(context);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 10),
                          Text('Edit'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: AppTheme.statusDanger),
                          SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(color: AppTheme.statusDanger)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && meals.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: meals
                    .where((m) {
                      final items = m['items'];
                      return items is List && items.isNotEmpty;
                    })
                    .map((m) => _MealView(meal: m))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Meal view (read-only) ─────────────────────────────────────────────────────

class _MealView extends StatelessWidget {
  final Map<String, dynamic> meal;
  const _MealView({required this.meal});

  @override
  Widget build(BuildContext context) {
    final name = meal['name'] as String? ?? '';
    final time = meal['time'] as String? ?? '';
    final items = (meal['items'] as List? ?? []).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkHint,
                    letterSpacing: 0.8),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(time,
                      style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.inkSoft,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ...items.asMap().entries.map((e) {
            final item = e.value;
            final food = item['food'] as String? ?? '—';
            final qty = item['qty'] as String? ?? '';
            final kcal = item['calories'] as int?;
            final parts = <String>[
              if (qty.isNotEmpty) qty,
              if (kcal != null) '${kcal}kcal',
            ];
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Text('${e.key + 1}. ',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.inkHint)),
                  Expanded(
                    child: Text(food,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.ink)),
                  ),
                  if (parts.isNotEmpty)
                    Text(parts.join(' · '),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.inkHint)),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
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
      final name = '${m['first_name']} ${m['last_name']}'.toLowerCase();
      return name.contains(_query.toLowerCase());
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 20,
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
            decoration: const InputDecoration(hintText: 'Search members', prefixIcon: Icon(Icons.search, size: 18)),
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
                final name = '${m['first_name']} ${m['last_name']}'.trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Row(children: [
                        InitialsAvatar(name: name, size: 38),
                        const SizedBox(width: 12),
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                      ]),
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
          Icon(Icons.restaurant_menu, size: 56, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text('No diet plans yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink)),
          SizedBox(height: 8),
          Text('Tap + to create a plan for a member',
              style: TextStyle(color: AppTheme.inkSoft)),
        ],
      ),
    );
  }
}
