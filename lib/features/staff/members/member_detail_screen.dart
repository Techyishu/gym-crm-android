import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/access/role_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/member_photo.dart';

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

String _detailPlanLabel(Map<String, dynamic> p) {
  final price = (p['price'] as num?)?.toStringAsFixed(0) ?? '0';
  final interval = p['billing_interval'] as String? ?? '';
  const short = {'monthly': 'mo', 'quarterly': 'qtr', 'biannual': '6mo', 'annual': 'yr'};
  final unit = interval == 'custom'
      ? '${p['billing_interval_months'] ?? ''}mo'
      : (short[interval] ?? interval);
  return '${p['name']} — ₹$price/$unit';
}

final _memberDetailProvider = FutureProvider.family<Member?, String>((ref, id) async {
  final data = await Supabase.instance.client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('id', id)
      .maybeSingle();
  return data != null ? Member.fromJson(data) : null;
});

final _memberCheckInsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  return await Supabase.instance.client
      .from('check_ins')
      .select('*')
      .eq('member_id', id)
      .order('checked_in_at', ascending: false)
      .limit(10);
});

final _memberInvoicesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  return await Supabase.instance.client
      .from('invoices')
      .select('id, amount, status, description, due_at, paid_at, created_at')
      .eq('member_id', id)
      .order('created_at', ascending: false)
      .limit(8);
});

