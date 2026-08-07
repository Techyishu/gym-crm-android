import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/advance_payment_date.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/invoice_pdf.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import '../members/upcoming_payments_screen.dart' show QuickCollectSheet;

final _plansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  return await client
      .from('membership_plans')
      .select()
      .eq('gym_id', gymId)
      .order('price');
});

final _membersListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  return await client
      .from('members')
      .select('id, first_name, last_name')
      .eq('gym_id', gymId)
      .eq('status', 'active')
      .order('first_name');
});

// Period shown on the balance card's hero number.
enum BillingPeriod { today, week, month }

// Money dashboard: collected totals for today/week/month (each vs the same
// elapsed-length window immediately before it), open due count, and a merged
// feed of recent payments + open dues (banking-app style).
final _billingFeedProvider = FutureProvider<_BillingFeed>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final upperBound = now.add(const Duration(minutes: 1));
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));
  final startOfMonth = DateTime(now.year, now.month, 1);

  final elapsedWeek = now.difference(startOfWeek);
  final prevWeekStart = startOfWeek.subtract(elapsedWeek);
  final elapsedMonth = now.difference(startOfMonth);
  final prevMonthStart = startOfMonth.subtract(elapsedMonth);

  // Earliest bound any of the three period comparisons need.
  final statsFrom = prevMonthStart.isBefore(prevWeekStart) ? prevMonthStart : prevWeekStart;

  final results = await Future.wait([
    // Recent payments feed (with member/method info for display) — widened to
    // the start of the month so the Today/Week/Month toggle always has data.
    client
        .from('payments')
        .select('amount, method, created_at, invoice_id, invoices!inner(gym_id, members(first_name, last_name))')
        .eq('invoices.gym_id', gymId)
        .eq('status', 'succeeded')
        .gte('created_at', startOfMonth.toIso8601String())
        .order('created_at', ascending: false),
    client
        .from('invoices')
        .select('id, amount, due_at, member_id, members(first_name, last_name, email, phone)')
        .eq('gym_id', gymId)
        .eq('status', 'open')
        .order('due_at'),
    // Wider-range, lightweight payments for the today/week/month sums.
    client
        .from('payments')
        .select('amount, created_at, invoices!inner(gym_id)')
        .eq('invoices.gym_id', gymId)
        .eq('status', 'succeeded')
        .gte('created_at', statsFrom.toIso8601String()),
    // Members whose next renewal has passed or falls in the next 30 days but
    // don't have an open invoice yet (mirrors Upcoming Payments' window) —
    // Collect on these creates the invoice on the spot.
    client
        .from('members')
        .select('id, first_name, last_name, next_payment_date, memberships(status, discount_amount, membership_plans(price, name))')
        .eq('gym_id', gymId)
        .not('status', 'eq', 'cancelled')
        .lte('next_payment_date', now.add(const Duration(days: 30)).toIso8601String().split('T').first)
        .order('next_payment_date'),
  ]);

  final payments = (results[0] as List).cast<Map<String, dynamic>>();
  final dues = (results[1] as List).cast<Map<String, dynamic>>();
  final statsPayments = (results[2] as List).cast<Map<String, dynamic>>();
  final renewingMembers = (results[3] as List).cast<Map<String, dynamic>>();
  final invoicedMemberIds = dues.map((d) => d['member_id']).toSet();
  final projected = renewingMembers.where((m) => !invoicedMemberIds.contains(m['id']));

  double sumBetween(DateTime from, DateTime to) => statsPayments
      .where((p) {
        final t = DateTime.tryParse(p['created_at'] as String? ?? '');
        return t != null && !t.isBefore(from) && t.isBefore(to);
      })
      .fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));

  int? pctChange(double current, double previous) =>
      previous > 0 ? ((current - previous) / previous * 100).round() : null;

  final collectedToday = sumBetween(startOfToday, upperBound);
  final collectedYesterday = sumBetween(startOfYesterday, startOfToday);
  final collectedWeek = sumBetween(startOfWeek, upperBound);
  final collectedPrevWeek = sumBetween(prevWeekStart, startOfWeek);
  final collectedMonth = sumBetween(startOfMonth, upperBound);
  final collectedPrevMonth = sumBetween(prevMonthStart, startOfMonth);

  final items = <_TxnItem>[
    for (final p in payments) _TxnItem.payment(p),
    for (final d in dues) _TxnItem.due(d),
    for (final m in projected) _TxnItem.projected(m),
  ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));

  final invoicedTotal = dues.fold<double>(0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0));
  final projectedTotal = projected.fold<double>(0, (s, m) => s + _activePlanPrice(m));
  final overdueCount = dues.where((d) {
        final due = DateTime.tryParse(d['due_at'] as String? ?? '');
        return due != null && due.isBefore(now);
      }).length +
      projected.where((m) {
        final due = DateTime.tryParse(m['next_payment_date'] as String? ?? '');
        return due != null && due.isBefore(now);
      }).length;

  return _BillingFeed(
    collected: {
      BillingPeriod.today: collectedToday,
      BillingPeriod.week: collectedWeek,
      BillingPeriod.month: collectedMonth,
    },
    growthPct: {
      BillingPeriod.today: pctChange(collectedToday, collectedYesterday),
      BillingPeriod.week: pctChange(collectedWeek, collectedPrevWeek),
      BillingPeriod.month: pctChange(collectedMonth, collectedPrevMonth),
    },
    dueCount: dues.length + projected.length,
    dueTotal: invoicedTotal + projectedTotal,
    dueMembers: invoicedMemberIds.length + projected.length,
    overdueCount: overdueCount,
    items: items,
  );
});

