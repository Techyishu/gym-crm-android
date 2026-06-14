import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _dashboardDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
  final thirtyDaysAgo = now.subtract(const Duration(days: 30)).toIso8601String();
  final in14Days = now.add(const Duration(days: 14)).toIso8601String().split('T')[0];
  final in3Days  = now.add(const Duration(days: 3)).toIso8601String().split('T')[0];
  final in7Days  = now.add(const Duration(days: 7)).toIso8601String().split('T')[0];
  final todayDate = now.toIso8601String().split('T')[0];
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1)).toIso8601String();

  // ── All queries fired in one parallel batch ────────────────────────────────
  // Count futures and data futures are both started before either is awaited,
  // so all 12 queries run concurrently.
  final countFuture = Future.wait<PostgrestResponse<List<Map<String, dynamic>>>>([
    client.from('members').select('id').eq('gym_id', gymId).eq('status', 'active').count(CountOption.exact),
    client.from('members').select('id').eq('gym_id', gymId).eq('status', 'expired').count(CountOption.exact),
    client.from('check_ins').select('id').eq('gym_id', gymId).gte('checked_in_at', startOfDay).count(CountOption.exact),
    client.from('check_ins').select('id').eq('gym_id', gymId).count(CountOption.exact),
    client.from('leads').select('id').eq('gym_id', gymId).gte('created_at', startOfWeek).count(CountOption.exact),
    client.from('membership_plans').select('id').eq('gym_id', gymId).eq('is_active', true).count(CountOption.exact),
  ]);
  final dataFuture = Future.wait<List<Map<String, dynamic>>>([
    client.from('invoices').select('amount, paid_at, members(first_name, last_name)').eq('gym_id', gymId).eq('status', 'paid').order('paid_at', ascending: false).limit(4),
    client.from('invoices').select('amount').eq('gym_id', gymId).inFilter('status', ['pending', 'open', 'overdue']),
    client.from('invoices').select('amount').eq('gym_id', gymId).eq('status', 'paid').gte('paid_at', thirtyDaysAgo),
    client.from('members').select('id, first_name, last_name, phone, next_payment_date').eq('gym_id', gymId).eq('status', 'active').gte('next_payment_date', todayDate).lte('next_payment_date', in14Days).order('next_payment_date'),
    client.from('leads').select('id, first_name, last_name, phone, source, status, created_at').eq('gym_id', gymId).order('created_at', ascending: false).limit(4),
    client.from('check_ins').select('id, checked_in_at, members(first_name, last_name)').eq('gym_id', gymId).gte('checked_in_at', startOfDay).order('checked_in_at', ascending: false).limit(8),
  ]);

  final countResults = await countFuture;
  final dataResults  = await dataFuture;

  final activeMembers   = countResults[0].count ?? 0;
  final expiredMembers  = countResults[1].count ?? 0;
  final todayCheckins   = countResults[2].count ?? 0;
  final allTimeCheckins = countResults[3].count ?? 0;
  final leadsThisWeek   = countResults[4].count ?? 0;
  final planCount       = countResults[5].count ?? 0;

  final recentPaidInvoices = dataResults[0];
  final openInvoicesList   = dataResults[1];
  final paidInvoicesList   = dataResults[2];
  final dueMembersList     = dataResults[3];
  final recentLeads        = dataResults[4];
  final todayCheckinsList  = dataResults[5];

  final monthRevenue   = paidInvoicesList.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
  final pendingRevenue = openInvoicesList.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

  final due3  = dueMembersList.where((m) {
    final d = m['next_payment_date'] as String? ?? '';
    return d.isNotEmpty && d.compareTo(in3Days) <= 0;
  }).toList();
  final due7  = dueMembersList.where((m) {
    final d = m['next_payment_date'] as String? ?? '';
    return d.isNotEmpty && d.compareTo(in3Days) > 0 && d.compareTo(in7Days) <= 0;
  }).toList();
  final due14 = dueMembersList.where((m) {
    final d = m['next_payment_date'] as String? ?? '';
    return d.isNotEmpty && d.compareTo(in7Days) > 0 && d.compareTo(in14Days) <= 0;
  }).toList();

  return {
    'activeMembers':      activeMembers,
    'expiredMembers':     expiredMembers,
    'todayCheckins':      todayCheckins,
    'allTimeCheckins':    allTimeCheckins,
    'monthRevenue':       monthRevenue,
    'pendingRevenue':     pendingRevenue,
    'recentPaidInvoices': recentPaidInvoices,
    'due3':               due3,
    'due7':               due7,
    'due14':              due14,
    'allDueMembers':      dueMembersList,
    'recentLeads':        recentLeads,
    'leadsThisWeek':      leadsThisWeek,
    'planCount':          planCount,
    'todayCheckinsList':  todayCheckinsList,
    'memberCount':        activeMembers,
  };
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dashboardDataProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.ink,
        onRefresh: () async {
          ref.invalidate(_dashboardDataProvider);
        },
        child: data.when(
          loading: () => const _LoadingBody(),
          error: (e, _) => _ErrorBody(error: e.toString()),
          data: (d) => _DashboardBody(data: d),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(4, (_) => Container(
          height: 100,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(12)),
        )),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Failed to load dashboard', style: const TextStyle(color: AppTheme.inkHint, fontSize: 14)),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final memberCount = (data['memberCount'] as int?) ?? 0;
    final planCount = (data['planCount'] as int?) ?? 0;
    final allTimeCheckins = (data['allTimeCheckins'] as int?) ?? 0;

    final showChecklist = memberCount < 3 || planCount == 0 || allTimeCheckins == 0;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showChecklist) ...[
            _SetupChecklist(
              memberCount: memberCount,
              planCount: planCount,
              allTimeCheckins: allTimeCheckins,
            ),
            const SizedBox(height: 16),
          ],
          _KpiGrid(data: data),
          const SizedBox(height: 16),
          _UpcomingPaymentsCard(data: data),
          const SizedBox(height: 16),
          _PaymentDueCard(due3: data['due3'] as List<dynamic>),
          const SizedBox(height: 16),
          _QuickActionsCard(),
          const SizedBox(height: 16),
          _TodayCheckinsCard(checkins: data['todayCheckinsList'] as List<dynamic>, todayCount: (data['todayCheckins'] as int?) ?? 0),
          const SizedBox(height: 16),
          _RecentPaymentsCard(invoices: data['recentPaidInvoices'] as List<dynamic>, pendingRevenue: (data['pendingRevenue'] as double?) ?? 0),
          const SizedBox(height: 16),
          _NewLeadsCard(leads: data['recentLeads'] as List<dynamic>, leadsThisWeek: (data['leadsThisWeek'] as int?) ?? 0),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Setup Checklist ──────────────────────────────────────────────────────────

