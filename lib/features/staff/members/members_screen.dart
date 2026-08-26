import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/access/role_access.dart';
import '../../../core/billing/advance_payment_date.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/services/app_events.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../billing/billing_screen.dart' show PlanFormSheet;
import 'import_csv_screen.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

final _membersProvider = FutureProvider<List<Member>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('gym_id', gymId)
      .order('created_at', ascending: false);
  return (data as List)
      .map((e) => Member.fromJson(e as Map<String, dynamic>))
      .toList();
});

// Outstanding due per member, gym-wide, fetched in one batched query so the
// list can show a "Due" badge without an N+1 query per row.
final _membersDueProvider = FutureProvider<Map<String, double>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final invoices = await Supabase.instance.client
      .from('invoices')
      .select('member_id, amount, payments(amount, status)')
      .eq('gym_id', gymId)
      .inFilter('status', ['open', 'partial']);

  final due = <String, double>{};
  for (final inv in (invoices as List)) {
    final memberId = (inv as Map)['member_id'] as String?;
    if (memberId == null) continue;
    final amount = (inv['amount'] as num).toDouble();
    final payments = (inv['payments'] as List?) ?? const [];
    final paid = payments
        .where((p) => (p as Map)['status'] == 'succeeded')
        .fold<double>(
          0,
          (s, p) => s + ((p as Map)['amount'] as num).toDouble(),
        );
    due[memberId] = (due[memberId] ?? 0) + (amount - paid).clamp(0, amount);
  }
  return due;
});

// Active membership plans for the current gym — used to assign a plan when
// creating a member (matches the web add-member form).
final _memberPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  final data = await client
      .from('membership_plans')
      .select('id, name, price, billing_interval, billing_interval_months')
      .eq('gym_id', gymId)
      .eq('is_active', true)
      .order('price');
  return (data as List).cast<Map<String, dynamic>>();
});

