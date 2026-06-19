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
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
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
              if (m.nextPaymentDate != null)
                _InfoRow(label: 'Next payment', value: formatDateFromString(m.nextPaymentDate)),
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
          if (showInvite) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _sendInvite,
                icon: const Icon(Icons.mail_outline, size: 16),
                label: const Text('Send portal invite'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
          ],
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
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              onChanged: (_) => setState(() {}),
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
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            if (_phoneCtrl.text.trim().isEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                '⚠ Without phone number, SMS reminders won\'t be sent.',
                style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _customIdCtrl, maxLength: 50, decoration: const InputDecoration(labelText: 'Member ID (optional)', hintText: 'e.g. GYM-001', counterText: '')),
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
                  child: InkWell(
                    onTap: () => _pickDate(isJoined: false),
                    borderRadius: BorderRadius.circular(10),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Next payment date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                      child: Text(
                        _nextPaymentDate != null ? formatDateFromString(_nextPaymentDate) : 'Not set',
                        style: TextStyle(color: _nextPaymentDate != null ? AppTheme.ink : AppTheme.inkHint),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_nextPaymentDate != null) ...[
              const SizedBox(height: 12),
              const Text('Payment Interval', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkHint, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [1, 2, 3, 6, 12].map((m) {
                  final selected = _billingIntervalMonths == m;
                  return GestureDetector(
                    onTap: () => setState(() => _billingIntervalMonths = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.ink : Colors.transparent,
                        border: Border.all(color: selected ? AppTheme.ink : AppTheme.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _intervalLabel(m),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                'Invoices will be generated every ${_intervalLabel(_billingIntervalMonths).toLowerCase()} starting ${formatDateFromString(_nextPaymentDate)}.',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
            ],
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