// Active plan price minus any per-member discount — same rule QuickCollectSheet
// uses to autofill the amount when it creates the invoice on Collect.
double _activePlanPrice(Map<String, dynamic> member) {
  final memberships = (member['memberships'] as List?) ?? const [];
  for (final m in memberships) {
    final map = (m as Map).cast<String, dynamic>();
    if (map['status'] != 'active') continue;
    final plan = map['membership_plans'] as Map?;
    if (plan == null || plan['price'] == null) continue;
    final listPrice = (plan['price'] as num).toDouble();
    final discount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    return (listPrice - discount).clamp(0, listPrice);
  }
  return 0;
}

class _BillingFeed {
  final Map<BillingPeriod, double> collected;
  final Map<BillingPeriod, int?> growthPct;
  final int dueCount;
  final double dueTotal;
  final int dueMembers;
  final int overdueCount;
  final List<_TxnItem> items;
  const _BillingFeed({
    required this.collected,
    required this.growthPct,
    required this.dueCount,
    required this.dueTotal,
    required this.dueMembers,
    required this.overdueCount,
    required this.items,
  });
}

// One row in the merged feed — either a collected payment or an open due.
class _TxnItem {
  final bool isDue;
  final String invoiceId;
  final String? memberId;
  final String name;
  final double amount;
  final String subtitle;
  final Color color;
  final DateTime sortKey;
  final Map<String, dynamic> raw;

  const _TxnItem._({
    required this.isDue,
    required this.invoiceId,
    this.memberId,
    required this.name,
    required this.amount,
    required this.subtitle,
    required this.color,
    required this.sortKey,
    required this.raw,
  });

  // No invoice exists yet for this due — Collect creates one on the spot.
  bool get needsInvoice => isDue && invoiceId.isEmpty;

  static ({String subtitle, Color color}) _dueSubtitle(DateTime? due) {
    if (due == null) return (subtitle: 'Due', color: AppTheme.statusWarn);
    final days = due.difference(DateTime.now()).inDays;
    if (days < 0) return (subtitle: '${days.abs()} day${days == -1 ? '' : 's'} overdue', color: AppTheme.statusDanger);
    if (days == 0) return (subtitle: 'Due today', color: AppTheme.statusWarn);
    return (subtitle: 'Due in $days day${days == 1 ? '' : 's'}', color: AppTheme.statusWarn);
  }

