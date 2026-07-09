import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/access/role_access.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/staff/workout/workout_plan_sheet.dart';
import '../../../features/staff/diet/diet_plan_sheet.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/member_photo.dart';
import '../../../shared/widgets/redesign.dart';
import 'member_plan_viewer.dart';

// Active membership plans for the current gym (for assign/change actions).
final _detailPlansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
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

final _memberDetailProvider = FutureProvider.family<Member?, String>((ref, id) async {
  final gymId = await ref.read(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('id', id)
      .eq('gym_id', gymId)
      .maybeSingle();
  return data != null ? Member.fromJson(data) : null;
});

final _memberCheckInsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final gymId = await ref.read(gymIdProvider.future);
  return await Supabase.instance.client
      .from('check_ins')
      .select('*')
      .eq('member_id', id)
      .eq('gym_id', gymId)
      .order('checked_in_at', ascending: false)
      .limit(10);
});

final _memberInvoicesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final gymId = await ref.read(gymIdProvider.future);
  return await Supabase.instance.client
      .from('invoices')
      .select('id, amount, status, description, due_at, paid_at, created_at')
      .eq('member_id', id)
      .eq('gym_id', gymId)
      .order('created_at', ascending: false)
      .limit(8);
});

final _memberBatchesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final gymId = await ref.read(gymIdProvider.future);
  final data = await Supabase.instance.client
      .from('class_enrollments')
      .select('id, enrolled_at, classes(id, name, color, default_start_time, default_end_time)')
      .eq('member_id', id)
      .eq('gym_id', gymId)
      .order('enrolled_at', ascending: false);
  return (data as List).cast<Map<String, dynamic>>();
});

final _memberWorkoutPlansProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
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

final _memberDietPlansProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
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

