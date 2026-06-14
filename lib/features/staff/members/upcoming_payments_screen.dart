import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/member_photo.dart';
import '../../auth/providers/auth_provider.dart';

final _overdueProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, gymId) async {
  final today = DateTime.now();
  final todayStr =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final data = await Supabase.instance.client
      .from('members')
      .select('id, first_name, last_name, avatar_url, next_payment_date, status, phone, email')
      .eq('gym_id', gymId)
      .lte('next_payment_date', todayStr)
      .not('status', 'eq', 'cancelled')
      .order('next_payment_date', ascending: true);
  return (data as List).cast<Map<String, dynamic>>();
});

final _upcomingProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, gymId) async {
  final today = DateTime.now();
  final tomorrow = today.add(const Duration(days: 1));
  final tomorrowStr =
      '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
  final end = today.add(const Duration(days: 14));
  final endStr =
      '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
  final data = await Supabase.instance.client
      .from('members')
      .select('id, first_name, last_name, avatar_url, next_payment_date, status, phone, email')
      .eq('gym_id', gymId)
      .gte('next_payment_date', tomorrowStr)
      .lte('next_payment_date', endStr)
      .not('status', 'eq', 'cancelled')
      .order('next_payment_date', ascending: true);
  return (data as List).cast<Map<String, dynamic>>();
});

class UpcomingPaymentsScreen extends ConsumerStatefulWidget {
  const UpcomingPaymentsScreen({super.key});

  @override
  ConsumerState<UpcomingPaymentsScreen> createState() =>
      _UpcomingPaymentsScreenState();
}