String _planLabel(Map<String, dynamic> p) {
  final price = (p['price'] as num?)?.toStringAsFixed(0) ?? '0';
  final interval = p['billing_interval'] as String? ?? '';
  const short = {
    'monthly': 'mo',
    'quarterly': 'qtr',
    'biannual': '6mo',
    'annual': 'yr',
  };
  final unit = interval == 'custom'
      ? '${p['billing_interval_months'] ?? ''}mo'
      : (short[interval] ?? interval);
  return '${p['name']} — $currencySymbol$price/$unit';
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

const _kLapsingWindows = [3, 7, 15];

/// Compact single-line filter pill: label + a small count badge, fixed
/// 34dp height so it never sits taller/bulkier than its neighbours.
class _FilterPill extends StatelessWidget {
  final String label;
  final String count;
  final bool selected;
  final Color? tintBg;
  final Color? tintFg;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.tintBg,
    this.tintFg,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.ink : (tintBg ?? AppTheme.surface);
    final fg = selected ? Colors.white : (tintFg ?? AppTheme.ink);
    final badgeBg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : AppTheme.background;
    final badgeFg = selected ? Colors.white : (tintFg ?? AppTheme.inkSoft);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: badgeFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same compact single line as [_FilterPill], plus a caret that opens the
/// day-window picker, separate from the tap-to-select-filter body.
class _LapsingChip extends StatelessWidget {
  final String label;
  final String count;
  final bool selected;
  final Color? tintBg;
  final Color? tintFg;
  final VoidCallback onTap;
  final VoidCallback onPickWindow;

  const _LapsingChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.tintBg,
    required this.tintFg,
    required this.onTap,
    required this.onPickWindow,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.ink : (tintBg ?? AppTheme.surface);
    final fg = selected ? Colors.white : (tintFg ?? AppTheme.ink);
    final badgeBg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : AppTheme.background;
    final badgeFg = selected ? Colors.white : (tintFg ?? AppTheme.inkSoft);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onPickWindow,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, left: 2),
              child: Icon(Icons.arrow_drop_down, size: 20, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _filter = 'all';
  String _search = '';
  int _lapsingDays = 7;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static bool _isLapsing(Member m, int withinDays) {
    if (m.status != 'active') return false;
    final npd = m.nextPaymentDate;
    if (npd == null || npd.isEmpty) return false;
    final due = DateTime.tryParse(npd);
    if (due == null) return false;
    final days = due.difference(DateTime.now()).inDays;
    return days >= 0 && days <= withinDays;
  }

  List<Member> _applyFilter(List<Member> list) => switch (_filter) {
    'all' => list,
    'lapsing' => list.where((m) => _isLapsing(m, _lapsingDays)).toList(),
    _ => list.where((m) => m.status == _filter).toList(),
  };

  void _pickLapsingWindow() {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Lapsing within'),
            const SizedBox(height: 16),
            ..._kLapsingWindows.map((d) {
              final selected = d == _lapsingDays;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _lapsingDays = d;
                      _filter = 'lapsing';
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accentSoft : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? AppTheme.accent
                                : Colors.transparent,
                            border: Border.all(
                              color: selected
                                  ? AppTheme.accent
                                  : AppTheme.inkHint,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  size: 13,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$d days',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersProvider);
    final dueMap = ref.watch(_membersDueProvider).valueOrNull ?? const {};
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canPii = RoleAccess.canSeeMemberPii(role);
    final canEdit = RoleAccess.canEditMembers(role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(canEdit),
            _buildSearchAndFilter(members.valueOrNull ?? const []),
            Expanded(
              child: members.when(
                loading: () => _MembersShimmer(),
                error: (e, _) => const Center(
                  child: Text(
                    'Could not load members. Pull to retry.',
                    style: TextStyle(color: AppTheme.inkSoft),
                  ),
                ),
                data: (list) {
                  var filtered = _applyFilter(list);
                  if (_search.isNotEmpty) {
                    final q = _search.toLowerCase();
                    filtered = filtered
                        .where(
                          (m) =>
                              m.fullName.toLowerCase().contains(q) ||
                              (canPii && m.email.toLowerCase().contains(q)),
                        )
                        .toList();
                  }

                  if (filtered.isEmpty) return const _EmptyMembers();

                  return RefreshIndicator(
                    color: AppTheme.accent,
                    onRefresh: () async => ref.invalidate(_membersProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox.shrink(),
                      itemBuilder: (_, i) => _MemberRow(
                        member: filtered[i],
                        canPii: canPii,
                        isFirst: i == 0,
                        isLast: i == filtered.length - 1,
                        due: dueMap[filtered[i].id] ?? 0,
                        onReturn: () {
                          ref.invalidate(_membersProvider);
                          ref.invalidate(_membersDueProvider);
                        },
                      ),
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

  Widget _buildHeader(bool canEdit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          const Text(
            'Members',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          if (canEdit) ...[
            GestureDetector(
              onTap: () => _showActionsMenu(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showAddMemberSheet(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33DF5B34),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, size: 21, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showActionsMenu(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.upload_file_outlined,
                color: AppTheme.ink,
              ),
              title: const Text('Import members'),
              onTap: () {
                Navigator.pop(ctx);
                _openImportCsv(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined, color: AppTheme.ink),
              title: const Text('Expiring soon'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/staff/upcoming-payments');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(List<Member> all) {
    final counts = {
      'all': all.length,
      'active': all.where((m) => m.status == 'active').length,
      'lapsing': all.where((m) => _isLapsing(m, _lapsingDays)).length,
      'frozen': all.where((m) => m.status == 'frozen').length,
      'expired': all.where((m) => m.status == 'expired').length,
    };
    final filters = [
      ('all', 'All', null, null),
      ('active', 'Active', null, null),
      (
        'lapsing',
        'Lapsing ${_lapsingDays}d',
        AppTheme.statusWarnBg,
        AppTheme.statusWarn,
      ),
      ('frozen', 'On hold', null, null),
      ('expired', 'Expired', null, null),
    ];

    final search = TextField(
      controller: _searchCtrl,
      decoration: const InputDecoration(
        hintText: 'Search members',
        prefixIcon: Icon(Icons.search, color: AppTheme.inkHint, size: 20),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _search = v),
    );

    final filterRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final (key, label, tintBg, tintFg) = f;
          if (key == 'lapsing') {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _LapsingChip(
                label: label,
                count: '${counts[key] ?? 0}',
                selected: _filter == key,
                tintBg: tintBg,
                tintFg: tintFg,
                onTap: () => setState(() => _filter = key),
                onPickWindow: _pickLapsingWindow,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FilterPill(
              label: label,
              count: '${counts[key] ?? 0}',
              selected: _filter == key,
              tintBg: tintBg,
              tintFg: tintFg,
              onTap: () => setState(() => _filter = key),
            ),
          );
        }).toList(),
      ),
    );

    // Wide screens have room for search and filters side by side; phones
    // keep search on its own line above the horizontally-scrolling filters.
    final isWide = ResponsiveContent.isWide(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: isWide
          ? Row(
              children: [
                SizedBox(width: 280, child: search),
                const SizedBox(width: 16),
                Expanded(child: filterRow),
              ],
            )
          : Column(children: [search, const SizedBox(height: 12), filterRow]),
    );
  }

  void _showAddMemberSheet(BuildContext context) {
    showAddMemberSheet(context).then((_) => ref.invalidate(_membersProvider));
  }

  void _openImportCsv(BuildContext context) {
    Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ImportCsvScreen()))
        .then((imported) {
          if (imported == true) ref.invalidate(_membersProvider);
        });
  }
}

// ── Member Row (grouped card list) ────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  final Member member;
  final bool canPii;
  final bool isFirst, isLast;
  final double due;
  final VoidCallback onReturn;
  const _MemberRow({
    required this.member,
    required this.canPii,
    required this.isFirst,
    required this.isLast,
    this.due = 0,
    required this.onReturn,
  });

  bool get _lapsing {
    if (member.status != 'active') return false;
    final npd = member.nextPaymentDate;
    if (npd == null || npd.isEmpty) return false;
    final due = DateTime.tryParse(npd);
    if (due == null) return false;
    final days = due.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }

  StatusPill get _pill {
    if (_lapsing) return StatusPill.warn();
    return switch (member.status) {
      'active' => StatusPill.active(),
      'frozen' => StatusPill.neutral(),
      'expired' => StatusPill.danger(),
      'cancelled' => StatusPill.neutral(label: 'Cancelled'),
      _ => StatusPill.neutral(label: member.status),
    };
  }

  String get _subtitle {
    final parts = <String>[];
    final plan = member.currentMembership?.plan?.name;
    if (plan != null && plan.isNotEmpty) parts.add(plan);
    final npd = member.nextPaymentDate;
    if (npd != null && npd.isNotEmpty) {
      parts.add(
        member.status == 'expired'
            ? 'Expired ${formatDateFromString(npd)}'
            : 'exp ${formatDateFromString(npd)}',
      );
    } else if (canPii && member.email.isNotEmpty) {
      parts.add(member.email);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final expired = member.status == 'expired';
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: radius,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppTheme.border, width: 0.7),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () => context
              .push('/staff/members/${member.id}')
              .then((_) => onReturn()),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                InitialsAvatar(
                  name: member.fullName,
                  size: 46,
                  photo: member.avatarUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.ink,
                        ),
                      ),
                      if (_subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: expired
                                ? AppTheme.statusDanger
                                : AppTheme.inkSoft,
                            fontSize: 12.5,
                            fontWeight: expired
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _pill,
                    if (due > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Collect ${formatCurrency(due)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.statusDanger,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shimmer Skeleton ──────────────────────────────────────────────────────────

class _MembersShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 8,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8E8E8),
        highlightColor: const Color(0xFFF5F5F5),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.people_outline, size: 64, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No members found',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.ink,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Add your first member to get started',
            style: TextStyle(color: AppTheme.inkHint, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// Shown in place of the plan dropdown when the gym hasn't created any plan yet.
class _NoPlansBox extends StatelessWidget {
  final VoidCallback onCreate;
  const _NoPlansBox({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCreate,
      child: DottedBorderBox(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No membership plans yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Every member needs a plan — it is what generates their invoices.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.add, size: 18, color: AppTheme.accent),
                SizedBox(width: 6),
                Text(
                  'Create a plan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Member Sheet ──────────────────────────────────────────────────────────

/// Opens the add-member sheet from anywhere in the app (not just this
/// screen) — e.g. the dashboard's setup checklist jumps straight here instead
/// of routing to the members list first. Fire-and-forget: resolves once the
/// sheet closes for any reason (saved or dismissed); callers invalidate
/// whatever provider they own.
Future<void> showAddMemberSheet(BuildContext context) {
  return showAdaptiveSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AddMemberSheet(),
  );
}

class AddMemberSheet extends ConsumerStatefulWidget {
  const AddMemberSheet({super.key});

  @override
  ConsumerState<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _customIdCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();

  String _status = 'active';
  String? _joinedAt;
  String? _nextPaymentDate;
  String? _planId;
  int? _planBillingIntervalMonths;
  double _planPrice = 0;
  double _planDiscountAmount = 0;
  String _paymentMethod = 'cash';
  File? _avatarFile;
  bool _loading = false;

  double get _planAmount =>
      (_planPrice - _planDiscountAmount).clamp(0, _planPrice);
  double get _paidAmount => double.tryParse(_paidAmountCtrl.text.trim()) ?? 0;
  double get _dueAmount => (_planAmount - _paidAmount).clamp(0, _planAmount);

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _customIdCtrl.dispose();
    _notesCtrl.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  void _selectPlan(Map<String, dynamic> plan) {
    _planId = plan['id'] as String?;
    _planBillingIntervalMonths =
        plan['billing_interval_months'] as int? ??
        const {
          'monthly': 1,
          'quarterly': 3,
          'biannual': 6,
          'annual': 12,
        }[plan['billing_interval']];
    _planPrice = (plan['price'] as num?)?.toDouble() ?? 0;
    _paidAmountCtrl.text = _planAmount.toStringAsFixed(0);
  }

  // Gym has no plans yet — let staff make one without losing the half-filled
  // member form. Reuses the Billing screen's sheet, which pops the new row.
  Future<void> _createPlan() async {
    final created = await showAdaptiveSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PlanFormSheet(),
    );
    ref.invalidate(_memberPlansProvider);
    if (created != null && mounted) setState(() => _selectPlan(created));
  }

  Future<void> _pickAvatar() async {
    final source = await showAdaptiveSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted)
      setState(() => _avatarFile = File(picked.path));
  }

  Future<String?> _uploadAvatar(String gymId) async {
    if (_avatarFile == null) return null;
    final ext = _avatarFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final filename = '$gymId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await _avatarFile!.readAsBytes();
    await MemberPhotoService.upload(
      path: filename,
      bytes: bytes,
      contentType: mime,
    );
    // Stored value is the bare path; display resolves it via the photo Worker.
    return filename;
  }

  Future<void> _pickDate({required bool isJoined}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final s = picked.toIso8601String().split('T')[0];
      setState(() {
        if (isJoined) {
          _joinedAt = s;
        } else {
          _nextPaymentDate = s;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // With zero plans the dropdown isn't in the tree, so validate() can't catch
    // this one — the empty-state box is shown instead.
    if (_planId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create a membership plan first — members need one to be invoiced',
          ),
        ),
      );
      return;
    }
    final paidAmount = _paidAmount;
    if (paidAmount > 0) {
      final ok = await confirmPartialIfNeeded(
        context,
        enteredAmount: paidAmount,
        dueAmount: _planAmount,
      );
      if (!ok) return;
    }
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      // Real (non-demo) member count before this insert, so
      // checkMemberMilestones can tell whether it just crossed 1 or 3.
      // Own try/catch: this only supports analytics — a transient failure
      // here must never block the actual member from being added.
      int? countBefore;
      try {
        final res = await client
            .from('members')
            .select('id')
            .eq('gym_id', gymId)
            .eq('is_demo_data', false)
            .count(CountOption.exact);
        countBefore = res.count;
      } catch (_) {
        countBefore = null;
      }

      final avatarUrl = await _uploadAvatar(gymId);

      // billing_interval_months always comes from the selected plan, never
      // from a manual chip — staff picking a plan then a mismatched interval
      // (e.g. Quarterly plan, "1 month" tapped) silently mis-billed members
      // every cycle with no error. If staff also typed a custom next payment
      // date, only that date is theirs to set; the interval still follows
      // the plan.
      var nextPaymentDate = _nextPaymentDate;
      final billingIntervalMonths = _planBillingIntervalMonths ?? 1;
      if (nextPaymentDate == null) {
        final joined =
            _joinedAt ?? DateTime.now().toIso8601String().split('T').first;
        nextPaymentDate = advancePaymentDate(
          joined,
          months: billingIntervalMonths,
        );
      }

      final inserted = await client
          .from('members')
          .insert({
            'gym_id': gymId,
            'first_name': _firstCtrl.text.trim(),
            if (_lastCtrl.text.trim().isNotEmpty)
              'last_name': _lastCtrl.text.trim(),
            if (_emailCtrl.text.trim().isNotEmpty)
              'email': _emailCtrl.text.trim(),
            if (_phoneCtrl.text.trim().isNotEmpty)
              'phone': _phoneCtrl.text.trim(),
            if (_customIdCtrl.text.trim().isNotEmpty)
              'custom_id': _customIdCtrl.text.trim(),
            if (_notesCtrl.text.trim().isNotEmpty)
              'notes': _notesCtrl.text.trim(),
            'status':
                (nextPaymentDate != null &&
                    nextPaymentDate.compareTo(
                          DateTime.now().toIso8601String().split('T')[0],
                        ) <
                        0)
                ? 'expired'
                : _status,
            if (_joinedAt != null) 'joined_at': _joinedAt,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
            if (nextPaymentDate != null) 'next_payment_date': nextPaymentDate,
            if (nextPaymentDate != null)
              'billing_interval_months': billingIntervalMonths,
          })
          .select('id')
          .single();

      // Assign the selected membership plan (open-ended, matches the web flow).
      // A DB trigger auto-creates the invoice the moment this insert commits.
      await client.from('memberships').insert({
        'member_id': inserted['id'],
        'plan_id': _planId,
        'status': 'active',
        'starts_at': DateTime.now().toUtc().toIso8601String(),
        'ends_at': null,
        'discount_amount': _planDiscountAmount,
      });

      if (paidAmount > 0) {
        final invoice = await client
            .from('invoices')
            .select('id')
            .eq('member_id', inserted['id'])
            .eq('status', 'open')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (invoice != null) {
          // next_payment_date was just set by the staff above — recordInvoicePayment
          // doesn't touch it itself, so no separate "don't advance" flag is needed here.
          await recordInvoicePayment(
            invoiceId: invoice['id'] as String,
            amount: paidAmount,
            method: _paymentMethod,
            recordedBy: client.auth.currentUser?.id,
          );
        }
      }

      if (countBefore != null) {
        unawaited(
          AppEvents.checkMemberMilestones(
            before: countBefore,
            after: countBefore + 1,
          ),
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[GymCRM] AddMember error: $e');
      if (mounted) {
        final msg = (e is PostgrestException && e.code == '23505')
            ? 'Member ID "${_customIdCtrl.text.trim()}" is already in use. Please use a different one.'
            : 'Failed to add member. Please try again.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Member',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Photo picker
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: AppTheme.inkHint,
                            width: 1.2,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                        child: _avatarFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.file(
                                  _avatarFile!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(
                                Icons.photo_camera_outlined,
                                size: 30,
                                color: AppTheme.inkHint,
                              ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add photo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Member',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkHint,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstCtrl,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'First name *',
                              counterText: '',
                            ),
                            validator: (v) =>
                                (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastCtrl,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'Last name (optional)',
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      maxLength: 254,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        counterText: '',
                      ),
                      validator: validateOptionalEmail,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_emailCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '⚠ Without email, the member portal won\'t be available and check-ins must be done manually.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      maxLength: 20,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        counterText: '',
                      ),
                      validator: validateOptionalPhone,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customIdCtrl,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: 'Member ID (optional)',
                        hintText: 'e.g. GYM-001',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plan & Payment',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkHint,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(isJoined: true),
                            borderRadius: BorderRadius.circular(10),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Joining date',
                                suffixIcon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                ),
                              ),
                              child: Text(
                                _joinedAt != null
                                    ? formatDateFromString(_joinedAt)
                                    : 'Today',
                                style: TextStyle(
                                  color: _joinedAt != null
                                      ? AppTheme.ink
                                      : AppTheme.inkHint,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickDate(isJoined: false),
                            borderRadius: BorderRadius.circular(10),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Next payment date',
                                suffixIcon: Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                ),
                              ),
                              child: Text(
                                _nextPaymentDate != null
                                    ? formatDateFromString(_nextPaymentDate)
                                    : 'Optional',
                                style: TextStyle(
                                  color: _nextPaymentDate != null
                                      ? AppTheme.ink
                                      : AppTheme.inkHint,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Membership plan — required. Without one there is no `memberships`
                    // row, and both invoice paths (the create_invoice_for_membership
                    // trigger and the nightly generate_monthly_invoices cron) key off
                    // that row, so a plan-less member is silently never billed.
                    Consumer(
                      builder: (context, ref, _) {
                        final plans = ref.watch(_memberPlansProvider);
                        return plans.maybeWhen(
                          data: (list) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: list.isEmpty
                                ? _NoPlansBox(onCreate: _createPlan)
                                : DropdownButtonFormField<String>(
                                    value: _planId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Membership plan *',
                                    ),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                    items: list
                                        .map(
                                          (p) => DropdownMenuItem<String>(
                                            value: p['id'] as String,
                                            child: Text(
                                              _planLabel(p),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _selectPlan(
                                        list.firstWhere(
                                          (p) => p['id'] == v,
                                          orElse: () => {},
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
                    ),
                    if (_planId != null) ...[
                      Text(
                        'Plan Amount: $currencySymbol${_planAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _paidAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Paid Amount',
                          prefixText: '$currencySymbol ',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Due Amount: $currencySymbol${_dueAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _dueAmount > 0
                              ? AppTheme.statusWarn
                              : AppTheme.statusActive,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_paidAmount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            value: _paymentMethod,
                            decoration: const InputDecoration(
                              labelText: 'Payment method',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text('Cash'),
                              ),
                              DropdownMenuItem(
                                value: 'upi',
                                child: Text('UPI'),
                              ),
                              DropdownMenuItem(
                                value: 'card',
                                child: Text('Card'),
                              ),
                              DropdownMenuItem(
                                value: 'bank_transfer',
                                child: Text('Bank transfer'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v ?? 'cash'),
                          ),
                        ),
                      TextFormField(
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Recurring discount (optional)',
                          hintText: '0',
                          prefixText: '$currencySymbol ',
                          helperText:
                              'Fixed amount deducted from every auto-generated invoice',
                        ),
                        onChanged: (v) {
                          final parsed = double.tryParse(v.trim()) ?? 0.0;
                          setState(() {
                            _planDiscountAmount = parsed < 0 ? 0 : parsed;
                            _paidAmountCtrl.text = _planAmount.toStringAsFixed(
                              0,
                            );
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Add Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
