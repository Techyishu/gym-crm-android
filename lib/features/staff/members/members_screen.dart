import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/access/role_access.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/billing/advance_payment_date.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/plan_limits.dart';
import '../../../core/services/app_events.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/services/member_photo_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/check_in_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../billing/billing_screen.dart' show PlanFormSheet;
import '../settings/gym_code_sheet.dart';
import 'import_csv_screen.dart';
import 'upcoming_payments_screen.dart' show QuickCollectSheet;
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

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

/// "₹1,200 / mo" — the plan chip's second line. Keeps the billing interval
/// visible, which a plan name alone doesn't always carry.
String _planPriceLabel(Map<String, dynamic> p) {
  final price = (p['price'] as num?)?.toDouble() ?? 0;
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
  return '${formatCurrency(price)} / $unit';
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
              child: Icon(AppIcons.arrowDropDown, size: 20, color: fg),
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

  // Sort + plan filter both run client-side over the already-loaded list.
  static const _sorts = ['Expiry soonest', 'Name A–Z', 'Recently joined'];
  int _sort = 0;
  String? _planFilter;
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

  List<Member> _applyFilter(List<Member> list, Map<String, double> dueMap) {
    var out = switch (_filter) {
      'all' => list,
      'due' => list.where((m) => (dueMap[m.id] ?? 0) > 0).toList(),
      'lapsing' => list.where((m) => _isLapsing(m, _lapsingDays)).toList(),
      _ => list.where((m) => m.status == _filter).toList(),
    };
    if (_planFilter != null) {
      out = out
          .where((m) => m.currentMembership?.plan?.name == _planFilter)
          .toList();
    }
    return _applySort(out);
  }

  List<Member> _applySort(List<Member> list) {
    final out = [...list];
    switch (_sort) {
      case 1:
        out.sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
      case 2:
        out.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
      default:
        // Expiry soonest — members with no renewal date sort last.
        out.sort((a, b) {
          final ad = a.nextPaymentDate;
          final bd = b.nextPaymentDate;
          if (ad == null || ad.isEmpty)
            return (bd == null || bd.isEmpty) ? 0 : 1;
          if (bd == null || bd.isEmpty) return -1;
          return ad.compareTo(bd);
        });
    }
    return out;
  }

  void _pickSort() {
    showAdaptiveSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _sorts.length; i++)
              ListTile(
                leading: Icon(
                  i == _sort
                      ? AppIcons.radioChecked
                      : AppIcons.radioUnchecked,
                  color: i == _sort ? AppTheme.accent : AppTheme.inkHint,
                ),
                title: Text(_sorts[i]),
                onTap: () {
                  setState(() => _sort = i);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pickPlanFilter(List<Member> all) {
    final plans =
        all
            .map((m) => m.currentMembership?.plan?.name)
            .whereType<String>()
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    showAdaptiveSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: SheetHeader(title: 'Filter by plan'),
            ),
            if (plans.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No plans on any member yet.',
                  style: TextStyle(color: AppTheme.inkSoft),
                ),
              ),
            for (final p in plans)
              ListTile(
                leading: Icon(
                  p == _planFilter
                      ? AppIcons.radioChecked
                      : AppIcons.radioUnchecked,
                  color: p == _planFilter ? AppTheme.accent : AppTheme.inkHint,
                ),
                title: Text(p),
                onTap: () {
                  setState(() => _planFilter = p == _planFilter ? null : p);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

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
                                  AppIcons.check,
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
    final canAdd = ref.watch(
      gymPermissionProvider((GymModule.members, GymAction.add)),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _showAddMemberSheet(context),
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(AppIcons.add),
              label: const Text(
                'Add member',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(canAdd, () {
              final all = members.valueOrNull;
              if (all == null || all.isEmpty) return null;
              final active = all.where((m) => m.status == 'active').length;
              return '${all.length} total · $active active';
            }()),
            _buildSearchAndFilter(members.valueOrNull ?? const [], dueMap),
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
                  var filtered = _applyFilter(list, dueMap);
                  if (_search.isNotEmpty) {
                    final q = _search.toLowerCase();
                    final digits = q.replaceAll(RegExp(r'\D'), '');
                    filtered = filtered
                        .where(
                          (m) =>
                              m.fullName.toLowerCase().contains(q) ||
                              (m.customId ?? '').toLowerCase().contains(q) ||
                              (canPii && m.email.toLowerCase().contains(q)) ||
                              (canPii &&
                                  digits.isNotEmpty &&
                                  (m.phone ?? '')
                                      .replaceAll(RegExp(r'\D'), '')
                                      .contains(digits)),
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
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _MemberRow(
                        member: filtered[i],
                        canPii: canPii,
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

  Widget _buildHeader(bool canEdit, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
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
                  AppIcons.moreHoriz,
                  size: 20,
                  color: AppTheme.ink,
                ),
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
                AppIcons.uploadFile,
                color: AppTheme.ink,
              ),
              title: const Text('Import members'),
              onTap: () {
                Navigator.pop(ctx);
                _openImportCsv(context);
              },
            ),
            ListTile(
              leading: const Icon(AppIcons.schedule, color: AppTheme.ink),
              title: const Text('Expiring soon'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/staff/upcoming-payments');
              },
            ),
            ListTile(
              leading: const Icon(AppIcons.qrCode, color: AppTheme.ink),
              title: const Text('Member signup code'),
              subtitle: const Text('Invite members to use the app'),
              onTap: () {
                Navigator.pop(ctx);
                showAdaptiveSheet(
                  context: context,
                  builder: (_) => const GymCodeSheet(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(List<Member> all, Map<String, double> dueMap) {
    final counts = {
      'all': all.length,
      'due': all.where((m) => (dueMap[m.id] ?? 0) > 0).length,
      'lapsing': all.where((m) => _isLapsing(m, _lapsingDays)).length,
      'expired': all.where((m) => m.status == 'expired').length,
      'active': all.where((m) => m.status == 'active').length,
      'frozen': all.where((m) => m.status == 'frozen').length,
    };
    final filters = [
      ('all', 'All', null, null),
      ('due', 'Due', AppTheme.statusDangerBg, AppTheme.statusDanger),
      ('lapsing', 'Expiring', AppTheme.statusWarnBg, AppTheme.statusWarn),
      ('expired', 'Expired', null, null),
      ('active', 'Active', null, null),
      ('frozen', 'On hold', null, null),
    ];

    final search = TextField(
      controller: _searchCtrl,
      decoration: const InputDecoration(
        hintText: 'Name, mobile or member ID',
        prefixIcon: Icon(AppIcons.search, color: AppTheme.inkHint, size: 20),
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
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 280, child: search),
                    const SizedBox(width: 16),
                    Expanded(child: filterRow),
                  ],
                ),
                const SizedBox(height: 10),
                _sortRow(all),
              ],
            )
          : Column(
              children: [
                search,
                const SizedBox(height: 12),
                filterRow,
                const SizedBox(height: 10),
                _sortRow(all),
              ],
            ),
    );
  }

  // tune Filters · swap_vert <sort> · active filter chips (canvas 1b)
  Widget _sortRow(List<Member> all) {
    return Row(
      children: [
        _MiniControl(
          icon: AppIcons.tune,
          label: 'Filters',
          onTap: () => _pickPlanFilter(all),
        ),
        const SizedBox(width: 8),
        _MiniControl(
          icon: AppIcons.swapVert,
          label: _sorts[_sort],
          onTap: _pickSort,
        ),
        if (_planFilter != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _planFilter = null),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _planFilter!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkSoft,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(AppIcons.close, size: 13, color: AppTheme.inkSoft),
              ],
            ),
          ),
        ],
      ],
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

// ── Small pill control (Filters / sort) ─────────────────────────────────────

class _MiniControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppTheme.statusNeutral),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Member Row (grouped card list) ────────────────────────────────────────────

class _MemberRow extends ConsumerWidget {
  final Member member;
  final bool canPii;
  final double due;
  final VoidCallback onReturn;
  const _MemberRow({
    required this.member,
    required this.canPii,
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

  // "ID 001 · Monthly Plan" — identity line (canvas 1b).
  String get _identityLine {
    final parts = <String>[];
    final code = member.customId;
    if (code != null && code.isNotEmpty) parts.add('ID $code');
    final plan = member.currentMembership?.plan?.name;
    if (plan != null && plan.isNotEmpty) parts.add(plan);
    if (parts.isEmpty && canPii && member.email.isNotEmpty) {
      parts.add(member.email);
    }
    return parts.join(' · ');
  }

  // "Expires 26 Sep" / "Expires in 3 days" / "Expired 12 Aug".
  String get _expiryLine {
    final npd = member.nextPaymentDate;
    if (npd == null || npd.isEmpty) return '';
    if (member.status == 'expired') {
      return 'Expired ${formatDateFromString(npd)}';
    }
    final date = DateTime.tryParse(npd);
    if (date != null) {
      final days = date.difference(DateTime.now()).inDays;
      if (days >= 0 && days <= 7) {
        return days == 0 ? 'Expires today' : 'Expires in $days days';
      }
    }
    return 'Expires ${formatDateFromString(npd)}';
  }

  // Manual check-in straight off the list — same shared path the check-in
  // screen uses, so the duplicate-per-day guard and activity log still apply.
  Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
    // Captured before the await — recording a check-in refreshes this list and
    // unmounts the row, so looking the messenger up afterwards finds nothing.
    final messenger = ScaffoldMessenger.of(context);
    final gymId = await ref.read(gymIdProvider.future);
    final r = await checkInMember(memberId: member.id, gymId: gymId);
    showCheckInResult(
      messenger,
      success: r.success,
      already: r.already,
      title: r.title,
      subtitle: r.subtitle,
    );
    if (r.success) onReturn();
  }

  void _showMoreActions(BuildContext context) {
    final phone = (member.phone ?? '').replaceAll(RegExp(r'\D'), '');
    final number = phone.length == 10 ? '91$phone' : phone;
    showAdaptiveSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.person, color: AppTheme.ink),
              title: const Text('Open profile'),
              onTap: () {
                Navigator.pop(ctx);
                context
                    .push('/staff/members/${member.id}')
                    .then((_) => onReturn());
              },
            ),
            if (canPii && phone.isNotEmpty) ...[
              ListTile(
                leading: const Icon(AppIcons.call, color: AppTheme.ink),
                title: const Text('Call'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse('tel:${member.phone}'));
                },
              ),
              ListTile(
                leading: const Icon(
                  AppIcons.chat,
                  color: AppTheme.ink,
                ),
                title: const Text('WhatsApp'),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(
                    Uri.parse('https://wa.me/$number'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = member.status == 'expired';

    return Container(
      decoration: AppTheme.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context
              .push('/staff/members/${member.id}')
              .then((_) => onReturn()),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InitialsAvatar(
                      name: member.fullName,
                      size: 44,
                      photo: member.avatarUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    color: AppTheme.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _pill,
                            ],
                          ),
                          if (_identityLine.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              _identityLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.inkSoft,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_expiryLine.isNotEmpty || due > 0) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (_expiryLine.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      _expiryLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: expired
                                            ? AppTheme.statusDanger
                                            : AppTheme.inkSoft,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                if (_expiryLine.isNotEmpty && due > 0)
                                  const SizedBox(width: 8),
                                if (due > 0)
                                  Text(
                                    'Due ${formatCurrency(due)}',
                                    style: AppTheme.numberStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.statusDanger,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RowAction(
                        label: 'Check in',
                        filled: false,
                        onTap: member.status == 'active'
                            ? () => _checkIn(context, ref)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RowAction(
                      icon: AppIcons.moreHoriz,
                      filled: false,
                      onTap: () => _showMoreActions(context),
                    ),
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

// ── Member row action button ────────────────────────────────────────────────

class _RowAction extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool filled;
  final VoidCallback? onTap;
  const _RowAction({
    this.label,
    this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final bg = filled ? AppTheme.accent : AppTheme.surface2;
    final fg = filled ? Colors.white : AppTheme.ink;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: icon != null ? 40 : null,
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: icon != null
              ? Icon(icon, size: 19, color: fg)
              : Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: fg,
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
    return const StateMessage(
      icon: AppIcons.people,
      title: 'No members here',
      body:
          'Nobody matches this search or filter yet. Clear the filter, or add '
          'your first member with the Add button.',
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
                Icon(AppIcons.add, size: 18, color: AppTheme.accent),
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
Future<void> showAddMemberSheet(BuildContext context) async {
  final added = await showAdaptiveSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    maxWidth: 820,
    maxHeight: 760,
    builder: (_) => const AddMemberSheet(),
  );
  if (added == null || !context.mounted) return;
  await showAdaptiveSheet(
    context: context,
    builder: (_) => _MemberAddedSheet(added: added),
  );
}

/// Canvas 1n "success — after add member": confirms what was created and
/// offers the two things staff actually do next.
class _MemberAddedSheet extends StatelessWidget {
  final Map<String, dynamic> added;
  const _MemberAddedSheet({required this.added});

  @override
  Widget build(BuildContext context) {
    final name = added['name'] as String? ?? 'Member';
    final customId = added['customId'] as String? ?? '';
    final plan = added['plan'] as String? ?? '';
    final outstanding = (added['outstanding'] as num?)?.toDouble() ?? 0;
    final phone = (added['phone'] as String? ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );

    final detail = [
      if (customId.isNotEmpty) 'ID $customId',
      if (plan.isNotEmpty) plan,
      if (outstanding > 0) '${formatCurrency(outstanding)} outstanding',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppTheme.statusActiveBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    AppIcons.check,
                    size: 22,
                    color: AppTheme.statusActive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name added',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (outstanding > 0)
              CardAction(
                label: 'Collect remaining ${formatCurrency(outstanding)}',
                filled: true,
                onTap: () {
                  Navigator.pop(context);
                  showAdaptiveSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => QuickCollectSheet(
                      memberId: added['id'] as String,
                      memberName: name,
                    ),
                  );
                },
              ),
            if (outstanding > 0 && phone.isNotEmpty) const SizedBox(height: 10),
            if (phone.isNotEmpty)
              CardAction(
                label: 'Share welcome message',
                filled: false,
                onTap: () {
                  Navigator.pop(context);
                  final number = phone.length == 10 ? '91$phone' : phone;
                  final text =
                      'Welcome ${name.split(' ').first}! 🎉 '
                      'Excited to have you with us. See you at the gym soon!';
                  launchUrl(
                    Uri.parse(
                      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class AddMemberSheet extends ConsumerStatefulWidget {
  const AddMemberSheet({super.key});

  @override
  ConsumerState<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  // Canvas 1d asks for one name box; first/last are split on save.
  final _nameCtrl = TextEditingController();
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

  /// Email / next payment date / notes stay folded away until asked for.
  bool _moreDetails = false;

  double get _planAmount =>
      (_planPrice - _planDiscountAmount).clamp(0, _planPrice);
  double get _paidAmount => double.tryParse(_paidAmountCtrl.text.trim()) ?? 0;
  double get _dueAmount => (_planAmount - _paidAmount).clamp(0, _planAmount);

  // "Rohit Sharma" → ("Rohit", "Sharma"); a single word keeps last_name empty.
  (String, String) get _splitName {
    final parts = _nameCtrl.text.trim().split(RegExp(r'\s+'))
      ..removeWhere((s) => s.isEmpty);
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _customIdCtrl.dispose();
    _notesCtrl.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  String _selectedPlanName = '';

  void _selectPlan(Map<String, dynamic> plan) {
    _planId = plan['id'] as String?;
    _selectedPlanName = plan['name'] as String? ?? '';
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
            'first_name': _splitName.$1,
            if (_splitName.$2.isNotEmpty) 'last_name': _splitName.$2,
            if (_emailCtrl.text.trim().isNotEmpty)
              'email': _emailCtrl.text.trim(),
            if (_phoneCtrl.text.trim().isNotEmpty)
              'phone': phoneWithCountryCode(_phoneCtrl.text),
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

      notifyGymDataChanged();

      // Hand the caller what it needs to show the "member added" confirmation
      // — this sheet's own context is gone the moment it pops.
      if (mounted) {
        Navigator.pop(context, <String, dynamic>{
          'id': inserted['id'] as String,
          'name': _nameCtrl.text.trim(),
          'customId': _customIdCtrl.text.trim(),
          'plan': _selectedPlanName,
          'outstanding': _dueAmount,
          // Same normalisation as the insert above — this one feeds the
          // "Share welcome message" wa.me link.
          'phone': phoneWithCountryCode(_phoneCtrl.text) ?? '',
        });
      }
    } catch (e) {
      debugPrint('[GymCRM] AddMember error: $e');
      if (mounted) {
        final msg = (e is PostgrestException && e.code == '23505')
            ? 'Member ID "${_customIdCtrl.text.trim()}" is already in use. Please use a different one.'
            : planLimitMessage(e) ?? 'Failed to add member. Please try again.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTopBar(title: 'Add member'),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1 · MEMBER', style: AppTheme.kicker),
                  const SizedBox(height: 8),
                  SheetCard(child: _memberSection()),
                  const SizedBox(height: 18),
                  const Text('2 · MEMBERSHIP', style: AppTheme.kicker),
                  const SizedBox(height: 8),
                  SheetCard(child: _membershipSection()),
                  const SizedBox(height: 18),
                  const Text('3 · PAYMENT', style: AppTheme.kicker),
                  const SizedBox(height: 8),
                  SheetCard(child: _paymentSection()),
                  const SizedBox(height: 16),
                  _moreDetailsSection(),
                ],
              ),
            ),
          ),
        ),
        // Sticky footer so the primary action never scrolls out of reach.
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
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
                  : const Text('Add member'),
            ),
          ),
        ),
      ],
    );
  }

  // ── 1 · Member ─────────────────────────────────────────────────────────────

  Widget _memberSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: _avatarFile != null
                ? Image.file(_avatarFile!, fit: BoxFit.cover)
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        AppIcons.photoCamera,
                        size: 22,
                        color: AppTheme.inkSoft,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Photo',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Full name',
                  counterText: '',
                ),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                maxLength: 20,
                keyboardType: TextInputType.phone,
                // prefixIcon, not prefixText — prefixText stays hidden until
                // the field has focus, and the canvas shows +91 at rest.
                decoration: const InputDecoration(
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 12, right: 4),
                    child: Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  prefixIconConstraints: BoxConstraints(minWidth: 0),
                  hintText: 'Mobile number',
                  counterText: '',
                ),
                validator: validateOptionalPhone,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 2 · Membership ─────────────────────────────────────────────────────────

  Widget _membershipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final plans = ref.watch(_memberPlansProvider);
            return plans.maybeWhen(
              data: (list) {
                if (list.isEmpty) return _NoPlansBox(onCreate: _createPlan);
                // A gym with exactly one plan has no choice to make, but the
                // chip still rendered unselected — so the payment section sat
                // on "Pick a membership plan first" beside what looked like an
                // already-chosen plan, with nothing saying it needed tapping.
                // Post-frame because this runs during build.
                if (list.length == 1 && _planId == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _planId == null) {
                      setState(() => _selectPlan(list.first));
                    }
                  });
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in list)
                      _PlanChip(
                        name: p['name'] as String? ?? 'Plan',
                        priceLabel: _planPriceLabel(p),
                        selected: _planId == p['id'],
                        onTap: () => setState(() => _selectPlan(p)),
                      ),
                  ],
                );
              },
              orElse: () => const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: BoxField(
                label: 'Joining date',
                value: _joinedAt != null
                    ? formatDateFromString(_joinedAt)
                    : 'Today, ${formatDateShort(DateTime.now())}',
                onTap: () => _pickDate(isJoined: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BoxField(
                label: 'Member ID',
                value: _customIdCtrl.text.trim().isEmpty
                    ? 'auto'
                    : _customIdCtrl.text.trim(),
                onTap: _editMemberId,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editMemberId() async {
    final ctrl = TextEditingController(text: _customIdCtrl.text);
    final saved = await showAppDialog<bool>(
      context,
      title: 'Member ID',
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: 'Leave empty to auto-assign',
            counterText: '',
          ),
        ),
      ),
      actions: (ctx) => [
        DialogButton(label: 'Cancel', onTap: () => Navigator.pop(ctx, false)),
        DialogButton(
          label: 'Save',
          filled: true,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (saved == true && mounted) {
      setState(() => _customIdCtrl.text = ctrl.text.trim());
    }
  }

  // ── 3 · Payment ────────────────────────────────────────────────────────────

  Widget _paymentSection() {
    if (_planId == null) {
      return const Text(
        'Pick a membership plan first.',
        style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Discount',
                  hintText: '0',
                  prefixText: '$currencySymbol ',
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v.trim()) ?? 0.0;
                  setState(() {
                    _planDiscountAmount = parsed < 0 ? 0 : parsed;
                    _paidAmountCtrl.text = _planAmount.toStringAsFixed(0);
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _paidAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount paid',
                  prefixText: '$currencySymbol ',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Discount repeats on every auto-generated invoice.',
          style: TextStyle(fontSize: 11, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [
              ('cash', 'Cash'),
              ('upi', 'UPI'),
              ('card', 'Card'),
              ('bank_transfer', 'Bank'),
            ])
              SelectChip(
                label: m.$2,
                selected: _paymentMethod == m.$1,
                onTap: () => setState(() => _paymentMethod = m.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _SummaryLine(label: 'Plan', value: formatCurrency(_planPrice)),
              if (_planDiscountAmount > 0)
                _SummaryLine(
                  label: 'Discount',
                  value: '−${formatCurrency(_planDiscountAmount)}',
                  valueColor: AppTheme.statusActive,
                ),
              _SummaryLine(label: 'Paid', value: formatCurrency(_paidAmount)),
              const Divider(height: 14, color: AppTheme.border),
              _SummaryLine(
                label: 'Outstanding',
                value: formatCurrency(_dueAmount),
                emphasis: true,
                valueColor: _dueAmount > 0
                    ? AppTheme.statusDanger
                    : AppTheme.statusActive,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Add more details ───────────────────────────────────────────────────────

  Widget _moreDetailsSection() {
    if (!_moreDetails) {
      return GestureDetector(
        onTap: () => setState(() => _moreDetails = true),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: const [
            Icon(AppIcons.addCircle, size: 20, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Add more details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Email, next payment date, notes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
              ),
            ),
          ],
        ),
      );
    }
    return SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _emailCtrl,
            maxLength: 254,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              counterText: '',
            ),
            validator: validateOptionalEmail,
          ),
          const SizedBox(height: 12),
          BoxField(
            label: 'Next payment date',
            value: _nextPaymentDate != null
                ? formatDateFromString(_nextPaymentDate)
                : 'From the plan',
            onTap: () => _pickDate(isJoined: false),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Notes',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add-member sheet parts ───────────────────────────────────────────────────

class _PlanChip extends StatelessWidget {
  final String name;
  final String priceLabel;
  final bool selected;
  final VoidCallback onTap;
  const _PlanChip({
    required this.name,
    required this.priceLabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppTheme.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              priceLabel,
              style: AppTheme.numberStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white70 : AppTheme.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                color: emphasis ? AppTheme.ink : AppTheme.inkSoft,
              ),
            ),
          ),
          Text(
            value,
            style: AppTheme.numberStyle(
              fontSize: 13.5,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
              color: valueColor ?? AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}