class _UpcomingPaymentsScreenState
    extends ConsumerState<UpcomingPaymentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  // bucket filter for upcoming tab: 3, 7, 14 days (null = all)
  int? _bucketFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(gymIdProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Upcoming Payments'),
        leading: const BackButton(),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overdue'),
            Tab(text: 'Next 14 Days'),
          ],
        ),
      ),
      body: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (gymId) => TabBarView(
          controller: _tabs,
          children: [
            _OverdueTab(gymId: gymId),
            _UpcomingTab(
              gymId: gymId,
              bucketFilter: _bucketFilter,
              onBucketChange: (v) => setState(() => _bucketFilter = v),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overdue Tab ────────────────────────────────────────────────────────────────

class _OverdueTab extends ConsumerWidget {
  final String gymId;
  const _OverdueTab({required this.gymId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_overdueProvider(gymId));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (members) {
        if (members.isEmpty) {
          return const _EmptyState(
            icon: Icons.check_circle_outline,
            label: 'No overdue payments',
            sub: 'All members are up to date.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_overdueProvider(gymId)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _OverdueCard(member: members[i], gymId: gymId),
          ),
        );
      },
    );
  }
}

class _OverdueCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final String gymId;
  const _OverdueCard({required this.member, required this.gymId});

  @override
  Widget build(BuildContext context) {
    final dateStr = member['next_payment_date'] as String?;
    final isFrozen = (member['status'] as String?) == 'frozen';

    int daysOverdue = 0;
    if (dateStr != null) {
      final due = DateTime.tryParse(dateStr);
      if (due != null) {
        final today = DateTime.now();
        daysOverdue = DateTime(today.year, today.month, today.day)
            .difference(DateTime(due.year, due.month, due.day))
            .inDays;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isFrozen ? const Color(0xFFFFF0F0) : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFrozen
              ? const Color(0xFFFFCDD2)
              : AppTheme.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _Avatar(member: member),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _name(member),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (isFrozen)
                      _Badge(label: 'Hold', bg: const Color(0xFFFFCDD2), fg: const Color(0xFFB71C1C)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  daysOverdue == 0
                      ? 'Due today'
                      : '$daysOverdue day${daysOverdue == 1 ? '' : 's'} overdue',
                  style: TextStyle(
                    fontSize: 12,
                    color: daysOverdue == 0
                        ? AppTheme.statusWarn
                        : AppTheme.statusDanger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (dateStr != null)
                  Text(
                    formatDateFromString(dateStr),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkHint,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((member['phone'] as String? ?? '').isNotEmpty)
                _WhatsAppButton(member: member),
              const SizedBox(height: 6),
              _CollectButton(
                memberId: member['id'] as String,
                memberName: _name(member),
                gymId: gymId,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Upcoming Tab ───────────────────────────────────────────────────────────────

class _UpcomingTab extends ConsumerWidget {
  final String gymId;
  final int? bucketFilter;
  final ValueChanged<int?> onBucketChange;
  const _UpcomingTab({
    required this.gymId,
    required this.bucketFilter,
    required this.onBucketChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_upcomingProvider(gymId));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (all) {
        final filtered = bucketFilter == null
            ? all
            : all.where((m) {
                final days = _daysUntil(m['next_payment_date'] as String?);
                if (bucketFilter == 3) return days <= 3;
                if (bucketFilter == 7) return days > 3 && days <= 7;
                return days > 7 && days <= 14;
              }).toList();

        return Column(
          children: [
            // Bucket filter chips
            Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _FilterChip(label: 'All', selected: bucketFilter == null, onTap: () => onBucketChange(null)),
                  const SizedBox(width: 8),
                  _FilterChip(label: '≤3 days', selected: bucketFilter == 3, color: AppTheme.statusDanger, onTap: () => onBucketChange(bucketFilter == 3 ? null : 3)),
                  const SizedBox(width: 8),
                  _FilterChip(label: '4–7 days', selected: bucketFilter == 7, color: const Color(0xFFF97316), onTap: () => onBucketChange(bucketFilter == 7 ? null : 7)),
                  const SizedBox(width: 8),
                  _FilterChip(label: '8–14 days', selected: bucketFilter == 14, color: const Color(0xFFEAB308), onTap: () => onBucketChange(bucketFilter == 14 ? null : 14)),
                ],
              ),
            ),
            if (filtered.isEmpty)
              const Expanded(
                child: _EmptyState(
                  icon: Icons.calendar_today_outlined,
                  label: 'No upcoming payments',
                  sub: 'No members due in this window.',
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_upcomingProvider(gymId)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _UpcomingCard(member: filtered[i], gymId: gymId),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static int _daysUntil(String? dateStr) {
    if (dateStr == null) return 999;
    final due = DateTime.tryParse(dateStr);
    if (due == null) return 999;
    final today = DateTime.now();
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }
}

class _UpcomingCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final String gymId;
  const _UpcomingCard({required this.member, required this.gymId});

  @override
  Widget build(BuildContext context) {
    final dateStr = member['next_payment_date'] as String?;
    int days = 0;
    if (dateStr != null) {
      final due = DateTime.tryParse(dateStr);
      if (due != null) {
        final today = DateTime.now();
        days = DateTime(due.year, due.month, due.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays;
      }
    }

    final Color daysColor = days <= 3
        ? AppTheme.statusDanger
        : days <= 7
            ? const Color(0xFFF97316)
            : const Color(0xFFEAB308);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _Avatar(member: member),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name(member),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Due in $days day${days == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: daysColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (dateStr != null)
                        TextSpan(
                          text: ' · ${formatDateFromString(dateStr)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkHint,
                          ),
                        ),
                    ],
                  ),
                ),
                if ((member['email'] as String? ?? '').isNotEmpty)
                  Text(
                    member['email'] as String,
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((member['phone'] as String? ?? '').isNotEmpty)
                _WhatsAppButton(member: member, isReminder: true),
              const SizedBox(height: 6),
              _CollectButton(
                memberId: member['id'] as String,
                memberName: _name(member),
                gymId: gymId,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────────

String _name(Map<String, dynamic> m) {
  final first = m['first_name'] as String? ?? '';
  final last = m['last_name'] as String? ?? '';
  return '$first $last'.trim();
}

class _Avatar extends StatelessWidget {
  final Map<String, dynamic> member;
  const _Avatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final url = member['avatar_url'] as String?;
    final first = member['first_name'] as String? ?? '';
    final last = member['last_name'] as String? ?? '';
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        shape: BoxShape.circle,
      ),
      child: MemberPhoto(
        stored: url,
        fallback: _Initials(first: first, last: last),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String first;
  final String last;
  const _Initials({required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials(first, last),
        style: const TextStyle(
          color: AppTheme.ink,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isReminder;
  const _WhatsAppButton({required this.member, this.isReminder = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: () => _launch(context),
        icon: const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF25D366)),
        label: const Text('WA', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF25D366),
          side: const BorderSide(color: Color(0xFF25D366)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final phone = member['phone'] as String? ?? '';
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('91') ? clean : '91$clean';
    final name = _name(member);
    final dateStr = member['next_payment_date'] as String?;
    final dueDateFormatted = dateStr != null ? formatDateFromString(dateStr) : '';

    final text = isReminder
        ? 'Hi $name, this is a reminder that your gym membership payment is due on $dueDateFormatted. Please make the payment at the earliest. Thank you!'
        : 'Hi $name, ';

    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    }
  }
}

class _CollectButton extends ConsumerWidget {
  final String memberId;
  final String memberName;
  final String gymId;
  const _CollectButton({
    required this.memberId,
    required this.memberName,
    required this.gymId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _QuickCollectSheet(
              memberId: memberId,
              memberName: memberName,
            ),
          ).then((success) {
            if (success == true) {
              ref.invalidate(_overdueProvider(gymId));
              ref.invalidate(_upcomingProvider(gymId));
            }
          });
        },
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: const Text('Collect'),
      ),
    );
  }
}

// ── Quick Collect Sheet ────────────────────────────────────────────────────────

class _QuickCollectSheet extends ConsumerStatefulWidget {
  final String memberId;
  final String memberName;
  const _QuickCollectSheet({required this.memberId, required this.memberName});

  @override
  ConsumerState<_QuickCollectSheet> createState() => _QuickCollectSheetState();
}

class _QuickCollectSheetState extends ConsumerState<_QuickCollectSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;
  String? _planHint;
  String? _nextPaymentDate;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('upi', 'UPI', Icons.qr_code_outlined),
    ('bank_transfer', 'Bank Transfer', Icons.account_balance_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _autofill() async {
    try {
      final data = await Supabase.instance.client
          .from('members')
          .select('next_payment_date, memberships(status, membership_plans(price, name))')
          .eq('id', widget.memberId)
          .maybeSingle();
      if (data == null || !mounted) return;
      final memberships = (data['memberships'] as List?) ?? [];
      Map<String, dynamic>? active;
      for (final m in memberships) {
        if ((m as Map)['status'] == 'active') {
          active = m.cast<String, dynamic>();
          break;
        }
      }
      final plan = active?['membership_plans'] as Map?;
      setState(() {
        if (plan != null && plan['price'] != null) {
          final price = (plan['price'] as num).toStringAsFixed(0);
          _amountCtrl.text = price;
          _planHint = '${plan['name']} — ₹$price';
        }
        final npd = data['next_payment_date'] as String?;
        if (npd != null) _nextPaymentDate = npd.split('T').first;
      });
    } catch (e) {
      debugPrint('[GymCRM] Autofill error: $e');
    }
  }

  String? _advancePaymentDate(String dateStr) {
    final segs = dateStr.split('T').first.split('-');
    if (segs.length < 3) return null;
    final day = int.tryParse(segs[2]);
    if (day == null || day < 1 || day > 31) return null;
    final base = DateTime.now().toUtc();
    var year = base.year;
    var month = base.month + 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
    final daysInNext = DateTime.utc(year, month + 1, 0).day;
    final billingDay = day < daysInNext ? day : daysInNext;
    return DateTime.utc(year, month, billingDay).toIso8601String().split('T').first;
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    setState(() => _loading = true);
    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      // 1. Create invoice
      final invoiceResult = await client.from('invoices').insert({
        'member_id': widget.memberId,
        'gym_id': gymId,
        'amount': amount,
        if (_nextPaymentDate != null) 'due_at': _nextPaymentDate,
        'status': 'open',
      }).select('id').single();
      final invoiceId = invoiceResult['id'] as String;

      // 2. Record payment
      await client.from('payments').insert({
        'invoice_id': invoiceId,
        'amount': amount,
        'method': _method,
        'status': 'succeeded',
        'reference_no': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'recorded_by': client.auth.currentUser?.id,
      });

      // 3. Mark invoice paid
      await client.from('invoices').update({
        'status': 'paid',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', invoiceId);

      // 4. Advance next_payment_date + lift freeze
      final memberRow = await client
          .from('members')
          .select('next_payment_date, status')
          .eq('id', widget.memberId)
          .maybeSingle();
      if (memberRow != null) {
        final updates = <String, dynamic>{};
        final npd = memberRow['next_payment_date'] as String?;
        if (npd != null) {
          final advanced = _advancePaymentDate(npd);
          if (advanced != null) updates['next_payment_date'] = advanced;
        }
        if (memberRow['status'] == 'frozen') updates['status'] = 'active';
        if (updates.isNotEmpty) {
          await client.from('members').update(updates).eq('id', widget.memberId);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment collected'),
            backgroundColor: AppTheme.statusActive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Collect Payment',
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.activeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: AppTheme.inkSoft),
                  const SizedBox(width: 8),
                  Text(
                    widget.memberName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹) *',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text(
                'Auto-filled: $_planHint',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Payment method',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.map((m) {
                final selected = _method == m.$1;
                return GestureDetector(
                  onTap: () => setState(() => _method = m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.ink : AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppTheme.ink : AppTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(m.$3,
                            size: 16,
                            color: selected ? Colors.white : AppTheme.inkSoft),
                        const SizedBox(width: 6),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: switch (_method) {
                  'upi' => 'UPI Transaction ID (optional)',
                  'bank_transfer' => 'UTR number (optional)',
                  _ => 'Reference / Receipt no. (optional)',
                },
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Collect Payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.12) : AppTheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? activeColor : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  const _EmptyState({required this.icon, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppTheme.inkHint),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: AppTheme.inkHint, fontSize: 13)),
        ],
      ),
    );
  }
}