  factory _TxnItem.payment(Map<String, dynamic> p) {
    final invoice = p['invoices'] as Map<String, dynamic>?;
    final member = invoice?['members'] as Map<String, dynamic>?;
    final created = DateTime.tryParse(p['created_at'] as String? ?? '') ?? DateTime.now();
    final method = (p['method'] as String?)?.replaceAll('_', ' ') ?? '';
    final methodLabel = method.isEmpty ? 'Payment' : method[0].toUpperCase() + method.substring(1);
    return _TxnItem._(
      isDue: false,
      invoiceId: p['invoice_id'] as String? ?? '',
      name: member != null ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim() : 'Unknown',
      amount: (p['amount'] as num?)?.toDouble() ?? 0,
      subtitle: '$methodLabel · ${DateFormat('d MMM, h:mm a').format(created.toLocal())}',
      color: AppTheme.statusActive,
      sortKey: created,
      raw: p,
    );
  }

  factory _TxnItem.due(Map<String, dynamic> inv) {
    final member = inv['members'] as Map<String, dynamic>?;
    final due = DateTime.tryParse(inv['due_at'] as String? ?? '');
    final s = _dueSubtitle(due);
    return _TxnItem._(
      isDue: true,
      invoiceId: inv['id'] as String? ?? '',
      memberId: inv['member_id'] as String?,
      name: member != null ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim() : 'Unknown',
      amount: (inv['amount'] as num?)?.toDouble() ?? 0,
      subtitle: s.subtitle,
      color: s.color,
      sortKey: due ?? DateTime.now(),
      raw: inv,
    );
  }

  // A member whose renewal is due/overdue but has no open invoice yet.
  factory _TxnItem.projected(Map<String, dynamic> member) {
    final due = DateTime.tryParse(member['next_payment_date'] as String? ?? '');
    final s = _dueSubtitle(due);
    return _TxnItem._(
      isDue: true,
      invoiceId: '',
      memberId: member['id'] as String?,
      name: '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim(),
      amount: _activePlanPrice(member),
      subtitle: s.subtitle,
      color: s.color,
      sortKey: due ?? DateTime.now(),
      raw: member,
    );
  }
}

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  // 'all' | 'due' | 'collected'
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(_billingFeedProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(_billingFeedProvider),
          child: CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Text('Billing',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: feed.when(
                    loading: () => const _BalanceCardSkeleton(),
                    error: (_, __) => const _BalanceCardSkeleton(),
                    data: (data) => _BalanceCard(
                      dueTotal: data.dueTotal,
                      dueMembers: data.dueMembers,
                      overdueCount: data.overdueCount,
                      collectedMonth: data.collected[BillingPeriod.month] ?? 0,
                      growthPct: data.growthPct[BillingPeriod.month],
                      dueCount: data.dueCount,
                      onRecord: () => setState(() => _filter = 'due'),
                      onInvoice: () => _showCreateInvoiceSheet(context),
                      onNewPlan: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const _PlansTab()),
                      ),
                      onDue: () => setState(() => _filter = 'due'),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('All transactions',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          PillChip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                          const SizedBox(width: 8),
                          PillChip(label: 'Due', selected: _filter == 'due', onTap: () => setState(() => _filter = 'due')),
                          const SizedBox(width: 8),
                          PillChip(label: 'Collected', selected: _filter == 'collected', onTap: () => setState(() => _filter = 'collected')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              feed.when(
                loading: () => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: 6,
                    itemBuilder: (_, __) => Shimmer.fromColors(
                      baseColor: const Color(0xFFE8E8E8),
                      highlightColor: const Color(0xFFF5F5F5),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        height: 68,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('Could not load transactions. Pull to retry.', style: TextStyle(color: AppTheme.inkSoft))),
                  ),
                ),
                data: (data) {
                  final items = data.items.where((t) {
                    if (_filter == 'due') return t.isDue;
                    if (_filter == 'collected') return !t.isDue;
                    return true;
                  }).toList();
                  if (items.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('No transactions', style: TextStyle(color: AppTheme.inkHint, fontSize: 14))),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => _TxnCard(
                        item: items[i],
                        onTap: () => _openInvoice(context, items[i]),
                        onCollect: () => _collect(context, items[i]),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openInvoice(BuildContext context, _TxnItem item) {
    if (item.invoiceId.isEmpty) return;
    context.push('/invoice/${item.invoiceId}');
  }

  void _collect(BuildContext context, _TxnItem item) {
    if (item.needsInvoice) {
      // No invoice exists yet for this renewal — QuickCollectSheet creates
      // one and records the payment in a single step.
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => QuickCollectSheet(memberId: item.memberId!, memberName: item.name),
      ).then((_) => ref.invalidate(_billingFeedProvider));
      return;
    }
    final invoice = Invoice.fromJson(item.raw);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecordPaymentSheet(invoice: invoice),
    ).then((_) => ref.invalidate(_billingFeedProvider));
  }

  void _showCreateInvoiceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CreateInvoiceSheet(),
    ).then((_) => ref.invalidate(_billingFeedProvider));
  }
}

