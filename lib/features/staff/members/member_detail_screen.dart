import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/access/role_access.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/billing/advance_payment_date.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../shared/widgets/authed_member_image.dart';
import '../../../core/services/check_in_service.dart';
import 'upcoming_payments_screen.dart' show QuickCollectSheet;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/staff/workout/workout_plan_sheet.dart';
import '../../../features/staff/diet/diet_plan_sheet.dart';
import '../../../shared/models/activity_log_entry.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/member_photo.dart';
import '../../../shared/widgets/redesign.dart';
import 'member_plan_viewer.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

// Active membership plans for the current gym (for assign/change actions).
final _detailPlansProvider = FutureProvider<List<Map<String, dynamic>>>((
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

final _memberDueProvider = FutureProvider.family<double, String>(
  (ref, memberId) => memberDueAmount(memberId),
);

final _memberDetailProvider = FutureProvider.family<Member?, String>((
  ref,
  id,
) async {
  final gymId = await ref.read(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('id', id)
      .eq('gym_id', gymId)
      .maybeSingle();
  return data != null ? Member.fromJson(data) : null;
});

final _memberActivityProvider =
    FutureProvider.family<List<ActivityLogEntry>, String>((ref, id) async {
      final raw = await Supabase.instance.client.rpc(
        'get_member_activity_log',
        params: {'p_member_id': id},
      );
      final items = (raw as Map)['items'] as List;
      return items
          .map((e) => ActivityLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });

final _memberCheckInsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      final gymId = await ref.read(gymIdProvider.future);
      return await Supabase.instance.client
          .from('check_ins')
          .select('*')
          .eq('member_id', id)
          .eq('gym_id', gymId)
          .order('checked_in_at', ascending: false)
          .limit(10);
    });

final _memberInvoicesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      final gymId = await ref.read(gymIdProvider.future);
      return await Supabase.instance.client
          .from('invoices')
          .select(
            'id, amount, status, description, due_at, paid_at, created_at, payments(amount, status)',
          )
          .eq('member_id', id)
          .eq('gym_id', gymId)
          .order('created_at', ascending: false)
          .limit(8);
    });

final _memberBatchesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      final data = await Supabase.instance.client
          .from('class_enrollments')
          .select(
            'id, enrolled_at, classes(id, name, color, default_start_time, default_end_time)',
          )
          .eq('member_id', id)
          .order('enrolled_at', ascending: false);
      return (data as List).cast<Map<String, dynamic>>();
    });

final _memberWorkoutPlansProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      try {
        final data = await Supabase.instance.client
            .from('workout_plans')
            .select('id, name, type, days, created_at')
            .eq('member_id', id)
            .order('created_at', ascending: false);
        return (data as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('[GymCRM] Load workout plans error: $e');
        return [];
      }
    });

final _memberDietPlansProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
      try {
        final data = await Supabase.instance.client
            .from('diet_plans')
            .select('id, name, goal, calories, meals, created_at')
            .eq('member_id', id)
            .order('created_at', ascending: false);
        return (data as List).cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('[GymCRM] Load diet plans error: $e');
        return [];
      }
    });

// Devices vary in whether they zero-pad employee IDs ("001" vs "1") — normalize
// on save so it always matches however the device formats it in an ATTLOG push.
String? _normalizeBiometricId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.replaceFirst(RegExp(r'^0+(?=\d)'), '');
}