class MemberDetailScreen extends ConsumerWidget {
  final String memberId;
  const MemberDetailScreen({super.key, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(_memberDetailProvider(memberId));
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canPii = RoleAccess.canSeeMemberPii(role);
    final canEdit = RoleAccess.canEditMembers(role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: member.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (m) {
          if (m == null) return const Center(child: Text('Member not found'));
          return RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async => ref.invalidate(_memberDetailProvider(memberId)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(context, ref, m, canPii: canPii, canEdit: canEdit),
                  const SizedBox(height: 16),
                  _buildMembershipCard(context, m),
                  const SizedBox(height: 12),
                  _buildStatTiles(ref),
                  const SizedBox(height: 12),
                  _buildQuickLinks(context, ref, m, role),
                  const SizedBox(height: 12),
                  _MemberQuickActions(member: m, canPii: canPii),
                  const SizedBox(height: 12),
                  if (canPii) _buildContactInfo(context, m),
                  const SizedBox(height: 12),
                  _buildBatches(ref),
                  const SizedBox(height: 12),
                  _buildCheckInHistory(ref),
                  const SizedBox(height: 12),
                  _buildMemberId(context, m),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteMember(BuildContext context, WidgetRef ref, Member m) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete member?',
      body: 'Permanently delete ${m.fullName}? All their data (memberships, invoices, check-ins) will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.from('members').delete().eq('id', m.id);
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

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _whatsApp(Member m) async {
    final phone = m.phone;
    if (phone == null || phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('https://wa.me/91$cleaned');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, Member m,
      {required bool canPii, required bool canEdit}) {
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
                icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.onDark),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 22, color: AppTheme.onDark),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined, color: AppTheme.ink),
                          title: const Text('Edit member'),
                          onTap: () {
                            Navigator.pop(ctx);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (_) => _EditMemberSheet(member: m),
                            ).then((_) => ref.invalidate(_memberDetailProvider(memberId)));
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: AppTheme.statusDanger),
                          title: const Text('Delete member', style: TextStyle(color: AppTheme.statusDanger)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _confirmDeleteMember(context, ref, m);
                          },
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
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
                      style: const TextStyle(color: AppTheme.mintOnDark, fontWeight: FontWeight.w800, fontSize: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fullName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppTheme.onDark, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (hasPhone) m.phone!,
                        'Member since ${formatDateFromString(m.joinedAt)}',
                      ].join(' · '),
                      maxLines: 2,
                      style: const TextStyle(color: AppTheme.onDarkSoft, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasPhone) ...[
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _call(m.phone),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(color: AppTheme.darkCard2, borderRadius: BorderRadius.circular(14)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.call_outlined, size: 17, color: AppTheme.onDark),
                      SizedBox(width: 8),
                      Text('Call', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onDark)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _whatsApp(m),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(color: const Color(0xFF2E7D4F), borderRadius: BorderRadius.circular(14)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.chat_bubble_outline, size: 17, color: Colors.white),
                      SizedBox(width: 8),
                      Text('WhatsApp', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
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
      final dt = DateTime.tryParse(list.first['checked_in_at'] as String? ?? '');
      if (dt != null) {
        final days = now.difference(dt).inDays;
        lastVisit = days == 0 ? 'Today' : days == 1 ? '1d ago' : '${days}d ago';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: StatTileLight(label: 'Check-ins / month', value: '$monthCount')),
        const SizedBox(width: 10),
        Expanded(child: StatTileLight(label: 'Last visit', value: lastVisit)),
      ]),
    );
  }

  // ── Quick links: Workout plan · Diet plan · Payment history ────────────────

  Widget _buildQuickLinks(BuildContext context, WidgetRef ref, Member m, String? role) {
    final workoutPlans = ref.watch(_memberWorkoutPlansProvider(memberId)).valueOrNull ?? const [];
    final dietPlans = ref.watch(_memberDietPlansProvider(memberId)).valueOrNull ?? const [];
    final invoices = ref.watch(_memberInvoicesProvider(memberId)).valueOrNull ?? const [];
    final canWorkout = RoleAccess.canManageWorkoutPlans(role);
    final canDiet = RoleAccess.canManageDietPlans(role);

    String workoutSummary() {
      if (workoutPlans.isEmpty) return canWorkout ? 'Add plan' : '—';
      return workoutPlans.first['name'] as String? ?? 'View';
    }

    String dietSummary() {
      if (dietPlans.isEmpty) return canDiet ? 'Add plan' : '—';
      final kcal = dietPlans.first['calories'] as int?;
      return kcal != null ? '$kcal kcal' : (dietPlans.first['name'] as String? ?? 'View');
    }

    Future<void> openWorkout() async {
      if (workoutPlans.isEmpty) {
        if (!canWorkout) return;
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => WorkoutPlanSheet(memberId: memberId, memberName: m.fullName),
        );
        if (saved == true) ref.invalidate(_memberWorkoutPlansProvider(memberId));
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => WorkoutPlanViewerPage(
          plan: workoutPlans.first,
          memberId: memberId,
          memberName: m.fullName,
          canManage: canWorkout,
        )),
      );
      if (changed == true) ref.invalidate(_memberWorkoutPlansProvider(memberId));
    }