// ── Balance Card (banking-app hero) ─────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double dueTotal;
  final int dueMembers;
  final int overdueCount;
  final double collectedMonth;
  final int? growthPct;
  final int dueCount;
  final VoidCallback onRecord;
  final VoidCallback onInvoice;
  final VoidCallback onNewPlan;
  final VoidCallback onDue;
  const _BalanceCard({
    required this.dueTotal,
    required this.dueMembers,
    required this.overdueCount,
    required this.collectedMonth,
    required this.growthPct,
    required this.dueCount,
    required this.onRecord,
    required this.onInvoice,
    required this.onNewPlan,
    required this.onDue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: AppTheme.darkCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Amount due',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.statusWarn)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatCurrency(dueTotal),
              style: AppTheme.numberStyle(fontSize: 38, color: AppTheme.onDark, height: 1.0)),
          ),
          const SizedBox(height: 6),
          Text('$dueMembers member${dueMembers == 1 ? '' : 's'} · $overdueCount overdue',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0x1FFFFFFF)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Collected this month',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
              Row(
                children: [
                  Text(formatCurrency(collectedMonth),
                    style: AppTheme.numberStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.onDark)),
                  if (growthPct != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${growthPct! >= 0 ? '↑' : '↓'}${growthPct!.abs()}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: growthPct! >= 0 ? AppTheme.mintOnDark : AppTheme.statusDanger,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _DockAction(icon: Icons.credit_card_outlined, label: 'Record', onTap: onRecord),
              _DockAction(icon: Icons.receipt_outlined, label: 'Invoice', onTap: onInvoice),
              _DockAction(icon: Icons.sell_outlined, label: 'Plans', onTap: onNewPlan),
              _DockAction(icon: Icons.schedule_outlined, label: 'Due · $dueCount', onTap: onDue),
            ],
          ),
        ],
      ),
    );
  }
}

class _DockAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DockAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: AppTheme.darkCard2, shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: AppTheme.onDark),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onDarkSoft)),
        ],
      ),
    );
  }
}

class _BalanceCardSkeleton extends StatelessWidget {
  const _BalanceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 216,
      decoration: AppTheme.darkCardDecoration(),
    );
  }
}

// ── Transaction Card ─────────────────────────────────────────────────────────