final _memberBatchesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final data = await Supabase.instance.client
      .from('class_enrollments')
      .select('id, enrolled_at, classes(id, name, color, default_start_time, default_end_time)')
      .eq('member_id', id)
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
      appBar: AppBar(
        title: const Text('Member Detail'),
        leading: const BackButton(),
        actions: [
          if (canEdit)
            member.whenOrNull(
              data: (m) => m != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => _EditMemberSheet(member: m),
                          ).then((_) => ref.invalidate(_memberDetailProvider(memberId))),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.statusDanger),
                          onPressed: () => _confirmDeleteMember(context, ref, m),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ) ?? const SizedBox.shrink(),
        ],
      ),
      body: member.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (m) {
          if (m == null) return const Center(child: Text('Member not found'));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_memberDetailProvider(memberId)),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(context, m, canPii: canPii),
                  _MemberQuickActions(member: m, canPii: canPii),
                  const SizedBox(height: 16),
                  _buildMembershipCard(context, m),
                  const SizedBox(height: 12),
                  if (canPii) _buildContactInfo(context, m),
                  const SizedBox(height: 12),
                  _buildBatches(ref),
                  const SizedBox(height: 12),
                  _buildInvoices(ref),
                  const SizedBox(height: 12),
                  _buildCheckInHistory(ref),
                  const SizedBox(height: 12),
                  _buildWorkoutPlans(ref),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete member?'),
        content: Text(
          'Permanently delete ${m.fullName}? All their data (memberships, invoices, check-ins) will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.statusDanger)),
          ),
        ],
      ),
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

  Widget _buildHeader(BuildContext context, Member m, {required bool canPii}) {
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          // Large avatar
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F0F0),
              shape: BoxShape.circle,
            ),
            child: MemberPhoto(
              stored: m.avatarUrl,
              fallback: Center(
                child: Text(
                  initials(m.firstName, m.lastName),
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            m.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.ink),
            textAlign: TextAlign.center,
          ),
          if (canPii) ...[
            const SizedBox(height: 4),
            Text(
              m.email,
              style: const TextStyle(color: AppTheme.inkSoft, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 14),
          _StatusChip(status: m.status),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: AppTheme.inkHint),
              const SizedBox(width: 4),
              Text(
                'Joined ${formatDateFromString(m.joinedAt)}',
                style: const TextStyle(color: AppTheme.inkHint, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipCard(BuildContext context, Member m) {
    final ms = m.currentMembership;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Membership'),
              const SizedBox(height: 12),
              if (ms == null)
                const Text('No active membership', style: TextStyle(color: AppTheme.inkHint))
              else ...[
                _InfoRow(label: 'Plan', value: ms.plan?.name ?? '-'),
                _InfoRow(
                  label: 'Price',
                  value: ms.plan != null
                      ? '${formatCurrency(ms.plan!.price)} / ${ms.plan!.billingInterval}'
                      : '-',
                ),
                _InfoRow(label: 'Status', value: ms.status),
                _InfoRow(label: 'Started', value: formatDateFromString(ms.startsAt)),
                if (ms.endsAt != null) _InfoRow(label: 'Expires', value: formatDateFromString(ms.endsAt)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactInfo(BuildContext context, Member m) {
    final ec = m.emergencyContact;
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
              _InfoRow(label: 'Email', value: m.email),
              _InfoRow(label: 'Phone', value: m.phone ?? '-'),
              if (m.nextPaymentDate != null)
                _InfoRow(label: 'Next payment', value: formatDateFromString(m.nextPaymentDate)),
              if (m.notes != null && m.notes!.isNotEmpty)
                _InfoRow(label: 'Notes', value: m.notes!),
              if (ec != null && (ec['name'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: AppTheme.border),
                const SizedBox(height: 12),
                const Text(
                  'Emergency Contact',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
                ),
                const SizedBox(height: 10),
                _InfoRow(label: 'Name', value: ec['name'] as String? ?? '-'),
                if ((ec['phone'] as String? ?? '').isNotEmpty)
                  _InfoRow(label: 'Phone', value: ec['phone'] as String),
                if ((ec['relationship'] as String? ?? '').isNotEmpty)
                  _InfoRow(label: 'Relation', value: ec['relationship'] as String),
              ],
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

  Widget _buildInvoices(WidgetRef ref) {
    final invoices = ref.watch(_memberInvoicesProvider(memberId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Invoices'),
              const SizedBox(height: 12),
              invoices.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? const Text('No invoices yet', style: TextStyle(color: AppTheme.inkHint))
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
                        itemBuilder: (_, i) {
                          final inv = list[i];
                          final status = inv['status'] as String? ?? 'open';
                          final isPaid = status == 'paid';
                          final amount = (inv['amount'] as num?)?.toDouble() ?? 0;
                          final desc = inv['description'] as String?;
                          final dateStr = isPaid
                              ? inv['paid_at'] as String?
                              : inv['due_at'] as String?;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        desc ?? '—',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.ink,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (dateStr != null)
                                        Text(
                                          '${isPaid ? 'Paid' : 'Due'} ${formatDateFromString(dateStr)}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatCurrency(amount),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPaid ? AppTheme.statusActiveBg : AppTheme.statusWarnBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isPaid ? 'Paid' : status[0].toUpperCase() + status.substring(1),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isPaid ? AppTheme.statusActive : AppTheme.statusWarn,
                                        ),
                                      ),
                                    ),
                                  ],
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

  Widget _buildWorkoutPlans(WidgetRef ref) {
    final plans = ref.watch(_memberWorkoutPlansProvider(memberId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _ExpandableSection(
        title: 'Workout Plans',
        child: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('No workout plans yet.', style: TextStyle(color: AppTheme.inkHint)),
                )
              : Column(
                  children: list.map((plan) => _WorkoutPlanTile(plan: plan)).toList(),
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
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WhatsApp — ${m.firstName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink)),
              const SizedBox(height: 16),
              const Text('Template', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.inkHint, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: tpl,
                decoration: const InputDecoration(isDense: true),
                items: const [
                  DropdownMenuItem(value: 'custom',  child: Text('Custom message')),
                  DropdownMenuItem(value: 'expiry',  child: Text('Expiry reminder')),
                  DropdownMenuItem(value: 'payment', child: Text('Payment reminder')),
                  DropdownMenuItem(value: 'welcome', child: Text('Welcome')),
                  DropdownMenuItem(value: 'checkin', child: Text("Haven't seen you lately")),
                ],
                onChanged: (v) { if (v != null) setS(() { tpl = v; msg = defaultMsg(v); }); },
              ),
              const SizedBox(height: 12),
              const Text('Message', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.inkHint, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: msg,
                maxLines: 4,
                onChanged: (v) => msg = v,
                decoration: const InputDecoration(hintText: 'Type a message...'),
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
                label: const Text('Open WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
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

  Future<void> _cancelPlan() async {
    final ms = m.currentMembership;
    if (ms == null || ms.status != 'active') return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel membership?'),
        content: Text("Cancel ${m.firstName}'s current plan?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel plan')),
        ],
      ),
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select a plan',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ...plans.map((p) => ListTile(
                  title: Text(_detailPlanLabel(p)),
                  onTap: () => Navigator.pop(context, p['id'] as String),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() => _busy = true);
    try {
      // Cancel any existing active membership, then assign the new plan.
      await _client.from('memberships').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('member_id', m.id).eq('status', 'active');
      await _client.from('memberships').insert({
        'member_id': m.id,
        'plan_id': selected,
        'status': 'active',
        'starts_at': DateTime.now().toUtc().toIso8601String(),
        'ends_at': null,
      });
      ref.invalidate(_memberDetailProvider(m.id));
      _toast('Plan assigned');
    } catch (e) {
      debugPrint('[GymCRM] Assign plan error: $e');
      _toast('Failed to assign plan');
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
    if (!canPii && !canEdit) {
      return const SizedBox.shrink();
    }
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          if (showWhatsApp || showHold) ...[
            Row(
              children: [
                if (showWhatsApp)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _whatsapp,
                      icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF25D366)),
                      label: const Text('WhatsApp'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(color: Color(0xFF25D366)),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                if (showWhatsApp && showHold)
                  const SizedBox(width: 10),
                if (showHold)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _toggleHold,
                      icon: Icon(m.status == 'frozen' ? Icons.play_arrow : Icons.pause, size: 16),
                      label: Text(m.status == 'frozen' ? 'Remove hold' : 'Hold'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (canEdit) Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _managePlan,
                  icon: const Icon(Icons.credit_card, size: 16),
                  label: Text(hasActivePlan ? 'Change plan' : 'Assign plan'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ),
              if (hasActivePlan) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _cancelPlan,
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.statusDanger),
                    label: const Text('Cancel plan'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.statusDanger,
                      side: BorderSide(color: AppTheme.statusDanger.withValues(alpha: 0.4)),
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
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

class _ExpandableSection extends StatefulWidget {
  final String title;
  final Widget child;
  const _ExpandableSection({required this.title, required this.child});

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  ),
                  Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.inkHint, size: 20),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

// ── Workout Plan Tile ──────────────────────────────────────────────────────────

class _WorkoutPlanTile extends StatefulWidget {
  final Map<String, dynamic> plan;
  const _WorkoutPlanTile({required this.plan});

  @override
  State<_WorkoutPlanTile> createState() => _WorkoutPlanTileState();
}

class _WorkoutPlanTileState extends State<_WorkoutPlanTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.plan['name'] as String? ?? 'Plan';
    final type = (widget.plan['type'] as String? ?? 'weekly').toLowerCase();
    final rawDays = widget.plan['days'];
    final days = rawDays is List ? rawDays.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    final totalEx = days.fold<int>(0, (s, d) {
      final exList = d['exercises'];
      return s + (exList is List ? exList.length : 0);
    });

    final (typeBg, typeFg) = switch (type) {
      'daily'   => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'monthly' => (const Color(0xFFFFF8E1), const Color(0xFF8A6800)),
      _         => (const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: typeBg, borderRadius: BorderRadius.circular(20)),
                    child: Text(type.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: typeFg, letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.ink))),
                  Text('$totalEx ex', style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
                  const SizedBox(width: 6),
                  Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppTheme.inkHint),
                ],
              ),
            ),
          ),
          if (_expanded && days.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: days.where((d) {
                  final exList = d['exercises'];
                  return exList is List && exList.isNotEmpty;
                }).map((day) {
                  final label = day['label'] as String? ?? '';
                  final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.inkHint, letterSpacing: 0.8)),
                        const SizedBox(height: 6),
                        ...exercises.asMap().entries.map((e) {
                          final ex = e.value;
                          final parts = <String>[
                            if ((ex['sets'] as String? ?? '').isNotEmpty) '${ex['sets']} sets',
                            if ((ex['reps'] as String? ?? '').isNotEmpty) '${ex['reps']} reps',
                            if ((ex['weight'] as String? ?? '').isNotEmpty) ex['weight'] as String,
                          ];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${e.key + 1}. ', style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ex['name'] as String? ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.ink)),
                                      if (parts.isNotEmpty)
                                        Text(parts.join(' · '), style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
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
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────

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
  const _InfoRow({required this.label, required this.value});

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
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink, fontSize: 13)),
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
  late final TextEditingController _notesCtrl;
  late final TextEditingController _ecNameCtrl;
  late final TextEditingController _ecPhoneCtrl;
  late final TextEditingController _ecRelCtrl;
  late String _status;
  String? _nextPaymentDate;
  String? _joinedAt;
  File? _avatarFile;
  bool _loading = false;
  bool _showEmergency = false;

  // Billing day input
  late final TextEditingController _billingDayCtrl;
  bool _billingForceNextMonth = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _firstCtrl = TextEditingController(text: m.firstName);
    _emailCtrl = TextEditingController(text: m.email);
    _lastCtrl = TextEditingController(text: m.lastName);
    _phoneCtrl = TextEditingController(text: m.phone ?? '');
    _notesCtrl = TextEditingController(text: m.notes ?? '');
    _status = m.status;
    _nextPaymentDate = m.nextPaymentDate;
    _joinedAt = m.joinedAt;
    // Extract day from stored next_payment_date for the billing day input
    final existingDay = m.nextPaymentDate?.split('-').lastOrNull;
    _billingDayCtrl = TextEditingController(
      text: existingDay != null ? int.tryParse(existingDay)?.toString() ?? '' : '',
    );
    final ec = m.emergencyContact;
    _ecNameCtrl = TextEditingController(text: ec?['name'] as String? ?? '');
    _ecPhoneCtrl = TextEditingController(text: ec?['phone'] as String? ?? '');
    _ecRelCtrl = TextEditingController(text: ec?['relationship'] as String? ?? '');
    _showEmergency = ec != null && (ec['name'] as String? ?? '').isNotEmpty;
  }

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _notesCtrl.dispose(); _ecNameCtrl.dispose(); _ecPhoneCtrl.dispose();
    _ecRelCtrl.dispose(); _billingDayCtrl.dispose();
    super.dispose();
  }

  String? _computeNextPaymentDate() {
    final day = int.tryParse(_billingDayCtrl.text.trim());
    if (day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    final useNext = _billingForceNextMonth || day < now.day;
    var year = now.year;
    var month = now.month + (useNext ? 1 : 0);
    if (month > 12) { month = 1; year++; }
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final actual = day <= daysInMonth ? day : daysInMonth;
    return '$year-${month.toString().padLeft(2, '0')}-${actual.toString().padLeft(2, '0')}';
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
    final client = Supabase.instance.client;
    final ext = _avatarFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final filename = '$gymId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await _avatarFile!.readAsBytes();
    await client.storage
        .from('member-photos')
        .uploadBinary(filename, bytes, fileOptions: FileOptions(contentType: mime));
    // Private bucket: store the path; display resolves a signed URL.
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
    setState(() => _loading = true);
    try {
      Map<String, dynamic>? ec;
      if (_ecNameCtrl.text.trim().isNotEmpty) {
        ec = {
          'name': _ecNameCtrl.text.trim(),
          if (_ecPhoneCtrl.text.trim().isNotEmpty) 'phone': _ecPhoneCtrl.text.trim(),
          if (_ecRelCtrl.text.trim().isNotEmpty) 'relationship': _ecRelCtrl.text.trim(),
        };
      }

      final newAvatarUrl = await _uploadAvatar();

      await Supabase.instance.client.from('members').update({
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim() else 'phone': null,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': _status,
        if (_joinedAt != null) 'joined_at': _joinedAt,
        'next_payment_date': _computeNextPaymentDate(),
        'emergency_contact': ec,
        if (newAvatarUrl != null) 'avatar_url': newAvatarUrl,
      }).eq('id', widget.member.id);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Member',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
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
                        color: const Color(0xFFF0F0F0),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.border, width: 1.5),
                      ),
                      child: _avatarFile != null
                          ? ClipOval(child: Image.file(_avatarFile!, fit: BoxFit.cover))
                          : MemberPhoto(
                              stored: widget.member.avatarUrl,
                              fallback: Center(child: Text(initials(widget.member.firstName, widget.member.lastName),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: AppTheme.ink))),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(color: AppTheme.ink, shape: BoxShape.circle),
                        child: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _firstCtrl, decoration: const InputDecoration(labelText: 'First name'))),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(controller: _lastCtrl, decoration: const InputDecoration(labelText: 'Last name'))),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(isJoined: true),
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Joining date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                      child: Text(
                        _joinedAt != null ? formatDateFromString(_joinedAt) : 'Not set',
                        style: TextStyle(color: _joinedAt != null ? AppTheme.ink : AppTheme.inkHint),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BillingDayField(
                    controller: _billingDayCtrl,
                    forceNextMonth: _billingForceNextMonth,
                    onForceNextMonthChanged: (v) => setState(() => _billingForceNextMonth = v),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['active', 'frozen', 'expired', 'cancelled']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showEmergency = !_showEmergency),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(_showEmergency ? Icons.expand_less : Icons.expand_more, color: AppTheme.ink, size: 20),
                    const SizedBox(width: 6),
                    const Text('Emergency Contact', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  ],
                ),
              ),
            ),
            if (_showEmergency) ...[
              const SizedBox(height: 8),
              TextFormField(controller: _ecNameCtrl, decoration: const InputDecoration(labelText: 'Contact name')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _ecPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _ecRelCtrl, decoration: const InputDecoration(labelText: 'Relationship'))),
                ],
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Billing Day Field ─────────────────────────────────────────────────────────

class _BillingDayField extends StatelessWidget {
  final TextEditingController controller;
  final bool forceNextMonth;
  final ValueChanged<bool> onForceNextMonthChanged;
  final ValueChanged<String> onChanged;

  const _BillingDayField({
    required this.controller,
    required this.forceNextMonth,
    required this.onForceNextMonthChanged,
    required this.onChanged,
  });

  String? _computedDate() {
    final day = int.tryParse(controller.text.trim());
    if (day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    final useNext = forceNextMonth || day < now.day;
    var year = now.year;
    var month = now.month + (useNext ? 1 : 0);
    if (month > 12) { month = 1; year++; }
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final actual = day <= daysInMonth ? day : daysInMonth;
    return '$year-${month.toString().padLeft(2, '0')}-${actual.toString().padLeft(2, '0')}';
  }

  String _monthName(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[d.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = int.tryParse(controller.text.trim());
    final validDay = day != null && day >= 1 && day <= 31;
    final todayDay = DateTime.now().day;
    final dayValue = day ?? 0;
    final showToggle = validDay && dayValue > todayDay;
    final computed = _computedDate();

    final now = DateTime.now();
    var nm = now.month + 1; var ny = now.year;
    if (nm > 12) { nm = 1; ny++; }
    final nextMonthLabel = _monthName(DateTime(ny, nm));
    final thisMonthLabel = _monthName(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 2,
          decoration: const InputDecoration(
            labelText: 'Billing day',
            hintText: 'e.g. 15',
            counterText: '',
          ),
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, color: AppTheme.ink),
        ),
        if (controller.text.isNotEmpty && !validDay)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text('Enter a day 1–31', style: TextStyle(fontSize: 11, color: AppTheme.statusDanger)),
          ),
        if (validDay && computed != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Next due: ${formatDateFromString(computed)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
              if (showToggle) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onForceNextMonthChanged(!forceNextMonth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Text(
                      forceNextMonth
                          ? '← Back to $thisMonthLabel'
                          : '→ Start from $nextMonthLabel',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