    Future<void> openDiet() async {
      if (dietPlans.isEmpty) {
        if (!canDiet) return;
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => DietPlanSheet(memberId: memberId, memberName: m.fullName),
        );
        if (saved == true) ref.invalidate(_memberDietPlansProvider(memberId));
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => DietPlanViewerPage(
          plan: dietPlans.first,
          memberId: memberId,
          memberName: m.fullName,
          canManage: canDiet,
        )),
      );
      if (changed == true) ref.invalidate(_memberDietPlansProvider(memberId));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CardList(children: [
        _QuickLinkRow(
          icon: Icons.fitness_center_outlined,
          iconBg: AppTheme.accentSoft,
          iconColor: AppTheme.accent,
          label: 'Workout plan',
          summary: workoutSummary(),
          onTap: openWorkout,
        ),
        _QuickLinkRow(
          icon: Icons.restaurant_menu_outlined,
          iconBg: AppTheme.statusActiveBg,
          iconColor: AppTheme.statusActive,
          label: 'Diet plan',
          summary: dietSummary(),
          onTap: openDiet,
        ),
        _QuickLinkRow(
          icon: Icons.receipt_long_outlined,
          iconBg: AppTheme.statusNeutralBg,
          iconColor: AppTheme.statusNeutral,
          label: 'Payment history',
          summary: '${invoices.length} payment${invoices.length == 1 ? '' : 's'}',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _PaymentHistoryPage(
              memberId: memberId,
              memberName: m.fullName,
            )),
          ),
        ),
      ]),
    );
  }

  Widget _buildMembershipCard(BuildContext context, Member m) {
    final ms = m.currentMembership;
    final npd = m.nextPaymentDate != null ? DateTime.tryParse(m.nextPaymentDate!) : null;
    final started = ms != null ? DateTime.tryParse(ms.startsAt) : null;
    int? daysLeft;
    double? progress;
    if (npd != null) {
      daysLeft = npd.difference(DateTime.now()).inDays;
      if (started != null && npd.isAfter(started)) {
        final total = npd.difference(started).inDays;
        progress = total > 0 ? ((total - daysLeft) / total).clamp(0.0, 1.0) : null;
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
              const Text('Current plan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(planTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: m.status),
              ]),
              if (ms?.hasDiscount ?? false) ...[
                const SizedBox(height: 4),
                Text('− ${formatCurrency(ms!.discountAmount)} per invoice',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.statusActive)),
              ],
              if (progress != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.surface2,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.statusActive),
                  ),
                ),
              ],
              if (npd != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Text('Renews ${formatDateFromString(m.nextPaymentDate)}',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
                  const Spacer(),
                  Text(
                    daysLeft != null && daysLeft >= 0 ? '$daysLeft days left'
                        : '${daysLeft!.abs()} days overdue',
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: daysLeft >= 0 ? AppTheme.ink : AppTheme.statusDanger,
                      fontFeatures: AppTheme.tabularFigures,
                    ),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactInfo(BuildContext context, Member m) {
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
            ],
          ),
        ),
      ),
    );
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
                    ? const Text('Not enrolled in any batch.', style: TextStyle(color: AppTheme.inkHint))
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final cls = list[i]['classes'] as Map<String, dynamic>?;
                          if (cls == null) return const SizedBox.shrink();
                          final color = _parseColor(cls['color'] as String?);
                          final startTime = cls['default_start_time'] as String?;
                          final endTime = cls['default_end_time'] as String?;
                          final timeStr = (startTime != null && endTime != null) ? '$startTime–$endTime' : null;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: color, width: 3)),
                              color: color.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cls['name'] as String? ?? '—',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink)),
                                if (timeStr != null)
                                  Text(timeStr, style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
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
                    ? const Text('No check-ins yet', style: TextStyle(color: AppTheme.inkHint))
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
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
                                  child: const Icon(Icons.check, size: 16, color: AppTheme.statusActive),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    formatDateTimeFromString(ci['checked_in_at'] as String?),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.ink),
                                  ),
                                ),
                                // Method badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.statusNeutralBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    method.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.statusNeutral),
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
                  const Text('MEMBER ID',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.inkHint, letterSpacing: 1.0)),
                  const SizedBox(height: 4),
                  Text(m.id,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.inkSoft),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18, color: AppTheme.inkHint),
              onPressed: () {
                // Copy to clipboard
                final data = ClipboardData(text: m.id);
                Clipboard.setData(data);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Member ID copied'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
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
  ConsumerState<_MemberQuickActions> createState() => _MemberQuickActionsState();
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
      'expiry'  => 'Hi ${m.firstName}! Your membership is expiring soon. Please renew to keep access. 💪',
      'payment' => 'Hi ${m.firstName}, you have a pending payment. Please clear it at your earliest. Thank you!',
      'welcome' => 'Welcome ${m.firstName}! 🎉 Excited to have you. See you at the gym soon!',
      'checkin' => 'Hi ${m.firstName}! We miss you. Come back and keep your goals on track! 💪',
      _         => 'Hi ${m.firstName}, ',
    };

    await showModalBottomSheet(
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
          final tplIndex = templates.indexWhere((t) => t.$1 == tpl).clamp(0, templates.length - 1);
          return Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.chat_bubble, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text('Send WhatsApp',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.ink)),
                ]),
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
                      onTap: () => setS(() { tpl = templates[i].$1; msg = defaultMsg(templates[i].$1); }),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: msg,
                  maxLines: 4,
                  onChanged: (v) => msg = v,
                  decoration: const InputDecoration(hintText: 'Type a message…'),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final clean = m.phone!.replaceAll(RegExp(r'\D'), '');
                    final number = clean.startsWith('91') ? clean : '91$clean';
                    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(msg)}');
                    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                      _toast('Could not open WhatsApp');
                    }
                  },
                  icon: const Icon(Icons.send_outlined, size: 16),
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
      await _client.from('members').update({'status': newStatus}).eq('id', m.id);
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
      final session = auth.currentSession ?? (await auth.refreshSession()).session;
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
      body: "${m.firstName}'s current plan will be cancelled. This can't be undone.",
      cancelLabel: 'Keep plan',
      confirmLabel: 'Cancel it',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _client.from('memberships').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', ms.id);
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
    final plans = await ref.read(_detailPlansProvider.future);
    if (!mounted) return;
    if (plans.isEmpty) {
      _toast('No active plans. Create one in Billing first.');
      return;
    }
    final currentPlanId = m.currentMembership?.plan?.id;
    var picked = currentPlanId ?? (plans.isNotEmpty ? plans.first['id'] as String : null);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.accentSoft : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected ? AppTheme.accent : AppTheme.border, width: selected ? 1.5 : 1),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text(p['name'] as String? ?? '',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                          ),
                          Text(formatCurrency((p['price'] as num?)?.toDouble() ?? 0),
                            style: AppTheme.numberStyle(fontSize: 14.5)),
                        ]),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: picked == null ? null : () => Navigator.pop(context, picked),
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
    final discount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DiscountSheet(
        title: 'Recurring Discount',
        helperText: 'Fixed amount deducted from every auto-generated invoice for this member.',
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

      // Cancel any existing active membership, then assign the new plan.
      await _client.from('memberships').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('member_id', m.id).eq('status', 'active');
      await _client.from('memberships').insert({
        'member_id': m.id,
        'plan_id': selected,
        'status': 'active',
        'starts_at': startsAt.toIso8601String(),
        'ends_at': null,
        'discount_amount': discount ?? 0.0,
      });
      // Activate the member if they were expired or cancelled.
      if (m.status == 'expired' || m.status == 'cancelled') {
        await _client.from('members').update({'status': 'active'}).eq('id', m.id);
      }
      ref.invalidate(_memberDetailProvider(m.id));
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
    final newDiscount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DiscountSheet(
        title: 'Edit Recurring Discount',
        helperText: 'Fixed amount deducted from every auto-generated invoice. Set to 0 to remove.',
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
    final canEdit = widget.canPii; // same gate: manager+ only
    final showWhatsApp = canPii && m.phone != null && m.phone!.isNotEmpty;
    final showHold = canEdit && (m.status == 'active' || m.status == 'frozen');
    final showInvite = canEdit && m.email.isNotEmpty && m.userId == null;
    if (!canPii && !canEdit) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[
      if (showWhatsApp)
        _ActionRow(
          icon: Icons.chat_bubble_outline,
          iconBg: const Color(0xFFDDEFE2),
          iconColor: const Color(0xFF25D366),
          label: 'WhatsApp',
          onTap: _busy ? null : _whatsapp,
        ),
      if (showHold)
        _ActionRow(
          icon: m.status == 'frozen' ? Icons.play_arrow : Icons.pause,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: m.status == 'frozen' ? 'Remove hold' : 'Hold membership',
          onTap: _busy ? null : _toggleHold,
        ),
      if (canEdit)
        _ActionRow(
          icon: Icons.credit_card,
          iconBg: AppTheme.accentSoft,
          iconColor: AppTheme.accent,
          label: hasActivePlan ? 'Change plan' : 'Assign plan',
          onTap: _busy ? null : _managePlan,
        ),
      if (canEdit && hasActivePlan)
        _ActionRow(
          icon: Icons.edit_outlined,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: m.currentMembership?.hasDiscount == true
              ? 'Edit recurring discount (${formatCurrency(m.currentMembership!.discountAmount)} off)'
              : 'Add recurring discount',
          onTap: _busy ? null : _editDiscount,
        ),
      if (showInvite)
        _ActionRow(
          icon: Icons.mail_outline,
          iconBg: AppTheme.surface2,
          iconColor: AppTheme.inkSoft,
          label: 'Send portal invite',
          onTap: _busy ? null : _sendInvite,
        ),
      if (canEdit && hasActivePlan)
        _ActionRow(
          icon: Icons.delete_outline,
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
            left: 16, right: 16, top: 20,
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(hintText: '0', prefixText: '₹ '),
              ),
              if (discount > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: AppTheme.cardDecoration(),
                  child: Row(children: [
                    const Text('Discount applied', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                    const Spacer(),
                    Text('− ${formatCurrency(discount)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.statusActive)),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onConfirm,
                child: Text(confirmLabel),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onSkip,
                  child: Text(skipLabel, style: const TextStyle(color: AppTheme.inkSoft)),
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
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  static (Color, Color) _statusColors(String status) => switch (status) {
        'active'    => (AppTheme.statusActiveBg, AppTheme.statusActive),
        'frozen'    => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
        'expired'   => (AppTheme.statusWarnBg, AppTheme.statusWarn),
        'cancelled' => (AppTheme.statusDangerBg, AppTheme.statusDanger),
        _           => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
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
            child: Text(label, style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor ?? AppTheme.ink, fontSize: 13)),
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
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _customIdCtrl;
  late final TextEditingController _biometricIdCtrl;
  late final TextEditingController _notesCtrl;
  late String _status;
  String? _nextPaymentDate;
  int _billingIntervalMonths = 1;
  String? _joinedAt;
  File? _avatarFile;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _firstCtrl = TextEditingController(text: m.firstName);
    _emailCtrl = TextEditingController(text: m.email);
    _lastCtrl = TextEditingController(text: m.lastName);
    _phoneCtrl = TextEditingController(text: m.phone ?? '');
    _customIdCtrl = TextEditingController(text: m.customId ?? '');
    _biometricIdCtrl = TextEditingController(text: m.biometricId ?? '');
    _notesCtrl = TextEditingController(text: m.notes ?? '');
    _status = m.status;
    _nextPaymentDate = m.nextPaymentDate;
    _billingIntervalMonths = m.billingIntervalMonths;
    _joinedAt = m.joinedAt;
  }

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _customIdCtrl.dispose(); _biometricIdCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  String _intervalLabel(int months) {
    if (months == 1) return '1 Month';
    if (months == 12) return '1 Year';
    return '$months Months';
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
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
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (picked != null && mounted) setState(() => _avatarFile = File(picked.path));
  }

  Future<String?> _uploadAvatar() async {
    if (_avatarFile == null) return null;
    final gymId = widget.member.gymId;
    final ext = _avatarFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    // Stable per-member path: re-uploads overwrite the same object instead of
    // accumulating a new orphaned file (and egress cost) on every edit.
    final filename = '$gymId/${widget.member.id}.$ext';
    final bytes = await _avatarFile!.readAsBytes();
    await MemberPhotoService.upload(path: filename, bytes: bytes, contentType: mime);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid email address')));
      return;
    }
    if (phone.isNotEmpty && !isValidIndianMobile(phone)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid 10-digit mobile number')));
      return;
    }
    setState(() => _loading = true);
    try {
      final newAvatarUrl = await _uploadAvatar();

      await Supabase.instance.client.from('members').update({
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim() else 'phone': null,
        'custom_id': _customIdCtrl.text.trim().isEmpty ? null : _customIdCtrl.text.trim(),
        'biometric_id': _biometricIdCtrl.text.trim().isEmpty ? null : _biometricIdCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': _status,
        if (_joinedAt != null) 'joined_at': _joinedAt,
        'next_payment_date': _nextPaymentDate,
        'billing_interval_months': _billingIntervalMonths,
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
      }).eq('id', widget.member.id);

      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.code == '23505'
            ? 'A member with this ID already exists.'
            : 'Failed to save. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to save. Please try again.')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Edit member'),
            const SizedBox(height: 12),
            // Photo picker
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.surface2,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _avatarFile != null
                          ? Image.file(_avatarFile!, fit: BoxFit.cover)
                          : MemberPhoto(
                              stored: widget.member.avatarUrl,
                              fallback: Center(child: Text(initials(widget.member.firstName, widget.member.lastName),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: AppTheme.ink))),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('First name'),
                    TextFormField(controller: _firstCtrl),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Last name'),
                    TextFormField(controller: _lastCtrl),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const FieldLabel('Email (optional)'),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            if (_emailCtrl.text.trim().isEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                '⚠ Without email, the member portal won\'t be available and check-ins must be done manually.',
                style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
              ),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Phone (optional)'),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Member ID (optional)'),
            TextFormField(controller: _customIdCtrl, maxLength: 50, decoration: const InputDecoration(hintText: 'e.g. GYM-001', counterText: '')),
            // BIOMETRIC HIDDEN — re-enable when ready to launch
            // const SizedBox(height: 12),
            // TextFormField(
            //   controller: _biometricIdCtrl,
            //   maxLength: 20,
            //   keyboardType: TextInputType.number,
            //   decoration: const InputDecoration(
            //     labelText: 'Biometric Device ID (optional)',
            //     hintText: 'e.g. 001',
            //     counterText: '',
            //     prefixIcon: Icon(Icons.fingerprint_outlined),
            //     helperText: 'Employee number enrolled on fingerprint machine',
            //   ),
            // ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Joining date'),
                    InkWell(
                      onTap: () => _pickDate(isJoined: true),
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                        child: Text(
                          _joinedAt != null ? formatDateFromString(_joinedAt) : 'Not set',
                          style: TextStyle(color: _joinedAt != null ? AppTheme.ink : AppTheme.inkHint),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Next payment'),
                    InkWell(
                      onTap: () => _pickDate(isJoined: false),
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                        child: Text(
                          _nextPaymentDate != null ? formatDateFromString(_nextPaymentDate) : 'Not set',
                          style: TextStyle(color: _nextPaymentDate != null ? AppTheme.ink : AppTheme.inkHint),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
            if (_nextPaymentDate != null) ...[
              const SizedBox(height: 14),
              const FieldLabel('Payment interval'),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final months = [1, 2, 3, 6, 12][i];
                    return PillChip(
                      label: _intervalLabel(months),
                      selected: _billingIntervalMonths == months,
                      onTap: () => setState(() => _billingIntervalMonths = months),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Invoices will be generated every ${_intervalLabel(_billingIntervalMonths).toLowerCase()} starting ${formatDateFromString(_nextPaymentDate)}.',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Status'),
            DropdownButtonFormField<String>(
              value: _status,
              items: ['active', 'frozen', 'expired', 'cancelled']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Notes'),
            TextFormField(controller: _notesCtrl, maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
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
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onTap == null ? AppTheme.inkHint : (labelColor ?? AppTheme.ink),
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: AppTheme.inkHint),
        ]),
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
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(summary,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkHint),
        ]),
      ),
    );
  }
}

// ── Payment history page ──────────────────────────────────────────────────────

class _PaymentHistoryPage extends ConsumerWidget {
  final String memberId;
  final String memberName;
  const _PaymentHistoryPage({required this.memberId, required this.memberName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(_memberInvoicesProvider(memberId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(memberName, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No payments yet',
              style: TextStyle(color: AppTheme.inkHint)));
          }
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  children: list.asMap().entries.map((e) {
                    final inv = e.value;
                    final status = inv['status'] as String? ?? 'open';
                    final isPaid = status == 'paid';
                    final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
                    final dateStr = isPaid
                        ? inv['paid_at'] as String?
                        : inv['due_at'] as String?;
                    return Container(
                      decoration: BoxDecoration(
                        border: e.key == list.length - 1
                            ? null
                            : const Border(bottom: BorderSide(color: AppTheme.border, width: 0.7)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              inv['description'] as String? ?? 'Membership payment',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                            if (dateStr != null) ...[
                              const SizedBox(height: 2),
                              Text('${isPaid ? 'Paid' : 'Due'} ${formatDateFromString(dateStr)}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                            ],
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(formatCurrency(amount),
                            style: AppTheme.numberStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          if (isPaid)
                            StatusPill.active(label: 'Paid')
                          else
                            StatusPill.warn(label: status[0].toUpperCase() + status.substring(1)),
                        ]),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