class _SetupChecklist extends StatelessWidget {
  final int memberCount;
  final int planCount;
  final int allTimeCheckins;

  const _SetupChecklist({required this.memberCount, required this.planCount, required this.allTimeCheckins});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ChecklistItem(label: 'Add your first 3 members', done: memberCount >= 3, route: '/staff/members'),
      _ChecklistItem(label: 'Create a membership plan', done: planCount > 0, route: '/staff/settings'),
      _ChecklistItem(label: 'Record your first check-in', done: allTimeCheckins > 0, route: '/staff/check-in'),
    ];
    final doneCount = items.where((i) => i.done).length;

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Finish setting up your gym', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(20)),
                  child: Text('$doneCount/3 done', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
                ),
              ],
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Column(
              children: [
                if (i > 0) const Divider(height: 1, color: AppTheme.border),
                _ChecklistRow(item: item, index: i + 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ChecklistItem {
  final String label;
  final bool done;
  final String route;
  const _ChecklistItem({required this.label, required this.done, required this.route});
}

class _ChecklistRow extends StatelessWidget {
  final _ChecklistItem item;
  final int index;
  const _ChecklistRow({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: item.done ? AppTheme.ink : Colors.transparent,
                shape: BoxShape.circle,
                border: item.done ? null : Border.all(color: AppTheme.border, width: 1.5),
              ),
              child: Center(
                child: item.done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('$index', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: item.done ? AppTheme.inkHint : AppTheme.ink,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.inkHint,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.inkHint, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── KPI Grid ─────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const _KpiGrid({required this.data});

  String _formatRevenue(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}k';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final activeMembers = (data['activeMembers'] as int?) ?? 0;
    final todayCheckins = (data['todayCheckins'] as int?) ?? 0;
    final due14 = ((data['due3'] as List).length + (data['due7'] as List).length + (data['due14'] as List).length);
    final monthRevenue = (data['monthRevenue'] as double?) ?? 0;

    final tiles = [
      _KpiData(
        label: 'Members',
        value: '$activeMembers',
        icon: Icons.people_outline,
        iconBg: const Color(0xFFF0F0F0),
      ),
      _KpiData(
        label: 'Check-ins Today',
        value: '$todayCheckins',
        icon: Icons.check_circle_outline,
        iconBg: const Color(0xFFF2F2F2),
      ),
      _KpiData(
        label: 'Due Soon',
        value: '$due14',
        icon: Icons.schedule_outlined,
        iconBg: const Color(0xFFFFF3E0),
      ),
      _KpiData(
        label: 'Revenue (30d)',
        value: _formatRevenue(monthRevenue),
        icon: Icons.currency_rupee_outlined,
        iconBg: const Color(0xFFF2F2F2),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: tiles.map((t) => _KpiTile(data: t)).toList(),
    );
  }
}

class _KpiData {
  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  const _KpiData({required this.label, required this.value, required this.icon, required this.iconBg});
}

class _KpiTile extends StatelessWidget {
  final _KpiData data;
  const _KpiTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: data.iconBg, shape: BoxShape.circle),
            child: Icon(data.icon, size: 18, color: AppTheme.inkSoft),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF8a6800), height: 1.1),
              ),
              const SizedBox(height: 2),
              Text(data.label, style: const TextStyle(fontSize: 12, color: AppTheme.inkHint, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Upcoming Payments Card ───────────────────────────────────────────────────

class _UpcomingPaymentsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _UpcomingPaymentsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final due3 = data['due3'] as List<dynamic>;
    final due7 = data['due7'] as List<dynamic>;
    final due14 = data['due14'] as List<dynamic>;

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          _CardHeader(title: 'Upcoming Payments', viewAll: () => context.push('/staff/upcoming-payments')),
          const Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _DueBucket(label: '≤ 3 days', count: due3.length, color: AppTheme.statusDanger, onTap: () => context.push('/staff/members')),
                const SizedBox(width: 12),
                _DueBucket(label: '4–7 days', count: due7.length, color: AppTheme.statusWarn, onTap: () => context.push('/staff/members')),
                const SizedBox(width: 12),
                _DueBucket(label: '8–14 days', count: due14.length, color: AppTheme.accent, onTap: () => context.push('/staff/members')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DueBucket extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _DueBucket({required this.label, required this.count, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.inkHint, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Payment Due Card ─────────────────────────────────────────────────────────

class _PaymentDueCard extends ConsumerWidget {
  final List<dynamic> due3;
  const _PaymentDueCard({required this.due3});

  Future<void> _showCollectSheet(BuildContext context, WidgetRef ref, Map<String, dynamic> member) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CollectPaymentSheet(
        member: member,
        onPaid: () => ref.invalidate(_dashboardDataProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          _CardHeader(
            title: 'Payment Due',
            badge: due3.isNotEmpty ? '${due3.length} urgent' : null,
            badgeColor: AppTheme.statusDangerBg,
            badgeTextColor: AppTheme.statusDanger,
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (due3.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No payments due in the next 3 days', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: due3.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (_, i) {
                final m = due3[i] as Map<String, dynamic>;
                final firstName = m['first_name'] as String? ?? '';
                final lastName = m['last_name'] as String? ?? '';
                final name = '$firstName $lastName'.trim();
                final nextPayment = m['next_payment_date'] as String?;
                final daysUntil = nextPayment != null
                    ? DateTime.parse(nextPayment).difference(DateTime.now()).inDays
                    : 0;

                return InkWell(
                  onTap: () => _showCollectSheet(context, ref, m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        _Avatar(name: name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                              const SizedBox(height: 2),
                              Text(
                                daysUntil <= 0 ? 'Due today' : 'Due in $daysUntil day${daysUntil == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                              ),
                            ],
                          ),
                        ),
                        _StatusBadge(status: daysUntil <= 1 ? 'danger' : daysUntil <= 3 ? 'warn' : 'neutral'),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkHint),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Collect Payment Sheet ────────────────────────────────────────────────────

class _CollectPaymentSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> member;
  final VoidCallback onPaid;
  const _CollectPaymentSheet({required this.member, required this.onPaid});

  @override
  ConsumerState<_CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends ConsumerState<_CollectPaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  String  _method          = 'cash';
  bool    _loading         = false;
  String? _planHint;
  String? _nextPaymentDate;

  static const _methods = [
    ('cash',          'Cash',         Icons.payments_outlined),
    ('upi',           'UPI',          Icons.qr_code_outlined),
    ('bank_transfer', 'Bank Transfer',Icons.account_balance_outlined),
    ('card',          'Card',         Icons.credit_card_outlined),
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
    final memberId = widget.member['id'] as String?;
    if (memberId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('members')
          .select('next_payment_date, memberships(status, membership_plans(price, name))')
          .eq('id', memberId)
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
      debugPrint('[GymCRM] CollectPayment autofill error: $e');
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
    if (month > 12) { month = 1; year += 1; }
    final daysInNext = DateTime.utc(year, month + 1, 0).day;
    final billingDay = day < daysInNext ? day : daysInNext;
    return DateTime.utc(year, month, billingDay).toIso8601String().split('T').first;
  }

  Future<void> _collect() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _loading = true);
    try {
      final gymId  = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;
      final memberId = widget.member['id'] as String;

      // 1. Create invoice
      final invoiceResult = await client.from('invoices').insert({
        'member_id': memberId,
        'gym_id':    gymId,
        'amount':    amount,
        if (_nextPaymentDate != null) 'due_at': _nextPaymentDate,
        'status': 'open',
      }).select('id').single();
      final invoiceId = invoiceResult['id'] as String;

      // 2. Record payment
      await client.from('payments').insert({
        'invoice_id':   invoiceId,
        'amount':       amount,
        'method':       _method,
        'status':       'succeeded',
        'reference_no': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'notes':        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'recorded_by':  client.auth.currentUser?.id,
      });

      // 3. Mark invoice paid
      await client.from('invoices').update({
        'status':  'paid',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', invoiceId);

      // 4. Advance next_payment_date + lift freeze
      final memberRow = await client
          .from('members')
          .select('next_payment_date, status')
          .eq('id', memberId)
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
          await client.from('members').update(updates).eq('id', memberId);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onPaid();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment collected'), backgroundColor: AppTheme.statusActive),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] CollectPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to collect payment. Please try again.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendWhatsApp() async {
    final phone     = widget.member['phone'] as String?;
    final firstName = widget.member['first_name'] as String? ?? '';
    if (phone == null || phone.isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    final msg = Uri.encodeComponent('Hi $firstName! Your gym membership payment is due. Please make the payment at your earliest. 🙏');
    final url = Uri.parse('https://wa.me/91$cleaned?text=$msg');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.member['first_name'] as String? ?? '';
    final lastName  = widget.member['last_name']  as String? ?? '';
    final name      = '$firstName $lastName'.trim();
    final phone     = widget.member['phone'] as String?;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + close
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
            // Member name chip
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
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Amount
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
              Text('Auto-filled: $_planHint', style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
            ],
            const SizedBox(height: 16),
            // Method label
            const Text(
              'Payment method',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 10),
            // Method chips
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
                        Icon(m.$3, size: 16, color: selected ? Colors.white : AppTheme.inkSoft),
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
            // Reference field (label changes by method)
            TextFormField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: switch (_method) {
                  'upi'           => 'UPI Transaction ID (optional)',
                  'bank_transfer' => 'UTR number (optional)',
                  _               => 'Reference / Receipt no. (optional)',
                },
              ),
            ),
            const SizedBox(height: 12),
            // Notes
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 20),
            // Collect button
            ElevatedButton(
              onPressed: _loading ? null : _collect,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Collect Payment'),
            ),
            // WhatsApp reminder
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sendWhatsApp,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF25D366)),
                  label: const Text('WhatsApp Reminder'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Quick Actions Card ───────────────────────────────────────────────────────

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QA(label: 'Add Member', icon: Icons.person_add_outlined, route: '/staff/members', gold: true),
      _QA(label: 'Collect Payment', icon: Icons.payments_outlined, route: '/staff/billing', gold: false),
      _QA(label: 'Add Lead', icon: Icons.person_search_outlined, route: '/staff/leads', gold: false),
      _QA(label: 'Check-in Member', icon: Icons.qr_code_scanner_outlined, route: '/staff/check-in', gold: false),
    ];

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Quick Actions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: actions.map((a) => _QAButton(action: a)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _QA {
  final String label;
  final IconData icon;
  final String route;
  final bool gold;
  const _QA({required this.label, required this.icon, required this.route, required this.gold});
}

class _QAButton extends StatelessWidget {
  final _QA action;
  const _QAButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(action.route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: action.gold ? AppTheme.accent.withValues(alpha: 0.12) : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: action.gold ? AppTheme.accent.withValues(alpha: 0.3) : AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: action.gold ? AppTheme.accent : AppTheme.activeBg,
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 16, color: action.gold ? AppTheme.accentFg : AppTheme.inkSoft),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(action.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Today's Check-ins Card ───────────────────────────────────────────────────

class _TodayCheckinsCard extends StatelessWidget {
  final List<dynamic> checkins;
  final int todayCount;
  const _TodayCheckinsCard({required this.checkins, required this.todayCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          _CardHeader(
            title: "Today's Check-ins",
            badge: '$todayCount today',
            viewAll: () => context.push('/staff/check-in'),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (checkins.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No check-ins today', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: checkins.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (_, i) {
                final ci = checkins[i] as Map<String, dynamic>;
                final member = ci['members'] as Map<String, dynamic>?;
                final firstName = member?['first_name'] as String? ?? '';
                final lastName = member?['last_name'] as String? ?? '';
                final name = '$firstName $lastName'.trim().isEmpty ? 'Unknown' : '$firstName $lastName'.trim();
                final checkedInAt = ci['checked_in_at'] as String?;
                String timeStr = '';
                if (checkedInAt != null) {
                  try {
                    final dt = DateTime.parse(checkedInAt).toLocal();
                    final h = dt.hour;
                    final m = dt.minute.toString().padLeft(2, '0');
                    final period = h >= 12 ? 'PM' : 'AM';
                    final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
                    timeStr = '$displayH:$m $period';
                  } catch (e) {
                    debugPrint('[GymCRM] Parse check-in time error: $e');
                  }
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _Avatar(name: name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                            if (timeStr.isNotEmpty)
                              Text(timeStr, style: const TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(20)),
                        child: const Text('In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.statusActive)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Recent Payments Card ─────────────────────────────────────────────────────

class _RecentPaymentsCard extends StatelessWidget {
  final List<dynamic> invoices;
  final double pendingRevenue;
  const _RecentPaymentsCard({required this.invoices, required this.pendingRevenue});

  @override
  Widget build(BuildContext context) {
    String? badgeText;
    if (pendingRevenue > 0) {
      if (pendingRevenue >= 100000) {
        badgeText = '₹${(pendingRevenue / 100000).toStringAsFixed(1)}L pending';
      } else if (pendingRevenue >= 1000) {
        badgeText = '₹${(pendingRevenue / 1000).toStringAsFixed(0)}k pending';
      } else {
        badgeText = '₹${pendingRevenue.toStringAsFixed(0)} pending';
      }
    }

    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          _CardHeader(
            title: 'Recent Payments',
            badge: badgeText,
            badgeColor: AppTheme.statusWarnBg,
            badgeTextColor: AppTheme.statusWarn,
            viewAll: () => context.push('/staff/billing'),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (invoices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No recent payments', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (_, i) {
                final inv = invoices[i] as Map<String, dynamic>;
                final member = inv['members'] as Map<String, dynamic>?;
                final firstName = member?['first_name'] as String? ?? '';
                final lastName = member?['last_name'] as String? ?? '';
                final name = '$firstName $lastName'.trim().isEmpty ? 'Unknown' : '$firstName $lastName'.trim();
                final paidAt = inv['paid_at'] as String?;
                final amount = inv['amount_paid'];
                final amountNum = amount is num ? amount.toDouble() : double.tryParse(amount?.toString() ?? '') ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _Avatar(name: name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                            if (paidAt != null)
                              Text(formatDateFromString(paidAt), style: const TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(20)),
                            child: const Text('Paid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.statusActive)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${amountNum.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── New Leads Card ───────────────────────────────────────────────────────────

class _NewLeadsCard extends StatelessWidget {
  final List<dynamic> leads;
  final int leadsThisWeek;
  const _NewLeadsCard({required this.leads, required this.leadsThisWeek});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          _CardHeader(
            title: 'New Leads',
            badge: '$leadsThisWeek this week',
            viewAll: () => context.push('/staff/leads'),
          ),
          const Divider(height: 1, color: AppTheme.border),
          if (leads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No leads yet', style: TextStyle(fontSize: 14, color: AppTheme.inkHint))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leads.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (_, i) {
                final lead = leads[i] as Map<String, dynamic>;
                final firstName = lead['first_name'] as String? ?? '';
                final lastName = lead['last_name'] as String? ?? '';
                final name = '$firstName $lastName'.trim().isEmpty ? 'Unknown' : '$firstName $lastName'.trim();
                final source = lead['source'] as String? ?? '';
                final status = lead['status'] as String? ?? 'new';
                final createdAt = lead['created_at'] as String?;
                final phone = lead['phone'] as String?;

                String subText = '';
                if (source.isNotEmpty) subText = source;
                if (createdAt != null) {
                  final dateStr = formatDateFromString(createdAt);
                  subText = subText.isNotEmpty ? '$subText · $dateStr' : dateStr;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _Avatar(name: name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                            if (subText.isNotEmpty)
                              Text(subText, style: const TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                          ],
                        ),
                      ),
                      _LeadStatusBadge(status: status),
                      const SizedBox(width: 8),
                      if (phone != null && phone.isNotEmpty)
                        GestureDetector(
                          onTap: () async {
                            final url = Uri.parse('tel:$phone');
                            if (await canLaunchUrl(url)) await launchUrl(url);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.activeBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _LeadStatusBadge extends StatelessWidget {
  final String status;
  const _LeadStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'converted':
        bg = AppTheme.statusActiveBg;
        fg = AppTheme.statusActive;
        break;
      case 'lost':
        bg = AppTheme.statusDangerBg;
        fg = AppTheme.statusDanger;
        break;
      case 'follow_up':
        bg = AppTheme.statusWarnBg;
        fg = AppTheme.statusWarn;
        break;
      default:
        bg = AppTheme.statusNeutralBg;
        fg = AppTheme.statusNeutral;
    }
    final raw = status.isEmpty ? 'new' : status;
    final label = raw.replaceAll('_', ' ');
    final display = label[0].toUpperCase() + label.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        display,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final String title;
  final String? badge;
  final Color? badgeColor;
  final Color? badgeTextColor;
  final VoidCallback? viewAll;

  const _CardHeader({
    required this.title,
    this.badge,
    this.badgeColor,
    this.badgeTextColor,
    this.viewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212121))),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor ?? AppTheme.activeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge!,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeTextColor ?? AppTheme.inkSoft),
              ),
            ),
          ],
          const Spacer(),
          if (viewAll != null)
            GestureDetector(
              onTap: viewAll,
              child: const Row(
                children: [
                  Text('View all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
                  Icon(Icons.chevron_right, size: 16, color: AppTheme.inkHint),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : (name.isNotEmpty ? name[0].toUpperCase() : '?');

    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle),
      child: Center(
        child: Text(initials, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'danger':
        bg = AppTheme.statusDangerBg;
        fg = AppTheme.statusDanger;
        label = 'Urgent';
        break;
      case 'warn':
        bg = AppTheme.statusWarnBg;
        fg = AppTheme.statusWarn;
        label = 'Soon';
        break;
      default:
        bg = AppTheme.statusNeutralBg;
        fg = AppTheme.statusNeutral;
        label = 'Due';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