void _showFullPhoto(BuildContext context, Member m) {
  if (MemberPhotoService.pathFrom(m.avatarUrl) == null) return;
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: InteractiveViewer(
              child: AuthedMemberImage(
                stored: m.avatarUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: -16,
            right: -16,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class MemberDetailScreen extends ConsumerStatefulWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  static const _baseTabs = [
    'Overview',
    'Payments',
    'Attendance',
    'Plans',
    'Fitness',
  ];
  int _tab = 0;

  String get memberId => widget.memberId;

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(_memberDetailProvider(memberId));
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canPii = RoleAccess.canSeeMemberPii(role);
    final canEdit = ref.watch(
      gymPermissionProvider((GymModule.members, GymAction.edit)),
    );
    final canDelete = ref.watch(
      gymPermissionProvider((GymModule.members, GymAction.delete)),
    );
    // Same gate as the standalone activity log — owner/manager only.
    final canSeeActivity = ref.watch(
      gymPermissionProvider((GymModule.reports, GymAction.view)),
    );
    final tabs = [..._baseTabs, if (canSeeActivity) 'Activity'];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: member.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const ErrorState(what: 'this member'),
        data: (m) {
          if (m == null) {
            return const StateMessage(
              icon: AppIcons.personOff,
              title: 'Member not found',
              body: 'This member may have been deleted from your gym.',
            );
          }
          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async {
              ref.invalidate(_memberDetailProvider(memberId));
              ref.invalidate(_memberCheckInsProvider(memberId));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(
                    context,
                    ref,
                    m,
                    canPii: canPii,
                    canEdit: canEdit,
                    canDelete: canDelete,
                  ),
                  Container(
                    color: AppTheme.background,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: UnderlineTabs(
                      tabs: tabs,
                      selectedIndex: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._tabBody(context, ref, m, role, canPii, canEdit),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Canvas 1c splits what used to be one long scroll into five tabs; each
  // one is the same section builder as before, just grouped.
  List<Widget> _tabBody(
    BuildContext context,
    WidgetRef ref,
    Member m,
    String? role,
    bool canPii,
    bool canEdit,
  ) {
    switch (_tab) {
      case 1:
        return [
          _PaymentHistoryBody(memberId: memberId, memberName: m.fullName),
        ];
      case 2:
        return [
          _buildStatTiles(ref),
          const SizedBox(height: 12),
          _buildCheckInHistory(ref),
          const SizedBox(height: 12),
          _buildBatches(ref),
        ];
      case 3:
        return [
          _buildMembershipCard(context, ref, m),
          const SizedBox(height: 12),
          _MemberQuickActions(member: m, canPii: canPii),
        ];
      case 4:
        return [_buildFitnessLinks(context, ref, m, role)];
      case 5:
        return [_MemberActivityBody(memberId: memberId)];
      default:
        return [
          if (canPii) ...[
            _buildContactInfo(context, ref, m, canEdit: canEdit),
            const SizedBox(height: 12),
          ],
          _buildStatTiles(ref),
          const SizedBox(height: 12),
          _buildCheckInHistory(ref),
          const SizedBox(height: 12),
          _buildMemberId(context, m),
        ];
    }
  }

  Future<void> _confirmDeleteMember(
    BuildContext context,
    WidgetRef ref,
    Member m,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete member?',
      body:
          'Permanently delete ${m.fullName}? All their data (memberships, invoices, check-ins) will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: AppIcons.delete,
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'delete_member_secure',
        params: {'p_member_id': m.id},
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[GymCRM] Delete member error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete member')),
        );
      }
    }
  }

  Future<void> _whatsApp(Member m) async {
    final phone = m.phone;
    if (phone == null || phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('https://wa.me/91$cleaned');
    if (await canLaunchUrl(url))
      await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    Member m, {
    required bool canPii,
    required bool canEdit,
    required bool canDelete,
  }) {
    final topPad = MediaQuery.of(context).padding.top;
    final hasPhone = canPii && (m.phone?.isNotEmpty ?? false);
    return Container(
      width: double.infinity,
      color: AppTheme.darkCard,
      padding: EdgeInsets.fromLTRB(16, topPad + 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  AppIcons.arrowBackIosNew,
                  size: 20,
                  color: AppTheme.onDark,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (canDelete)
                IconButton(
                  icon: const Icon(
                    AppIcons.edit,
                    size: 21,
                    color: AppTheme.onDark,
                  ),
                  onPressed: () =>
                      showAdaptiveSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => _EditMemberSheet(member: m),
                      ).then(
                        (_) => ref.invalidate(_memberDetailProvider(memberId)),
                      ),
                ),
              if (canEdit)
                IconButton(
                  icon: const Icon(
                    AppIcons.moreVert,
                    size: 22,
                    color: AppTheme.onDark,
                  ),
                  onPressed: () => showAdaptiveSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(
                              AppIcons.delete,
                              color: AppTheme.statusDanger,
                            ),
                            title: const Text(
                              'Delete member',
                              style: TextStyle(color: AppTheme.statusDanger),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _confirmDeleteMember(context, ref, m);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: m.avatarUrl == null
                    ? null
                    : () => _showFullPhoto(context, m),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard2,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MemberPhoto(
                    stored: m.avatarUrl,
                    fallback: Center(
                      child: Text(
                        initials(m.firstName, m.lastName),
                        style: const TextStyle(
                          color: AppTheme.mintOnDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: AppTheme.onDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _identityLine(ref, m),
                      maxLines: 2,
                      style: const TextStyle(
                        color: AppTheme.onDarkSoft,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusChip(m),
                        if (_planChipLabel(m) case final label?)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard2,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onDarkSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ref.watch(_memberDueProvider(m.id)).valueOrNull case final due?
              when due > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkCard2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OUTSTANDING',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: AppTheme.onDarkSoft,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatCurrency(due),
                          style: AppTheme.numberStyle(
                            fontSize: 22,
                            color: AppTheme.onDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (m.nextPaymentDate?.isNotEmpty ?? false)
                    Text(
                      () {
                        final date = DateTime.tryParse(m.nextPaymentDate!);
                        final overdue =
                            date != null && date.isBefore(DateTime.now());
                        final label = formatDateFromString(m.nextPaymentDate!);
                        return overdue ? 'Pending since $label' : 'Due $label';
                      }(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.onDarkSoft,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroAction(
                  icon: AppIcons.payments,
                  label: 'Collect',
                  filled: true,
                  onTap: canEdit ? () => _collect(context, ref, m) : null,
                ),
              ),
              // Only offered once the plan has actually lapsed — an active
              // member is renewed through Collect, not this shortcut.
              if (m.status == 'expired') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroAction(
                    icon: AppIcons.autorenew,
                    label: 'Renew',
                    onTap: canEdit ? () => _renew(context, ref, m) : null,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _HeroAction(
                  icon: AppIcons.howToReg,
                  label: 'Check in',
                  onTap: m.status == 'active'
                      ? () => _checkIn(context, ref, m)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroAction(
                  icon: AppIcons.chat,
                  label: 'WhatsApp',
                  onTap: hasPhone ? () => _whatsApp(m) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // "ID 001 · Batch: Evening" — the canvas also shows a branch, which this
  // app has no per-member concept of, so it is left out.
  String _identityLine(WidgetRef ref, Member m) {
    final parts = <String>[];
    final code = m.customId;
    if (code != null && code.isNotEmpty) parts.add('ID $code');
    final batches =
        ref.watch(_memberBatchesProvider(memberId)).valueOrNull ?? const [];
    if (batches.isNotEmpty) {
      final cls = batches.first['classes'] as Map<String, dynamic>?;
      final batchName = cls?['name'] as String?;
      if (batchName != null && batchName.isNotEmpty) {
        parts.add('Batch: $batchName');
      }
    }
    parts.add('Member since ${formatDateFromString(m.joinedAt)}');
    return parts.join(' · ');
  }

  Widget _statusChip(Member m) {
    final (bg, fg, label) = switch (m.status) {
      'active' => (AppTheme.statusActiveBg, AppTheme.statusActive, 'Active'),
      'frozen' => (AppTheme.statusNeutralBg, AppTheme.statusNeutral, 'Frozen'),
      'expired' => (AppTheme.statusDangerBg, AppTheme.statusDanger, 'Expired'),
      _ => (AppTheme.statusNeutralBg, AppTheme.statusNeutral, m.status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  // "Monthly · exp 26 Sep"
  String? _planChipLabel(Member m) {
    final plan = m.currentMembership?.plan?.name;
    final npd = m.nextPaymentDate;
    final parts = <String>[
      if (plan != null && plan.isNotEmpty) plan,
      if (npd != null && npd.isNotEmpty) 'exp ${formatDateFromString(npd)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  void _collect(BuildContext context, WidgetRef ref, Member m) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => QuickCollectSheet(memberId: m.id, memberName: m.fullName),
    ).then((_) {
      ref.invalidate(_memberDetailProvider(memberId));
      ref.invalidate(_memberDueProvider(m.id));
    });
  }

  // One-tap reactivation for a lapsed member: confirm, then collect the
  // outstanding due and extend the plan in a single atomic call — the same
  // RPC Collect uses, just without the full payment-method form since this
  // path assumes cash/default terms already agreed with the member.
  Future<void> _renew(BuildContext context, WidgetRef ref, Member m) async {
    final npd = m.nextPaymentDate;
    if (npd == null || npd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Renewal date is missing. Refresh and try again.'),
        ),
      );
      return;
    }
    final due = ref.read(_memberDueProvider(m.id)).valueOrNull;
    final amount = (due != null && due > 0)
        ? due
        : (m.currentMembership?.plan?.price ?? 0);
    if (amount <= 0) {
      _collect(context, ref, m);
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Renew plan?',
      body:
          'This marks ${formatCurrency(amount)} as collected from '
          '${m.fullName} and extends their plan by one cycle. Confirm the '
          'payment was received before continuing.',
      confirmLabel: 'Renew',
      icon: AppIcons.autorenew,
      danger: false,
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await collectMembershipRenewal(
        memberId: m.id,
        expectedNextPaymentDate: npd.split('T').first,
        amount: amount,
        method: 'cash',
      );
      ref.invalidate(_memberDetailProvider(memberId));
      ref.invalidate(_memberDueProvider(m.id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Plan renewed'),
          backgroundColor: AppTheme.statusActive,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(paymentFailureMessage(e))));
    }
  }

  Future<void> _checkIn(BuildContext context, WidgetRef ref, Member m) async {
    // Captured before the await — see showCheckInResult's note.
    final messenger = ScaffoldMessenger.of(context);
    final gymId = await ref.read(gymIdProvider.future);
    final r = await checkInMember(memberId: m.id, gymId: gymId);
    showCheckInResult(
      messenger,
      success: r.success,
      already: r.already,
      title: r.title,
      subtitle: r.subtitle,
    );
    if (r.success) ref.invalidate(_memberCheckInsProvider(memberId));
  }

  Widget _buildStatTiles(WidgetRef ref) {
    final checkIns = ref.watch(_memberCheckInsProvider(memberId));
    final list = checkIns.valueOrNull ?? const <Map<String, dynamic>>[];
    final now = DateTime.now();
    final monthCount = list.where((ci) {
      final dt = DateTime.tryParse(ci['checked_in_at'] as String? ?? '');
      return dt != null && dt.year == now.year && dt.month == now.month;
    }).length;
    String lastVisit = '—';
    if (list.isNotEmpty) {
      final dt = DateTime.tryParse(
        list.first['checked_in_at'] as String? ?? '',
      );
      if (dt != null) {
        final days = now.difference(dt).inDays;
        lastVisit = days == 0
            ? 'Today'
            : days == 1
            ? '1d ago'
            : '${days}d ago';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: StatTileLight(
              label: 'Check-ins / month',
              value: '$monthCount',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTileLight(label: 'Last visit', value: lastVisit),
          ),
        ],
      ),
    );
  }

  // ── Quick links: Workout plan · Diet plan · Payment history ────────────────

  Widget _buildFitnessLinks(
    BuildContext context,
    WidgetRef ref,
    Member m,
    String? role,
  ) {
    final workoutPlans =
        ref.watch(_memberWorkoutPlansProvider(memberId)).valueOrNull ??
        const [];
    final dietPlans =
        ref.watch(_memberDietPlansProvider(memberId)).valueOrNull ?? const [];
    final canWorkout = RoleAccess.canManageWorkoutPlans(role);
    final canDiet = RoleAccess.canManageDietPlans(role);

    String workoutSummary() {
      if (workoutPlans.isEmpty) return canWorkout ? 'Add plan' : '—';
      return workoutPlans.first['name'] as String? ?? 'View';
    }

    String dietSummary() {
      if (dietPlans.isEmpty) return canDiet ? 'Add plan' : '—';
      final kcal = dietPlans.first['calories'] as int?;
      return kcal != null
          ? '$kcal kcal'
          : (dietPlans.first['name'] as String? ?? 'View');
    }

    Future<void> openWorkout() async {
      if (workoutPlans.isEmpty) {
        if (!canWorkout) return;
        final saved = await showAdaptiveSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              WorkoutPlanSheet(memberId: memberId, memberName: m.fullName),
        );
        if (saved == true)
          ref.invalidate(_memberWorkoutPlansProvider(memberId));
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WorkoutPlanViewerPage(
            plan: workoutPlans.first,
            memberId: memberId,
            memberName: m.fullName,
            canManage: canWorkout,
          ),
        ),
      );
      if (changed == true)
        ref.invalidate(_memberWorkoutPlansProvider(memberId));
    }

    Future<void> openDiet() async {
      if (dietPlans.isEmpty) {
        if (!canDiet) return;
        final saved = await showAdaptiveSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              DietPlanSheet(memberId: memberId, memberName: m.fullName),
        );
        if (saved == true) ref.invalidate(_memberDietPlansProvider(memberId));
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DietPlanViewerPage(
            plan: dietPlans.first,
            memberId: memberId,
            memberName: m.fullName,
            canManage: canDiet,
          ),
        ),
      );
      if (changed == true) ref.invalidate(_memberDietPlansProvider(memberId));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CardList(
        children: [
          _QuickLinkRow(
            icon: AppIcons.fitness,
            iconBg: AppTheme.accentSoft,
            iconColor: AppTheme.accent,
            label: 'Workout plan',
            summary: workoutSummary(),
            onTap: openWorkout,
          ),
          _QuickLinkRow(
            icon: AppIcons.restaurant,
            iconBg: AppTheme.statusActiveBg,
            iconColor: AppTheme.statusActive,
            label: 'Diet plan',
            summary: dietSummary(),
            onTap: openDiet,
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipCard(BuildContext context, WidgetRef ref, Member m) {
    final due = ref.watch(_memberDueProvider(m.id)).valueOrNull ?? 0;
    final ms = m.currentMembership;
    final npd = m.nextPaymentDate != null
        ? DateTime.tryParse(m.nextPaymentDate!)
        : null;
    final started = ms != null ? DateTime.tryParse(ms.startsAt) : null;
    int? daysLeft;
    double? progress;
    if (npd != null) {
      daysLeft = npd.difference(DateTime.now()).inDays;
      if (started != null && npd.isAfter(started)) {
        final total = npd.difference(started).inDays;
        progress = total > 0
            ? ((total - daysLeft) / total).clamp(0.0, 1.0)
            : null;
      }
    }
    final planTitle = ms?.plan != null
        ? '${ms!.plan!.name} · ${formatCurrency(ms.plan!.price)}'
        : 'No active plan';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current plan',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      planTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(status: m.status),
                ],
              ),
              if (ms?.hasDiscount ?? false) ...[
                const SizedBox(height: 4),
                Text(
                  '− ${formatCurrency(ms!.discountAmount)} per invoice',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.statusActive,
                  ),
                ),
              ],
              if (due > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.statusDangerBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Due ${formatCurrency(due)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.statusDanger,
                    ),
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.surface2,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.statusActive,
                    ),
                  ),
                ),
              ],
              if (started != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Started ${formatDateFromString(ms!.startsAt)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
              if (npd != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Renews ${formatDateFromString(m.nextPaymentDate)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      daysLeft != null && daysLeft >= 0
                          ? '$daysLeft days left'
                          : '${daysLeft!.abs()} days overdue',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: daysLeft >= 0
                            ? AppTheme.ink
                            : AppTheme.statusDanger,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactInfo(
    BuildContext context,
    WidgetRef ref,
    Member m, {
    required bool canEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Contact'),
              const SizedBox(height: 12),
              if (m.customId != null && m.customId!.isNotEmpty)
                _InfoRow(label: 'Member ID', value: m.customId!),
              _InfoRow(label: 'Email', value: m.email),
              _InfoRow(label: 'Phone', value: m.phone ?? '-'),
              if (m.notes != null && m.notes!.isNotEmpty)
                _InfoRow(label: 'Notes', value: m.notes!),
              _BiometricIdRow(
                member: m,
                canEdit: canEdit,
                onTap: canEdit
                    ? () => _showEditBiometricIdDialog(context, ref, m)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditBiometricIdDialog(
    BuildContext context,
    WidgetRef ref,
    Member m,
  ) async {
    final ctrl = TextEditingController(text: m.biometricId ?? '');
    final saved = await showAppDialog<bool>(
      context,
      title: 'Biometric Device ID',
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 001',
            helperText: 'Employee number enrolled on fingerprint machine',
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

    if (saved != true) return;

    try {
      await Supabase.instance.client
          .from('members')
          .update({'biometric_id': _normalizeBiometricId(ctrl.text)})
          .eq('id', m.id);
      ref.invalidate(_memberDetailProvider(m.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Widget _buildBatches(WidgetRef ref) {
    final batches = ref.watch(_memberBatchesProvider(memberId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Enrolled Batches'),
              const SizedBox(height: 12),
              batches.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? const Text(
                        'Not enrolled in any batch.',
                        style: TextStyle(color: AppTheme.inkHint),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final cls =
                              list[i]['classes'] as Map<String, dynamic>?;
                          if (cls == null) return const SizedBox.shrink();
                          final color = _parseColor(cls['color'] as String?);
                          final startTime =
                              cls['default_start_time'] as String?;
                          final endTime = cls['default_end_time'] as String?;
                          final timeStr = (startTime != null && endTime != null)
                              ? '$startTime–$endTime'
                              : null;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: color, width: 3),
                              ),
                              color: color.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cls['name'] as String? ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                if (timeStr != null)
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.inkHint,
                                    ),
                                  ),
                              ],
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

  Widget _buildCheckInHistory(WidgetRef ref) {
    final checkIns = ref.watch(_memberCheckInsProvider(memberId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Recent Check-ins'),
              const SizedBox(height: 12),
              checkIns.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? const Text(
                        'No check-ins yet',
                        style: TextStyle(color: AppTheme.inkHint),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppTheme.border, height: 1),
                        itemBuilder: (_, i) {
                          final ci = list[i];
                          final method = (ci['method'] as String? ?? 'manual');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.statusActiveBg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    AppIcons.check,
                                    size: 16,
                                    color: AppTheme.statusActive,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    formatDateTimeFromString(
                                      ci['checked_in_at'] as String?,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                                // Method badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.statusNeutralBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    method.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.statusNeutral,
                                    ),
                                  ),
                                ),
                              ],
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

  Widget _buildMemberId(BuildContext context, Member m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MEMBER ID',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.inkHint,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.id,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppTheme.inkSoft,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(AppIcons.copy, size: 18, color: AppTheme.inkHint),
              onPressed: () {
                // Copy to clipboard
                final data = ClipboardData(text: m.id);
                Clipboard.setData(data);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Member ID copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dark-hero quick action tile (Collect / Renew / Check in / WhatsApp) ─────

class _HeroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  const _HeroAction({
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: filled ? AppTheme.accent : AppTheme.darkCard2,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 19,
                color: filled ? Colors.white : AppTheme.onDark,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: filled ? Colors.white : AppTheme.onDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Member Quick Actions ────────────────────────────────────────────────────
// Mirrors the web member-slideover quick actions: WhatsApp, Hold/Unhold,
// and membership plan management (assign / change / cancel).
class _MemberQuickActions extends ConsumerStatefulWidget {
  final Member member;
  final bool canPii;
  const _MemberQuickActions({required this.member, required this.canPii});

  @override
  ConsumerState<_MemberQuickActions> createState() =>
      _MemberQuickActionsState();
}

class _MemberQuickActionsState extends ConsumerState<_MemberQuickActions> {
  bool _busy = false;

  Member get m => widget.member;
  SupabaseClient get _client => Supabase.instance.client;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _whatsapp() async {
    final phone = m.phone;
    if (phone == null || phone.trim().isEmpty) return;
    await _showWaDialog();
  }

  Future<void> _showWaDialog() async {
    if (!mounted) return;
    String tpl = 'custom';
    String msg = 'Hi ${m.firstName}, ';

    String defaultMsg(String t) => switch (t) {
      'expiry' =>
        'Hi ${m.firstName}! Your membership is expiring soon. Please renew to keep access. 💪',
      'payment' =>
        'Hi ${m.firstName}, you have a pending payment. Please clear it at your earliest. Thank you!',
      'welcome' =>
        'Welcome ${m.firstName}! 🎉 Excited to have you. See you at the gym soon!',
      'checkin' =>
        'Hi ${m.firstName}! We miss you. Come back and keep your goals on track! 💪',
      _ => 'Hi ${m.firstName}, ',
    };

    await showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          const templates = [
            ('custom', 'Custom'),
            ('expiry', 'Fee reminder'),
            ('payment', 'Payment'),
            ('welcome', 'Welcome'),
            ('checkin', 'Renewal'),
          ];
          final tplIndex = templates
              .indexWhere((t) => t.$1 == tpl)
              .clamp(0, templates.length - 1);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        AppIcons.chatActive,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Send WhatsApp',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => PillChip(
                      label: templates[i].$2,
                      selected: tplIndex == i,
                      onTap: () => setS(() {
                        tpl = templates[i].$1;
                        msg = defaultMsg(templates[i].$1);
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: msg,
                  maxLines: 4,
                  onChanged: (v) => msg = v,
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final clean = m.phone!.replaceAll(RegExp(r'\D'), '');
                    final number = clean.startsWith('91') ? clean : '91$clean';
                    final uri = Uri.parse(
                      'https://wa.me/$number?text=${Uri.encodeComponent(msg)}',
                    );
                    if (!await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    )) {
                      _toast('Could not open WhatsApp');
                    }
                  },
                  icon: const Icon(AppIcons.send, size: 16),
                  label: const Text('Send on WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleHold() async {
    final newStatus = m.status == 'frozen' ? 'active' : 'frozen';
    setState(() => _busy = true);
    try {
      await _client
          .from('members')
          .update({'status': newStatus})
          .eq('id', m.id);
      ref.invalidate(_memberDetailProvider(m.id));
      _toast(newStatus == 'frozen' ? 'Membership put on hold' : 'Hold removed');
    } catch (e) {
      debugPrint('[GymCRM] Toggle hold error: $e');
      _toast('Failed to update status');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendInvite() async {
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      final session =
          auth.currentSession ?? (await auth.refreshSession()).session;
      final token = session?.accessToken;
      if (token == null) {
        _toast('Session expired. Please sign in again.');
        return;
      }
      final res = await http.post(
        Uri.parse('https://www.gymcrm.in/api/members/${m.id}/invite'),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _toast('Portal invite sent to ${m.email}');
      } else {
        final body = jsonDecode(res.body) as Map;
        _toast(body['error']?.toString() ?? 'Failed to send invite');
      }
    } catch (e) {
      if (mounted) _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelPlan() async {
    final ms = m.currentMembership;
    if (ms == null || ms.status != 'active') return;
    final ok = await showConfirmDialog(
      context,
      title: 'Cancel membership?',
      body:
          "${m.firstName}'s current plan will be cancelled. This can't be undone.",
      cancelLabel: 'Keep plan',
      confirmLabel: 'Cancel it',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _client
          .from('memberships')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', ms.id);
      ref.invalidate(_memberDetailProvider(m.id));
      _toast('Membership cancelled');
    } catch (e) {
      debugPrint('[GymCRM] Cancel plan error: $e');
      _toast('Failed to cancel membership');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _managePlan() async {
    ref.invalidate(_detailPlansProvider);
    final plans = await ref.read(_detailPlansProvider.future);
    if (!mounted) return;
    if (plans.isEmpty) {
      _toast('No active plans. Create one in Billing first.');
      return;
    }
    final currentPlanId = m.currentMembership?.plan?.id;
    var picked =
        currentPlanId ??
        (plans.isNotEmpty ? plans.first['id'] as String : null);
    final selected = await showAdaptiveSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHeader(title: 'Change plan'),
                const SizedBox(height: 16),
                ...plans.map((p) {
                  final id = p['id'] as String;
                  final selected = picked == id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => setS(() => picked = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.accentSoft
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? AppTheme.accent : AppTheme.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p['name'] as String? ?? '',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                            Text(
                              formatCurrency(
                                (p['price'] as num?)?.toDouble() ?? 0,
                              ),
                              style: AppTheme.numberStyle(fontSize: 14.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: picked == null
                      ? null
                      : () => Navigator.pop(context, picked),
                  child: const Text('Switch plan'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected == null) return;

    // Optional recurring discount for this member.
    final discountCtrl = TextEditingController();
    final discount = await showAdaptiveSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DiscountSheet(
        title: 'Recurring Discount',
        helperText:
            'Fixed amount deducted from every auto-generated invoice for this member.',
        controller: discountCtrl,
        confirmLabel: 'Confirm',
        skipLabel: 'No Discount',
        onSkip: () => Navigator.pop(ctx, 0.0),
        onConfirm: () {
          final v = double.tryParse(discountCtrl.text.trim()) ?? 0.0;
          Navigator.pop(ctx, v < 0 ? 0.0 : v);
        },
      ),
    );
    discountCtrl.dispose();

    setState(() => _busy = true);
    try {
      // Plan cycle starts on the member's join date, not on assignment date.
      // Membership is open-ended — next_payment_date tracks renewal, not ends_at.
      final startsAt = DateTime.tryParse(m.joinedAt) ?? DateTime.now().toUtc();

      // Extend from the member's current next_payment_date when one exists —
      // matches how Collect Payment already advances dates (from the date
      // itself, not from today or from join date). Only members who never
      // had a next_payment_date fall back to join date + plan duration.
      final plan = plans.firstWhere(
        (p) => p['id'] == selected,
        orElse: () => {},
      );
      final months =
          (plan['billing_interval_months'] as int?) ??
          const {
            'monthly': 1,
            'quarterly': 3,
            'biannual': 6,
            'annual': 12,
          }[plan['billing_interval']] ??
          1;
      final currentNpd = m.nextPaymentDate;
      final today = DateTime.now().toUtc();
      final todayStr = today.toIso8601String().split('T').first;
      final hasRemainingTime =
          currentNpd != null &&
          currentNpd.isNotEmpty &&
          (DateTime.tryParse(
                currentNpd,
              )?.isAfter(DateTime(today.year, today.month, today.day)) ??
              false);

      String anchor;
      if (hasRemainingTime) {
        if (!mounted) return;
        final choice = await showAdaptiveSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              _PlanStartChoiceSheet(todayStr: todayStr, currentNpd: currentNpd),
        );
        if (choice == null) {
          setState(() => _busy = false);
          return;
        }
        anchor = choice == 'today' ? todayStr : currentNpd;
      } else {
        anchor = (currentNpd != null && currentNpd.isNotEmpty)
            ? currentNpd
            : startsAt.toIso8601String().split('T').first;
      }
      final derived = advancePaymentDate(anchor, months: months) ?? anchor;

      // Cancel old membership + insert new one + update member row, atomically
      // (single DB transaction via RPC) so a mid-flow interruption can't leave
      // the member with an old-cancelled-but-no-new-active membership.
      await _client.rpc(
        'change_member_plan',
        params: {
          'p_member_id': m.id,
          'p_plan_id': selected,
          'p_starts_at': startsAt.toIso8601String(),
          'p_discount_amount': discount ?? 0.0,
          'p_next_payment_date': derived,
          'p_billing_interval_months': months,
        },
      );
      ref.invalidate(_memberDetailProvider(m.id));
      notifyGymDataChanged();
      _toast('Plan assigned');
    } catch (e) {
      debugPrint('[GymCRM] Assign plan error: $e');
      _toast('Failed to assign plan');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editDiscount() async {
    final ms = m.currentMembership;
    if (ms == null) return;

    final discountCtrl = TextEditingController(
      text: ms.discountAmount > 0 ? ms.discountAmount.toStringAsFixed(0) : '',
    );
    final newDiscount = await showAdaptiveSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DiscountSheet(
        title: 'Edit Recurring Discount',
        helperText:
            'Fixed amount deducted from every auto-generated invoice. Set to 0 to remove.',
        controller: discountCtrl,
        confirmLabel: 'Save',
        skipLabel: 'Cancel',
        onSkip: () => Navigator.pop(ctx),
        onConfirm: () {
          final v = double.tryParse(discountCtrl.text.trim()) ?? 0.0;
          Navigator.pop(ctx, v < 0 ? 0.0 : v);
        },
      ),
    );
    discountCtrl.dispose();
    if (newDiscount == null) return;

    setState(() => _busy = true);
    try {
      await _client
          .from('memberships')
          .update({'discount_amount': newDiscount})
          .eq('id', ms.id);
      ref.invalidate(_memberDetailProvider(m.id));
      _toast('Discount updated');
    } catch (e) {
      debugPrint('[GymCRM] Edit discount error: $e');
      _toast('Failed to update discount');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActivePlan = m.currentMembership?.status == 'active';
    final canPii = widget.canPii;
    final canEdit = ref.watch(
      gymPermissionProvider((GymModule.members, GymAction.edit)),
    );
    final canFreeze = ref.watch(
      gymPermissionProvider((GymModule.members, GymAction.freeze)),
    );
    final canEditMembership = ref.watch(
      gymPermissionProvider((GymModule.memberships, GymAction.edit)),
    );
    final canDeleteMembership = ref.watch(
      gymPermissionProvider((GymModule.memberships, GymAction.delete)),
    );
    final showWhatsApp = canPii && m.phone != null && m.phone!.isNotEmpty;
    final showHold =
        canFreeze && (m.status == 'active' || m.status == 'frozen');
    final showInvite = canEdit && m.email.isNotEmpty && m.userId == null;
    if (!canPii &&
        !canEdit &&
        !canFreeze &&
        !canEditMembership &&
        !canDeleteMembership) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[
      if (showWhatsApp)
        _ActionRow(
          icon: AppIcons.chat,
          iconBg: const Color(0xFFDDEFE2),
          iconColor: const Color(0xFF25D366),
          label: 'WhatsApp',
          onTap: _busy ? null : _whatsapp,
        ),
      if (showHold)
        _ActionRow(
          icon: m.status == 'frozen' ? AppIcons.play : AppIcons.pause,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: m.status == 'frozen' ? 'Remove hold' : 'Hold membership',
          onTap: _busy ? null : _toggleHold,
        ),
      if (canEditMembership)
        _ActionRow(
          icon: AppIcons.creditCardActive,
          iconBg: AppTheme.accentSoft,
          iconColor: AppTheme.accent,
          label: hasActivePlan ? 'Change plan' : 'Assign plan',
          onTap: _busy ? null : _managePlan,
        ),
      if (canEditMembership && hasActivePlan)
        _ActionRow(
          icon: AppIcons.edit,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: m.currentMembership?.hasDiscount == true
              ? 'Edit recurring discount (${formatCurrency(m.currentMembership!.discountAmount)} off)'
              : 'Add recurring discount',
          onTap: _busy ? null : _editDiscount,
        ),
      if (showInvite)
        _ActionRow(
          icon: AppIcons.mail,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: 'Send portal invite',
          onTap: _busy ? null : _sendInvite,
        ),
      if (canDeleteMembership && hasActivePlan)
        _ActionRow(
          icon: AppIcons.delete,
          iconBg: AppTheme.statusDangerBg,
          iconColor: AppTheme.statusDanger,
          label: 'Cancel plan',
          labelColor: AppTheme.statusDanger,
          onTap: _busy ? null : _cancelPlan,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppTheme.border),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Discount bottom sheet ──────────────────────────────────────────────────────

class _PlanStartChoiceSheet extends StatefulWidget {
  final String todayStr;
  final String currentNpd;
  const _PlanStartChoiceSheet({
    required this.todayStr,
    required this.currentNpd,
  });

  @override
  State<_PlanStartChoiceSheet> createState() => _PlanStartChoiceSheetState();
}

class _PlanStartChoiceSheetState extends State<_PlanStartChoiceSheet> {
  String _picked = 'today';

  Widget _option({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _picked == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _picked = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentSoft : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(
            title: 'Start new plan from?',
            subtitle:
                'Their current plan is active till ${formatDateFromString(widget.currentNpd)}.',
          ),
          const SizedBox(height: 16),
          _option(
            value: 'today',
            title: 'Today (${formatDateFromString(widget.todayStr)})',
            subtitle:
                'New plan starts now. Remaining days on the old plan are dropped.',
          ),
          _option(
            value: 'end',
            title: formatDateFromString(widget.currentNpd),
            subtitle:
                'New plan starts after the old one ends. Nothing dropped, no gap.',
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _picked),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class _DiscountSheet extends StatelessWidget {
  final String title;
  final String helperText;
  final TextEditingController controller;
  final String confirmLabel;
  final String skipLabel;
  final VoidCallback onSkip;
  final VoidCallback onConfirm;

  const _DiscountSheet({
    required this.title,
    required this.helperText,
    required this.controller,
    required this.confirmLabel,
    required this.skipLabel,
    required this.onSkip,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (ctx, setS) {
        final discount = double.tryParse(controller.text.trim()) ?? 0;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title: title, subtitle: helperText),
              const SizedBox(height: 18),
              const FieldLabel('Discount amount'),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: '$currencySymbol ',
                ),
              ),
              if (discount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: AppTheme.cardDecoration(),
                  child: Row(
                    children: [
                      const Text(
                        'Discount applied',
                        style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                      ),
                      const Spacer(),
                      Text(
                        '− ${formatCurrency(discount)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.statusActive,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onConfirm, child: Text(confirmLabel)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onSkip,
                  child: Text(
                    skipLabel,
                    style: const TextStyle(color: AppTheme.inkSoft),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFF999999);
  final h = hex.replaceAll('#', '');
  try {
    return Color(int.parse('FF$h', radix: 16));
  } catch (e) {
    debugPrint('[GymCRM] Parse plan color error for "$hex": $e');
    return const Color(0xFF999999);
  }
}

// ── Expandable Section ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppTheme.border, height: 1),
      ],
    );
  }
}

// ── Status Chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  static (Color, Color) _statusColors(String status) => switch (status) {
    'active' => (AppTheme.statusActiveBg, AppTheme.statusActive),
    'frozen' => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
    'expired' => (AppTheme.statusWarnBg, AppTheme.statusWarn),
    'cancelled' => (AppTheme.statusDangerBg, AppTheme.statusDanger),
    _ => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
  };
}

// ── Info Row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.ink,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricIdRow extends StatelessWidget {
  final Member member;
  final bool canEdit;
  final VoidCallback? onTap;
  const _BiometricIdRow({
    required this.member,
    required this.canEdit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final value = member.biometricId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 100,
            child: Text(
              'Biometric ID',
              style: TextStyle(
                color: AppTheme.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? 'Not set' : value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: (value == null || value.isEmpty)
                    ? AppTheme.inkHint
                    : AppTheme.ink,
                fontSize: 13,
              ),
            ),
          ),
          if (canEdit)
            GestureDetector(
              onTap: onTap,
              child: const Icon(
                AppIcons.edit,
                size: 16,
                color: AppTheme.inkHint,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Edit Member Sheet ─────────────────────────────────────────────────────────

class _EditMemberSheet extends StatefulWidget {
  final Member member;
  const _EditMemberSheet({required this.member});

  @override
  State<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<_EditMemberSheet> {
  // One name box, split back into first/last on save — same as Add member.
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _customIdCtrl;
  late final TextEditingController _biometricIdCtrl;
  late final TextEditingController _notesCtrl;
  late String _status;
  String? _nextPaymentDate;
  // Always derived from the member's active plan, never staff-editable here
  // — a manual chip that could disagree with the assigned plan silently
  // mis-billed members every cycle (2026-08-26 incident).
  late int _billingIntervalMonths;
  String? _joinedAt;
  File? _avatarFile;
  bool _loading = false;
  bool _moreDetails = false;

  // "Rohit Sharma" → ("Rohit", "Sharma"); a single word keeps last_name empty.
  (String, String) get _splitName {
    final parts = _nameCtrl.text.trim().split(RegExp(r'\s+'))
      ..removeWhere((s) => s.isEmpty);
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');
    return (parts.first, parts.sublist(1).join(' '));
  }

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _nameCtrl = TextEditingController(text: m.fullName.trim());
    _emailCtrl = TextEditingController(text: m.email);
    _phoneCtrl = TextEditingController(text: m.phone ?? '');
    _customIdCtrl = TextEditingController(text: m.customId ?? '');
    _biometricIdCtrl = TextEditingController(text: m.biometricId ?? '');
    _notesCtrl = TextEditingController(text: m.notes ?? '');
    _status = m.status;
    _nextPaymentDate = m.nextPaymentDate;
    _billingIntervalMonths =
        m.currentMembership?.plan?.resolvedIntervalMonths ??
        m.billingIntervalMonths;
    _joinedAt = m.joinedAt;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _customIdCtrl.dispose();
    _biometricIdCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted)
      setState(() => _avatarFile = File(picked.path));
  }

  Future<String?> _uploadAvatar() async {
    if (_avatarFile == null) return null;
    final gymId = widget.member.gymId;
    final ext = _avatarFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    // Stable per-member path: re-uploads overwrite the same object instead of
    // accumulating a new orphaned file (and egress cost) on every edit.
    final filename = '$gymId/${widget.member.id}.$ext';
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
    final current = isJoined ? _joinedAt : _nextPaymentDate;
    final initial = current != null ? DateTime.tryParse(current) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final s = picked.toIso8601String().split('T')[0];
      setState(() => isJoined ? _joinedAt = s : _nextPaymentDate = s);
    }
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (email.isNotEmpty && !isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address')),
      );
      return;
    }
    if (phone.isNotEmpty && !isValidIndianMobile(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit mobile number')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final newAvatarUrl = await _uploadAvatar();

      await Supabase.instance.client
          .from('members')
          .update({
            'first_name': _splitName.$1,
            'last_name': _splitName.$2,
            'email': _emailCtrl.text.trim().isEmpty
                ? null
                : _emailCtrl.text.trim(),
            if (_phoneCtrl.text.trim().isNotEmpty)
              'phone': phoneWithCountryCode(_phoneCtrl.text)
            else
              'phone': null,
            'custom_id': _customIdCtrl.text.trim().isEmpty
                ? null
                : _customIdCtrl.text.trim(),
            'biometric_id': _normalizeBiometricId(_biometricIdCtrl.text),
            'notes': _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            'status': _status,
            if (_joinedAt != null) 'joined_at': _joinedAt,
            'next_payment_date': _nextPaymentDate,
            'billing_interval_months': _billingIntervalMonths,
            if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
          })
          .eq('id', widget.member.id);

      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.code == '23505'
            ? 'A member with this ID already exists.'
            : 'Failed to save. Please try again.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please try again.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTopBar(title: 'Edit member'),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                const SizedBox(height: 16),
                _moreDetailsSection(),
              ],
            ),
          ),
        ),
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
                  : const Text('Save changes'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _memberSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: _avatarFile != null
                    ? Image.file(_avatarFile!, fit: BoxFit.cover)
                    : MemberPhoto(
                        stored: widget.member.avatarUrl,
                        fallback: Center(
                          child: Text(
                            initials(
                              widget.member.firstName,
                              widget.member.lastName,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    AppIcons.edit,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _membershipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: BoxField(
                label: 'Joining date',
                value: _joinedAt != null
                    ? formatDateFromString(_joinedAt)
                    : 'Not set',
                onTap: () => _pickDate(isJoined: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BoxField(
                label: 'Next payment',
                value: _nextPaymentDate != null
                    ? formatDateFromString(_nextPaymentDate)
                    : 'Not set',
                onTap: () => _pickDate(isJoined: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Status',
          style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in const [
              ('active', 'Active'),
              ('frozen', 'Frozen'),
              ('expired', 'Expired'),
              ('cancelled', 'Cancelled'),
            ])
              SelectChip(
                label: s.$2,
                selected: _status == s.$1,
                onTap: () => setState(() => _status = s.$1),
              ),
          ],
        ),
      ],
    );
  }

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
              'More details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.accent,
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Email, member ID, biometric, notes',
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
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_emailCtrl.text.trim().isEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              '⚠ Without email, the member portal won\'t be available and check-ins must be done manually.',
              style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _customIdCtrl,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Member ID',
              hintText: 'e.g. GYM-001',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _biometricIdCtrl,
            maxLength: 20,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Biometric device ID',
              hintText: 'e.g. 001',
              counterText: '',
              helperText: 'Employee number enrolled on fingerprint machine',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ],
      ),
    );
  }
}

// ── Diet plan tile ────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? AppTheme.inkHint
                      : (labelColor ?? AppTheme.ink),
                ),
              ),
            ),
            Icon(AppIcons.chevronRight, size: 18, color: AppTheme.inkHint),
          ],
        ),
      ),
    );
  }
}

class _QuickLinkRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String summary;
  final VoidCallback onTap;

  const _QuickLinkRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(AppIcons.chevronRight, size: 18, color: AppTheme.inkHint),
          ],
        ),
      ),
    );
  }
}

// ── Payment history page ──────────────────────────────────────────────────────

class _MemberActivityBody extends ConsumerWidget {
  final String memberId;
  const _MemberActivityBody({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(_memberActivityProvider(memberId));

    return activity.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'this member\'s activity'),
      data: (list) {
        if (list.isEmpty) {
          return const StateMessage(
            icon: AppIcons.historyToggleOff,
            title: 'No activity yet',
            body: 'Changes made to this member will show up here.',
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final item = list[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: const CircleAvatar(
                backgroundColor: AppTheme.activeBg,
                child: Icon(AppIcons.history, color: AppTheme.ink, size: 19),
              ),
              title: Text(
                item.actionLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                [
                  item.actorRole != null
                      ? '${item.actorName} (${item.actorRole![0].toUpperCase()}${item.actorRole!.substring(1)})'
                      : item.actorName,
                  DateFormat('d MMM, h:mm a').format(item.createdAt),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: item.amount == null
                  ? const Icon(AppIcons.chevronRight, size: 18)
                  : Text(
                      formatCurrency(item.amount!),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
              onTap: () => context.push('/staff/activity-log/${item.id}'),
            );
          },
        );
      },
    );
  }
}

class _PaymentHistoryBody extends ConsumerWidget {
  final String memberId;
  final String memberName;
  const _PaymentHistoryBody({required this.memberId, required this.memberName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(_memberInvoicesProvider(memberId));

    return invoices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'payment history'),
      data: (list) {
        if (list.isEmpty) {
          return const StateMessage(
            icon: AppIcons.receipt,
            title: 'No payments yet',
            body: 'Payments you collect from this member will be listed here.',
          );
        }
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Container(
              decoration: AppTheme.cardDecoration(),
              child: Column(
                children: list.asMap().entries.map((e) {
                  final inv = e.value;
                  final status = inv['status'] as String? ?? 'open';
                  final isPaid = status == 'paid';
                  final isPartial = status == 'partial';
                  final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
                  final invPayments = (inv['payments'] as List?) ?? const [];
                  final paidSoFar = invPayments
                      .where((p) => (p as Map)['status'] == 'succeeded')
                      .fold<double>(
                        0,
                        (s, p) => s + ((p as Map)['amount'] as num).toDouble(),
                      );
                  final balanceDue = (amount - paidSoFar).clamp(0, amount);
                  final dateStr = isPaid
                      ? inv['paid_at'] as String?
                      : inv['due_at'] as String?;
                  return Container(
                    decoration: BoxDecoration(
                      border: e.key == list.length - 1
                          ? null
                          : const Border(
                              bottom: BorderSide(
                                color: AppTheme.border,
                                width: 0.7,
                              ),
                            ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                inv['description'] as String? ??
                                    'Membership payment',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                              ),
                              if (dateStr != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '${isPaid ? 'Paid' : 'Due'} ${formatDateFromString(dateStr)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.inkSoft,
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
                            Text(
                              isPartial
                                  ? '${formatCurrency(balanceDue)} due'
                                  : formatCurrency(amount),
                              style: AppTheme.numberStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (isPartial) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${formatCurrency(paidSoFar)} of ${formatCurrency(amount)} paid',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.inkSoft,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            if (isPaid)
                              StatusPill.active(label: 'Paid')
                            else if (isPartial)
                              StatusPill.warn(label: 'Partial')
                            else
                              StatusPill.warn(
                                label:
                                    status[0].toUpperCase() +
                                    status.substring(1),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