class _TxnCard extends StatelessWidget {
  final _TxnItem item;
  final VoidCallback onTap;
  final VoidCallback onCollect;
  const _TxnCard({required this.item, required this.onTap, required this.onCollect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            InitialsAvatar(name: item.name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.ink)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: item.color)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.isDue)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatCurrency(item.amount)} due',
                    style: AppTheme.numberStyle(fontSize: 15, fontWeight: FontWeight.w800, color: item.color)),
                  const SizedBox(height: 6),
                  PillButton(label: 'Collect', onTap: onCollect),
                ],
              )
            else
              Text(
                '+${formatCurrency(item.amount)}',
                style: AppTheme.numberStyle(fontSize: 15, fontWeight: FontWeight.w800, color: item.color),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Record Payment Sheet ──────────────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final Invoice invoice;
  const _RecordPaymentSheet({required this.invoice});

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('upi', 'UPI', Icons.qr_code_outlined),
    ('bank_transfer', 'Bank Transfer', Icons.account_balance_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
  ];

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      // currentUser can be null if the session expired mid-screen; guard it
      // so we show a clear message rather than a force-unwrap crash.
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please sign in again.')),
          );
          setState(() => _loading = false);
        }
        return;
      }
      final inv = widget.invoice;

      // 1. Record the payment in the ledger (matches the web flow).
      await client.from('payments').insert({
        'invoice_id': inv.id,
        'amount': inv.amount,
        'method': _method,
        'status': 'succeeded',
        'reference_no': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'recorded_by': userId,
      });

      // 2. Mark the invoice paid.
      await client.from('invoices').update({
        'status': 'paid',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', inv.id);

      // 3. Advance the member's next payment date and lift any freeze.
      final memberRow = await client
          .from('members')
          .select('next_payment_date, status, billing_interval_months')
          .eq('id', inv.memberId)
          .maybeSingle();
      if (memberRow != null) {
        final updates = <String, dynamic>{};
        final npd = memberRow['next_payment_date'] as String?;
        if (npd != null) {
          final advanced = advancePaymentDate(
            npd,
            months: (memberRow['billing_interval_months'] as int?) ?? 1,
          );
          if (advanced != null) updates['next_payment_date'] = advanced;
        }
        if (memberRow['status'] == 'frozen' || memberRow['status'] == 'expired') updates['status'] = 'active';
        if (updates.isNotEmpty) {
          await client.from('members').update(updates).eq('id', inv.memberId);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded'), backgroundColor: AppTheme.statusActive),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] RecordPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to record payment. Please try again.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodIndex = _methods.indexWhere((m) => m.$1 == _method).clamp(0, _methods.length - 1);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: 'Record payment',
              subtitle: '${widget.invoice.member?.fullName ?? 'Member'}'
                  '${widget.invoice.description != null ? ' · ${widget.invoice.description}' : ''}',
            ),
            const SizedBox(height: 18),
            const FieldLabel('Amount'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: AppTheme.cardDecoration(),
              child: Text(formatCurrency(widget.invoice.amount),
                  style: AppTheme.numberStyle(fontSize: 22)),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Method'),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _methods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => PillChip(
                  label: _methods[i].$2,
                  selected: methodIndex == i,
                  onTap: () => setState(() => _method = _methods[i].$1),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FieldLabel(switch (_method) {
              'upi' => 'UPI transaction ID (optional)',
              'bank_transfer' => 'UTR number (optional)',
              _ => 'Reference / receipt no. (optional)',
            }),
            TextFormField(controller: _refCtrl),
            const SizedBox(height: 14),
            const FieldLabel('Notes (optional)'),
            TextFormField(controller: _notesCtrl, maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Record ${formatCurrency(widget.invoice.amount)}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create Invoice Sheet ──────────────────────────────────────────────────────

class _CreateInvoiceSheet extends ConsumerStatefulWidget {
  const _CreateInvoiceSheet();

  @override
  ConsumerState<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends ConsumerState<_CreateInvoiceSheet> {
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedMemberId;
  String? _dueAt;
  String? _planHint;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // Pre-fill amount from the member's active plan and due date from their
  // next_payment_date — mirrors the web create-invoice dialog.
  Future<void> _autofill(String memberId) async {
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
          _planHint = '${plan['name']} — $currencySymbol$price';
        }
        final npd = data['next_payment_date'] as String?;
        if (npd != null) _dueAt = npd.split('T').first;
      });
    } catch (e) {
      debugPrint('[GymCRM] RecordPayment autofill error: $e');
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dueAt = picked.toIso8601String().split('T')[0]);
    }
  }

  Future<void> _create() async {
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a member first')));
      return;
    }
    if (_amountCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final originalAmount = double.parse(_amountCtrl.text.trim());
      final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
      final finalAmount = (originalAmount - discountAmount).clamp(0.0, double.infinity);

      await client.from('invoices').insert({
        'member_id': _selectedMemberId,
        'gym_id': gymId,
        'original_amount': originalAmount,
        'discount_amount': discountAmount,
        'amount': finalAmount,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_dueAt != null) 'due_at': _dueAt,
        'status': 'open',
      });

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
    final members = ref.watch(_membersListProvider);

    final originalAmount = double.tryParse(_amountCtrl.text.trim());
    final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
    final total = originalAmount == null ? null : (originalAmount - discountAmount).clamp(0.0, double.infinity);

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
            const SheetHeader(title: 'Create invoice'),
            const SizedBox(height: 18),
            const FieldLabel('Member'),
            members.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (list) => DropdownButtonFormField<String>(
                value: _selectedMemberId,
                isExpanded: true,
                hint: const Text('Select member'),
                items: list.map((m) {
                  final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
                  return DropdownMenuItem(value: m['id'] as String, child: Text(name));
                }).toList(),
                onChanged: (v) {
                  setState(() => _selectedMemberId = v);
                  if (v != null) _autofill(v);
                },
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Amount'),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text('Auto-filled from active plan: $_planHint',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Discount (optional)'),
            TextFormField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Description (optional)'),
            TextFormField(controller: _descCtrl),
            const SizedBox(height: 16),
            if (total != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: AppTheme.cardDecoration(),
                child: Column(children: [
                  Row(children: [
                    const Text('Amount', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                    const Spacer(),
                    Text(formatCurrency(originalAmount!), style: const TextStyle(fontSize: 13, color: AppTheme.ink)),
                  ]),
                  if (discountAmount > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Discount', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                      const Spacer(),
                      Text('− ${formatCurrency(discountAmount)}', style: const TextStyle(fontSize: 13, color: AppTheme.statusActive)),
                    ]),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    const Spacer(),
                    Text(formatCurrency(total), style: AppTheme.numberStyle(fontSize: 16)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            const FieldLabel('Due date (optional)'),
            InkWell(
              onTap: _pickDueDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  suffixIcon: _dueAt != null
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _dueAt = null))
                      : const Icon(Icons.calendar_today_outlined, size: 16),
                ),
                child: Text(
                  _dueAt != null ? formatDateFromString(_dueAt) : 'Select date',
                  style: TextStyle(color: _dueAt != null ? AppTheme.ink : AppTheme.inkHint),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create & send invoice'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── WhatsApp Invoice Button ───────────────────────────────────────────────────

class _WhatsAppInvoiceButton extends StatefulWidget {
  final Invoice invoice;
  const _WhatsAppInvoiceButton({required this.invoice});

  @override
  State<_WhatsAppInvoiceButton> createState() => _WhatsAppInvoiceButtonState();
}

class _WhatsAppInvoiceButtonState extends State<_WhatsAppInvoiceButton> {
  bool _loading = false;

  Future<void> _share() async {
    final phone = widget.invoice.member?.phone ?? '';
    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this member. Add it in their profile first.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // 1. Fetch full invoice data (gym header needed for PDF)
      final data = await client
          .from('invoices')
          .select('*, members(first_name, last_name, email, phone), gyms(name, settings)')
          .eq('id', widget.invoice.id)
          .single();

      // 2. Generate PDF bytes
      final bytes  = await buildInvoicePdf(data);
      final invNum = invoiceNumber(widget.invoice.id, widget.invoice.createdAt);

      // 3. Upload to Supabase Storage (upsert so same invoice never duplicates)
      await client.storage.from('invoice-pdfs').uploadBinary(
        '${widget.invoice.id}.pdf',
        bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
      );

      // 4. Get public download URL
      final downloadUrl = client.storage
          .from('invoice-pdfs')
          .getPublicUrl('${widget.invoice.id}.pdf');

      // 5. Build WhatsApp message with download link
      final name   = widget.invoice.member?.fullName ?? 'there';
      final amount = formatCurrency(widget.invoice.amount);
      final text   = widget.invoice.status == 'paid'
          ? 'Hi $name, we have received your payment of $amount for invoice $invNum. Download your receipt here: $downloadUrl'
          : 'Hi $name, your invoice $invNum for $amount is due. Download it here: $downloadUrl';

      // 6. Open WhatsApp directly to member's chat
      final clean  = phone.replaceAll(RegExp(r'\D'), '');
      final number = clean.startsWith('91') ? clean : '91$clean';
      final uri    = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open WhatsApp')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate or upload invoice PDF')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _share,
        icon: _loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25D366)),
              )
            : const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF25D366)),
        label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF25D366),
          side: const BorderSide(color: Color(0xFF25D366)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── Plans Tab ─────────────────────────────────────────────────────────────────

class _PlansTab extends ConsumerWidget {
  const _PlansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(_plansProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Plans & pricing'), leading: const BackButton()),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(_plansProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No plans yet', style: TextStyle(color: AppTheme.inkHint, fontSize: 14))),
                )
              else
                CardList(
                  children: list.map((plan) => _PlanCard(
                    plan: plan,
                    onEdit: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => PlanFormSheet(plan: plan),
                    ).then((_) => ref.invalidate(_plansProvider)),
                  )).toList(),
                ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const PlanFormSheet(),
                ).then((_) => ref.invalidate(_plansProvider)),
                child: DottedBorderBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add, size: 18, color: AppTheme.accent),
                      SizedBox(width: 6),
                      Text('Add new plan',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onEdit;
  const _PlanCard({required this.plan, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final features = List<String>.from(plan['features'] ?? []);
    final interval = plan['billing_interval'] as String;
    final months = plan['billing_interval_months'] as int?;
    final intervalLabel = interval == 'custom' && months != null ? '$months months' : interval;
    final isActive = plan['is_active'] as bool? ?? true;

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppTheme.ink),
                      ),
                      const SizedBox(height: 3),
                      if (plan['max_classes'] != null)
                        Text('Up to ${plan['max_classes']} classes',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(children: [
                    Text(formatCurrency(plan['price'] as num), style: AppTheme.numberStyle(fontSize: 15)),
                    Text(' / $intervalLabel',
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                  ]),
                  const SizedBox(height: 4),
                  isActive ? StatusPill.active() : StatusPill.neutral(label: 'Inactive'),
                ]),
              ],
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 14, color: AppTheme.statusActive),
                        const SizedBox(width: 6),
                        Text(f, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Plan Form Sheet ───────────────────────────────────────────────────────────

/// Create/edit a membership plan. Public because the add-member sheet opens it
/// inline when a gym has no plans yet — on create it pops the new plan row so
/// the caller can select it without a round-trip.
class PlanFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? plan;
  const PlanFormSheet({super.key, this.plan});

  @override
  ConsumerState<PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends ConsumerState<PlanFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _maxClassesCtrl;
  late final TextEditingController _monthsCtrl;
  late final TextEditingController _featureCtrl;

  String _interval = 'monthly';
  bool _isActive = true;
  List<String> _features = [];
  bool _loading = false;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _priceCtrl = TextEditingController(text: p != null ? (p['price'] as num).toString() : '');
    _maxClassesCtrl = TextEditingController(text: p?['max_classes']?.toString() ?? '');
    _monthsCtrl = TextEditingController(text: p?['billing_interval_months']?.toString() ?? '');
    _featureCtrl = TextEditingController();
    _interval = p?['billing_interval'] as String? ?? 'monthly';
    _isActive = p?['is_active'] as bool? ?? true;
    _features = List<String>.from(p?['features'] ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _priceCtrl.dispose(); _maxClassesCtrl.dispose();
    _monthsCtrl.dispose(); _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final f = _featureCtrl.text.trim();
    if (f.isEmpty) return;
    setState(() { _features.add(f); _featureCtrl.clear(); });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'billing_interval': _interval,
        if (_interval == 'custom' && _monthsCtrl.text.trim().isNotEmpty)
          'billing_interval_months': int.parse(_monthsCtrl.text.trim()),
        'features': _features,
        if (_maxClassesCtrl.text.trim().isNotEmpty)
          'max_classes': int.parse(_maxClassesCtrl.text.trim()),
        'is_active': _isActive,
      };

      Map<String, dynamic>? created;
      if (_isEdit) {
        await client.from('membership_plans').update(data).eq('id', widget.plan!['id']);
      } else {
        data['gym_id'] = await ref.read(gymIdProvider.future);
        created = await client
            .from('membership_plans')
            .insert(data)
            .select('id, name, price, billing_interval, billing_interval_months')
            .single();
      }

      if (mounted) Navigator.pop(context, created);
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title: _isEdit ? 'Edit plan' : 'New plan'),
              const SizedBox(height: 18),
              const FieldLabel('Plan name'),
              TextFormField(
                controller: _nameCtrl,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Price'),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(prefixText: '$currencySymbol '),
                      validator: (v) {
                        if (v?.trim().isEmpty ?? true) return 'Required';
                        if (double.tryParse(v!) == null) return 'Enter a valid price';
                        return null;
                      },
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Duration'),
                    DropdownButtonFormField<String>(
                      value: _interval,
                      items: const [
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                        DropdownMenuItem(value: 'biannual', child: Text('6 months')),
                        DropdownMenuItem(value: 'annual', child: Text('Yearly')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom…')),
                      ],
                      onChanged: (v) => setState(() => _interval = v!),
                    ),
                  ]),
                ),
              ]),
              if (_interval == 'custom') ...[
                const SizedBox(height: 14),
                const FieldLabel('Duration (months)'),
                TextFormField(
                  controller: _monthsCtrl,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_interval != 'custom') return null;
                    if (v?.trim().isEmpty ?? true) return 'Required for custom interval';
                    if (int.tryParse(v!) == null || int.parse(v) < 1) return 'Enter a positive number';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 14),
              const FieldLabel('Max classes (blank = unlimited)'),
              TextFormField(controller: _maxClassesCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 18),
              const FieldLabel('Includes'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _featureCtrl,
                      decoration: const InputDecoration(hintText: 'Add a feature', isDense: true),
                      onFieldSubmitted: (_) => _addFeature(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(icon: Icons.add, onTap: _addFeature, bg: AppTheme.accentSoft, fg: AppTheme.accent),
                ],
              ),
              if (_features.isNotEmpty)
                CardList(
                  children: _features.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.check, size: 15, color: AppTheme.statusActive),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13.5, color: AppTheme.ink))),
                      GestureDetector(
                        onTap: () => setState(() => _features.removeAt(e.key)),
                        child: const Icon(Icons.close, size: 16, color: AppTheme.inkHint),
                      ),
                    ]),
                  )).toList(),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeColor: AppTheme.accent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
