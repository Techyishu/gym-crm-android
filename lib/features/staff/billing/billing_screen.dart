import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/access/gym_permissions.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/services/app_events.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/invoice_pdf.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../members/upcoming_payments_screen.dart' show QuickCollectSheet;
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

final _plansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  return await client
      .from('membership_plans')
      .select()
      .eq('gym_id', gymId)
      .order('price');
});

final _membersListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
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

// "To collect" always shows overdue members plus anyone due within this
// many days — no filter toggle, just one fixed window. Bounds how far past
// today the dues/renewals queries fetch.
const _collectWindowDays = 7;

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
  final statsFrom = prevMonthStart.isBefore(prevWeekStart)
      ? prevMonthStart
      : prevWeekStart;

  final results = await Future.wait([
    // Recent payments feed (with member/method info for display) — widened to
    // the start of the month so the Today/Week/Month toggle always has data.
    client
        .from('payments')
        .select(
          'amount, method, created_at, invoice_id, invoices!inner(gym_id, members(first_name, last_name))',
        )
        .eq('invoices.gym_id', gymId)
        .eq('status', 'succeeded')
        .gte('created_at', startOfMonth.toIso8601String())
        .order('created_at', ascending: false),
    // A partial invoice is a real outstanding balance and must always stay
    // visible, regardless of its renewal date. An untouched open invoice is
    // only a collection item once it is due within the short collection
    // window; that prevents 102-day-away renewals looking collectible today.
    client
        .from('invoices')
        .select(
          'id, amount, status, due_at, member_id, members(first_name, last_name, email, phone, next_payment_date, memberships(status, membership_plans(name))), payments(amount, status)',
        )
        .eq('gym_id', gymId)
        .inFilter('status', ['open', 'partial'])
        .or(
          'status.eq.partial,due_at.lt.${startOfToday.add(const Duration(days: _collectWindowDays + 1)).toIso8601String()}',
        )
        .order('due_at'),
    // Wider-range, lightweight payments for the today/week/month sums.
    client
        .from('payments')
        .select('amount, created_at, invoices!inner(gym_id)')
        .eq('invoices.gym_id', gymId)
        .eq('status', 'succeeded')
        .gte('created_at', statsFrom.toIso8601String()),
    // Members whose renewal falls due soon but don't have an open invoice
    // yet — Collect on these creates the invoice on the spot. Same
    // _collectWindowDays cap as above and the same rule: only the overdue
    // subset feeds the "Amount due" figures.
    client
        .from('members')
        .select(
          'id, first_name, last_name, phone, next_payment_date, memberships(status, discount_amount, membership_plans(price, name))',
        )
        .eq('gym_id', gymId)
        .not('status', 'eq', 'cancelled')
        .lte(
          'next_payment_date',
          startOfToday
              .add(const Duration(days: _collectWindowDays))
              .toIso8601String()
              .split('T')
              .first,
        )
        .order('next_payment_date'),
  ]);

  final payments = (results[0] as List).cast<Map<String, dynamic>>();
  // Each due row still carries its true invoice 'amount' (needed intact when
  // Collect opens _RecordPaymentSheet) plus the joined 'payments' rows —
  // _TxnItem.due() computes the remaining balance for display separately.
  final dues = (results[1] as List)
      .cast<Map<String, dynamic>>()
      // A zero balance is not actionable. Showing it with a Collect button
      // makes the owner doubt every number on this page.
      .where((invoice) => _remainingDue(invoice) > 0)
      .toList();
  final statsPayments = (results[2] as List).cast<Map<String, dynamic>>();
  final renewingMembers = (results[3] as List).cast<Map<String, dynamic>>();
  final invoicedMemberIds = dues.map((d) => d['member_id']).toSet();
  final projected = renewingMembers.where(
    (m) => !invoicedMemberIds.contains(m['id']) && _activePlanPrice(m) > 0,
  );
  bool isOverdueOrToday(DateTime? due) => due != null && !due.isAfter(now);
  final overdueDues = dues.where(
    (d) => isOverdueOrToday(DateTime.tryParse(d['due_at'] as String? ?? '')),
  );
  final overdueProjected = projected.where(
    (m) => isOverdueOrToday(
      DateTime.tryParse(m['next_payment_date'] as String? ?? ''),
    ),
  );

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

  // "Amount due" and the overdue/member counts below deliberately use only
  // the overdue-or-today subset, never the full (bucket-widened) dues/
  // projected lists — otherwise the summary card would silently start
  // counting members who aren't actually due yet again.
  final invoicedTotal = overdueDues.fold<double>(
    0,
    (s, d) => s + _remainingDue(d),
  );
  final projectedTotal = overdueProjected.fold<double>(
    0,
    (s, m) => s + _activePlanPrice(m),
  );
  final overdueCount = overdueDues.length + overdueProjected.length;

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
    dueCount: overdueCount,
    dueTotal: invoicedTotal + projectedTotal,
    dueMembers:
        overdueDues.map((d) => d['member_id']).toSet().length +
        overdueProjected.length,
    overdueCount: overdueCount,
    items: items,
  );
});

// Remaining balance on an invoice row (as fetched with a joined 'payments'
// list) — invoice amount minus whatever's already been collected against it.
double _remainingDue(Map<String, dynamic> invoice) {
  final amount = (invoice['amount'] as num?)?.toDouble() ?? 0;
  final invPayments = (invoice['payments'] as List?) ?? const [];
  final paid = invPayments
      .where((p) => (p as Map)['status'] == 'succeeded')
      .fold<double>(0, (s, p) => s + ((p as Map)['amount'] as num).toDouble());
  return (amount - paid).clamp(0, amount);
}

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

  /// Dues-queue extras — the canvas row reads
  /// "Monthly · overdue 15 days · exp 26 Sep".
  final String planName;
  final DateTime? expiry;
  final String phone;

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
    this.planName = '',
    this.expiry,
    this.phone = '',
  });

  // Days past the due date, 0 when not yet overdue.
  int get overdueDays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(sortKey.year, sortKey.month, sortKey.day);
    final diff = today.difference(date).inDays;
    return diff > 0 ? diff : 0;
  }

  bool get isOverdue => isDue && !isUpcoming;

  // "Monthly · overdue 15 days · exp 26 Sep" — every part optional, because
  // a projected renewal and a partial invoice carry different fields.
  String get duesLine {
    final parts = <String>[
      if (planName.isNotEmpty) planName,
      if (isPartial) 'partially paid',
      if (overdueDays > 0)
        'overdue $overdueDays day${overdueDays == 1 ? '' : 's'}'
      else if (isUpcoming)
        'due ${DateFormat('d MMM').format(sortKey)}'
      else
        'due today',
      if (expiry != null) 'exp ${DateFormat('d MMM').format(expiry!)}',
    ];
    return parts.join(' · ');
  }

  // Active plan name off a joined memberships list (invoice or member row).
  static String _planNameOf(Map<String, dynamic>? source) {
    final memberships = (source?['memberships'] as List?) ?? const [];
    for (final m in memberships) {
      final map = (m as Map).cast<String, dynamic>();
      if (map['status'] != 'active') continue;
      final plan = map['membership_plans'] as Map?;
      final name = plan?['name'] as String?;
      if (name != null && name.isNotEmpty) return name;
    }
    return '';
  }

  // No invoice exists yet for this due — Collect creates one on the spot.
  bool get needsInvoice => isDue && invoiceId.isEmpty;
  bool get isPartial => raw['status'] == 'partial';
  bool get isUpcoming {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(sortKey.year, sortKey.month, sortKey.day);
    return isDue && date.isAfter(today);
  }

  static ({String subtitle, Color color}) _dueSubtitle(DateTime? due) {
    if (due == null) return (subtitle: 'Due', color: AppTheme.statusWarn);
    final days = due.difference(DateTime.now()).inDays;
    if (days < 0)
      return (
        subtitle: '${days.abs()} day${days == -1 ? '' : 's'} overdue',
        color: AppTheme.statusDanger,
      );
    if (days == 0) return (subtitle: 'Due today', color: AppTheme.statusWarn);
    return (
      subtitle: 'Upcoming in $days day${days == 1 ? '' : 's'}',
      color: AppTheme.statusWarn,
    );
  }

  factory _TxnItem.payment(Map<String, dynamic> p) {
    final invoice = p['invoices'] as Map<String, dynamic>?;
    final member = invoice?['members'] as Map<String, dynamic>?;
    final created =
        DateTime.tryParse(p['created_at'] as String? ?? '') ?? DateTime.now();
    final method = (p['method'] as String?)?.replaceAll('_', ' ') ?? '';
    final methodLabel = method.isEmpty
        ? 'Payment'
        : method[0].toUpperCase() + method.substring(1);
    return _TxnItem._(
      isDue: false,
      invoiceId: p['invoice_id'] as String? ?? '',
      name: member != null
          ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim()
          : 'Unknown',
      amount: (p['amount'] as num?)?.toDouble() ?? 0,
      subtitle:
          '$methodLabel · ${DateFormat('d MMM, h:mm a').format(created.toLocal())}',
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
      name: member != null
          ? '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim()
          : 'Unknown',
      amount: _remainingDue(inv),
      subtitle: inv['status'] == 'partial'
          ? 'Partially paid · ${s.subtitle}'
          : s.subtitle,
      color: s.color,
      sortKey: due ?? DateTime.now(),
      raw: inv,
      planName: _planNameOf(member),
      expiry: DateTime.tryParse(member?['next_payment_date'] as String? ?? ''),
      phone: member?['phone'] as String? ?? '',
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
      planName: _planNameOf(member),
      expiry: due,
      phone: member['phone'] as String? ?? '',
    );
  }
}

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  // Dues · Payments · Invoices · Plans
  static const _tabs = ['Dues', 'Payments', 'Invoices', 'Plans'];
  int _tab = 0;

  // Sub-filter inside the Dues tab: 'overdue' | 'week' | 'all'.
  String _bucket = 'overdue';

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(_billingFeedProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Money',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    feed.when(
                      loading: () => const _BalanceCardSkeleton(),
                      error: (_, _) => const _BalanceCardSkeleton(),
                      data: (data) => _BalanceCard(
                        dueTotal: data.dueTotal,
                        dueMembers: data.dueMembers,
                        collectedMonth:
                            data.collected[BillingPeriod.month] ?? 0,
                        onDue: () => setState(() {
                          _tab = 0;
                          _bucket = 'overdue';
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                    UnderlineTabs(
                      tabs: _tabs,
                      selectedIndex: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _tab == 3
                    ? const _PlansBody()
                    : RefreshIndicator(
                        color: AppTheme.accent,
                        onRefresh: () async =>
                            ref.invalidate(_billingFeedProvider),
                        child: feed.when(
                          loading: _loadingList,
                          error: (_, _) => ListView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                            children: [
                              StateMessage(
                                icon: AppIcons.cloudOff,
                                tint: AppTheme.statusDanger,
                                tintBg: AppTheme.statusDangerBg,
                                title: 'Could not load payments',
                                body:
                                    'Check your connection, then pull down to retry.',
                                actionLabel: 'Retry',
                                onAction: () =>
                                    ref.invalidate(_billingFeedProvider),
                              ),
                            ],
                          ),
                          data: (data) => _tab == 0
                              ? _duesTab(context, data)
                              : _ledgerTab(context, data),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
    itemCount: 6,
    itemBuilder: (_, _) => Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
  );

  // ── Dues queue ────────────────────────────────────────────────────────────

  Widget _duesTab(BuildContext context, _BillingFeed data) {
    final all = data.items.where((t) => t.isDue).toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final overdue = all.where((t) => t.isOverdue).toList();
    final week = all.where((t) => t.isUpcoming).toList();
    final rows = switch (_bucket) {
      'overdue' => overdue,
      'week' => week,
      _ => all,
    };

    final canCollect = ref.watch(
      gymPermissionProvider((GymModule.payments, GymAction.add)),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Row(
          children: [
            PillChip(
              label: 'Overdue ${overdue.length}',
              selected: _bucket == 'overdue',
              onTap: () => setState(() => _bucket = 'overdue'),
            ),
            const SizedBox(width: 8),
            PillChip(
              label: 'Due this week ${week.length}',
              selected: _bucket == 'week',
              onTap: () => setState(() => _bucket = 'week'),
            ),
            const SizedBox(width: 8),
            PillChip(
              label: 'All ${all.length}',
              selected: _bucket == 'all',
              onTap: () => setState(() => _bucket = 'all'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          StateMessage(
            icon: AppIcons.checkCircle,
            tint: AppTheme.statusActive,
            tintBg: AppTheme.statusActiveBg,
            title: 'Everyone has paid',
            body:
                'No outstanding dues today. Renewals due this week will show '
                'up here.',
            actionLabel: 'See upcoming renewals',
            onAction: () => context.push('/staff/upcoming-payments'),
          )
        else
          CardList(
            children: [
              for (final item in rows)
                _DueRow(
                  item: item,
                  onCollect: canCollect ? () => _collect(context, item) : null,
                ),
            ],
          ),
      ],
    );
  }

  // ── Payments / Invoices ledgers ───────────────────────────────────────────

  Widget _ledgerTab(BuildContext context, _BillingFeed data) {
    // Payments = money already collected. Invoices = the invoice records
    // themselves, i.e. open/partial bills (projected renewals have no
    // invoice row yet, so they only ever appear in Dues).
    final items = _tab == 1
        ? data.items.where((t) => !t.isDue).toList()
        : data.items.where((t) => t.isDue && t.invoiceId.isNotEmpty).toList();

    final canAdd = ref.watch(
      gymPermissionProvider((GymModule.payments, GymAction.add)),
    );
    final canDelete = ref.watch(
      gymPermissionProvider((GymModule.payments, GymAction.delete)),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_tab == 2 && canAdd) ...[
          GestureDetector(
            onTap: () => _showCreateInvoiceSheet(context),
            child: DottedBorderBox(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(AppIcons.add, size: 18, color: AppTheme.accent),
                  SizedBox(width: 6),
                  Text(
                    'New invoice',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (items.isEmpty)
          StateMessage(
            icon: AppIcons.receipt,
            title: 'Nothing here yet',
            body: _tab == 1
                ? 'Payments appear here as soon as you record the first one.'
                : 'Invoices you raise appear here.',
          )
        else
          for (final item in items)
            _TxnCard(
              item: item,
              onTap: () => _openInvoice(context, item),
              onCollect: canAdd ? () => _collect(context, item) : null,
              onDelete: canDelete && item.invoiceId.isNotEmpty
                  ? () => _deleteInvoice(context, item)
                  : null,
            ),
      ],
    );
  }

  void _openInvoice(BuildContext context, _TxnItem item) {
    if (item.invoiceId.isEmpty) return;
    context.push('/invoice/${item.invoiceId}');
  }

  Future<void> _deleteInvoice(BuildContext context, _TxnItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete invoice?',
      body:
          'This invoice and its payment records will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: AppIcons.delete,
    );
    if (ok != true) return;
    await Supabase.instance.client
        .from('invoices')
        .delete()
        .eq('id', item.invoiceId);
    ref.invalidate(_billingFeedProvider);
  }

  void _collect(BuildContext context, _TxnItem item) {
    if (item.needsInvoice) {
      // No invoice exists yet for this renewal — QuickCollectSheet creates
      // one and records the payment in a single step.
      showAdaptiveSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            QuickCollectSheet(memberId: item.memberId!, memberName: item.name),
      ).then((_) => ref.invalidate(_billingFeedProvider));
      return;
    }
    final invoice = Invoice.fromJson(item.raw);
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecordPaymentSheet(invoice: invoice),
    ).then((_) => ref.invalidate(_billingFeedProvider));
  }

  void _showCreateInvoiceSheet(BuildContext context) {
    showAdaptiveSheet(
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
  final double collectedMonth;
  final VoidCallback onDue;
  const _BalanceCard({
    required this.dueTotal,
    required this.dueMembers,
    required this.collectedMonth,
    required this.onDue,
  });

  @override
  Widget build(BuildContext context) {
    final collectionRate = (collectedMonth + dueTotal) > 0
        ? (collectedMonth / (collectedMonth + dueTotal) * 100).round()
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.darkCardDecoration(radius: 18),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onDue,
                behavior: HitTestBehavior.opaque,
                child: _HeroFigure(
                  label: 'TO COLLECT',
                  value: formatCurrency(dueTotal),
                  valueColor: AppTheme.onDark,
                  caption: '$dueMembers member${dueMembers == 1 ? '' : 's'}',
                ),
              ),
            ),
            const VerticalDivider(width: 29, color: AppTheme.darkCard2),
            Expanded(
              child: _HeroFigure(
                label:
                    'COLLECTED · ${DateFormat('MMM').format(DateTime.now()).toUpperCase()}',
                value: formatCurrency(collectedMonth),
                valueColor: AppTheme.mintOnDark,
                caption: collectionRate != null
                    ? '$collectionRate% collection rate'
                    : 'No dues outstanding',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One side of the money hero: kicker, figure, one line of context.
class _HeroFigure extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String caption;
  const _HeroFigure({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppTheme.onDarkSoft,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppTheme.numberStyle(fontSize: 24, color: valueColor),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppTheme.onDarkSoft),
        ),
      ],
    );
  }
}

class _BalanceCardSkeleton extends StatelessWidget {
  const _BalanceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      decoration: AppTheme.darkCardDecoration(radius: 18),
    );
  }
}

// ── Transaction Card ─────────────────────────────────────────────────────────

class _TxnCard extends StatelessWidget {
  final _TxnItem item;
  final VoidCallback onTap;
  final VoidCallback? onCollect;
  final VoidCallback? onDelete;
  const _TxnCard({
    required this.item,
    required this.onTap,
    required this.onCollect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialsAvatar(name: item.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: item.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.isDue
                      ? '${formatCurrency(item.amount)} ${item.isUpcoming ? 'upcoming' : 'due'}'
                      : '+${formatCurrency(item.amount)}',
                  style: AppTheme.numberStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: item.color,
                  ),
                ),
              ],
            ),
            if (item.isDue && onCollect != null) ...[
              const SizedBox(height: 12),
              WideActionButton(
                label: item.isUpcoming ? 'Collect early' : 'Collect',
                onTap: onCollect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Dues queue row (Collect) ────────────────────────────────────────────────

class _DueRow extends StatelessWidget {
  final _TxnItem item;
  final VoidCallback? onCollect;
  const _DueRow({required this.item, required this.onCollect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(name: item.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.duesLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatCurrency(item.amount),
                style: AppTheme.numberStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: item.color,
                ),
              ),
            ],
          ),
          if (onCollect != null) ...[
            const SizedBox(height: 12),
            WideActionButton(
              label: item.isUpcoming ? 'Collect early' : 'Collect',
              onTap: onCollect,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Record Payment Sheet ──────────────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final Invoice invoice;
  const _RecordPaymentSheet({required this.invoice});

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;
  double? _due;

  static const _methods = [
    ('cash', 'Cash', AppIcons.payments),
    ('upi', 'UPI', AppIcons.qrCode),
    ('bank_transfer', 'Bank Transfer', AppIcons.accountBalance),
    ('card', 'Card', AppIcons.creditCard),
  ];

  @override
  void initState() {
    super.initState();
    _loadDue();
  }

  Future<void> _loadDue() async {
    final due = await invoiceDue(widget.invoice.id, widget.invoice.amount);
    if (!mounted) return;
    setState(() {
      _due = due;
      _amountCtrl.text = due.toStringAsFixed(0);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final inv = widget.invoice;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    final early = await confirmEarlyRenewalIfNeeded(
      context,
      nextPaymentDate: inv.dueAt,
      settlingPartialInvoice: (_due ?? inv.amount) < inv.amount,
    );
    if (!early) return;

    // Only a genuine duplicate is worth stopping. A balance still owed on this
    // invoice means a second collection today is the rest of the same bill —
    // an instalment, not an accidental re-tap.
    final prior = (_due ?? 0) > 0
        ? null
        : await LocalPaymentGuard.check(inv.memberId);
    if (prior != null && mounted) {
      final proceed = await showConfirmDialog(
        context,
        title: 'Already collected today',
        body:
            '$currencySymbol${prior.amount.toStringAsFixed(0)} was already collected '
            'from this member today at '
            '${prior.at.hour.toString().padLeft(2, '0')}:${prior.at.minute.toString().padLeft(2, '0')}.\n\n'
            'Record $currencySymbol${amount.toStringAsFixed(0)} again?',
        confirmLabel: 'Record anyway',
        icon: AppIcons.history,
        danger: false,
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    final ok = await confirmPartialIfNeeded(
      context,
      enteredAmount: amount,
      dueAmount: _due ?? inv.amount,
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      // currentUser can be null if the session expired mid-screen; guard it
      // so we show a clear message rather than a force-unwrap crash.
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please sign in again.'),
            ),
          );
          setState(() => _loading = false);
        }
        return;
      }

      final memberRow = await client
          .from('members')
          .select('next_payment_date')
          .eq('id', inv.memberId)
          .maybeSingle();
      final nextPaymentDate = memberRow?['next_payment_date'] as String?;
      final invoiceDueDate = inv.dueAt?.split('T').first;
      final renewalDate = nextPaymentDate?.split('T').first;

      // A membership-renewal invoice advances the plan date inside the same
      // locked transaction. A manually created invoice records only its own
      // payment and must not move the membership schedule.
      if (invoiceDueDate != null && invoiceDueDate == renewalDate) {
        await collectMembershipRenewal(
          memberId: inv.memberId,
          expectedNextPaymentDate: renewalDate!,
          amount: amount,
          method: _method,
          referenceNo: _refCtrl.text.trim().isEmpty
              ? null
              : _refCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          invoiceId: inv.id,
        );
      } else {
        await recordInvoicePayment(
          invoiceId: inv.id,
          amount: amount,
          method: _method,
          referenceNo: _refCtrl.text.trim().isEmpty
              ? null
              : _refCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          recordedBy: userId,
        );
      }

      await LocalPaymentGuard.record(inv.memberId, amount);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded'),
            backgroundColor: AppTheme.statusActive,
          ),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] RecordPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(paymentFailureMessage(e))));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodIndex = _methods
        .indexWhere((m) => m.$1 == _method)
        .clamp(0, _methods.length - 1);
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
            SheetHeader(
              title: 'Record payment',
              subtitle:
                  '${widget.invoice.member?.fullName ?? 'Member'}'
                  '${widget.invoice.description != null ? ' · ${widget.invoice.description}' : ''}',
            ),
            const SizedBox(height: 18),
            const FieldLabel('Amount'),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
              style: AppTheme.numberStyle(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              partialPaymentHint,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
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
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Record payment'),
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
  ConsumerState<_CreateInvoiceSheet> createState() =>
      _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends ConsumerState<_CreateInvoiceSheet> {
  final _amountCtrl = TextEditingController();
  final _admissionCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedMemberId;
  String? _dueAt;
  String? _planHint;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _admissionCtrl.dispose();
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
          .select(
            'next_payment_date, memberships(status, membership_plans(price, name))',
          )
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a member first')));
      return;
    }
    if (_amountCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final originalAmount = double.parse(_amountCtrl.text.trim());
      final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
      final admissionFee = double.tryParse(_admissionCtrl.text.trim()) ?? 0.0;

      await client.rpc(
        'create_invoice_secure',
        params: {
          'p_gym_id': gymId,
          'p_member_id': _selectedMemberId,
          'p_membership_amount': originalAmount,
          'p_discount_amount': discountAmount,
          'p_admission_fee': admissionFee,
          'p_description': _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          'p_due_at': _dueAt,
        },
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersListProvider);

    final originalAmount = double.tryParse(_amountCtrl.text.trim());
    final admissionFee = double.tryParse(_admissionCtrl.text.trim()) ?? 0.0;
    final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
    final total = originalAmount == null
        ? null
        : (originalAmount + admissionFee - discountAmount).clamp(
            0.0,
            double.infinity,
          );

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
                  final name =
                      '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
                  return DropdownMenuItem(
                    value: m['id'] as String,
                    child: Text(name),
                  );
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text(
                'Auto-filled from active plan: $_planHint',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Admission fee (optional)'),
            TextFormField(
              controller: _admissionCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Discount (optional)'),
            TextFormField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixText: '$currencySymbol '),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Description (optional)'),
            TextFormField(controller: _descCtrl),
            const SizedBox(height: 16),
            if (total != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Amount',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatCurrency(originalAmount!),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                    if (admissionFee > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            'Admission fee',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '+ ${formatCurrency(admissionFee)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (discountAmount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            'Discount',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.inkSoft,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '− ${formatCurrency(discountAmount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.statusActive,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    Row(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatCurrency(total),
                          style: AppTheme.numberStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
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
                      ? IconButton(
                          icon: const Icon(AppIcons.clear, size: 16),
                          onPressed: () => setState(() => _dueAt = null),
                        )
                      : const Icon(AppIcons.calendarToday, size: 16),
                ),
                child: Text(
                  _dueAt != null ? formatDateFromString(_dueAt) : 'Select date',
                  style: TextStyle(
                    color: _dueAt != null ? AppTheme.ink : AppTheme.inkHint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
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
        const SnackBar(
          content: Text(
            'No phone number saved for this member. Add it in their profile first.',
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // 1. Fetch full invoice data (gym header needed for PDF)
      final data = await client
          .from('invoices')
          .select(
            '*, members(first_name, last_name, email, phone), gyms(name, settings)',
          )
          .eq('id', widget.invoice.id)
          .single();

      // 2. Generate PDF bytes
      final bytes = await buildInvoicePdf(data);
      final invNum = invoiceNumber(
        widget.invoice.id,
        widget.invoice.createdAt,
        issuedNumber: widget.invoice.invoiceNumber,
      );

      // 3. Upload to Supabase Storage (upsert so same invoice never duplicates)
      await client.storage
          .from('invoice-pdfs')
          .uploadBinary(
            '${widget.invoice.id}.pdf',
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      // 4. Get public download URL
      final downloadUrl = client.storage
          .from('invoice-pdfs')
          .getPublicUrl('${widget.invoice.id}.pdf');

      // 5. Build WhatsApp message with download link
      final name = widget.invoice.member?.fullName ?? 'there';
      final amount = formatCurrency(widget.invoice.amount);
      final text = widget.invoice.status == 'paid'
          ? 'Hi $name, we have received your payment of $amount for invoice $invNum. Download your receipt here: $downloadUrl'
          : 'Hi $name, your invoice $invNum for $amount is due. Download it here: $downloadUrl';

      // 6. Open WhatsApp directly to member's chat
      final clean = phone.replaceAll(RegExp(r'\D'), '');
      final number = clean.startsWith('91') ? clean : '91$clean';
      final uri = Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
      );

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
          const SnackBar(
            content: Text('Could not generate or upload invoice PDF'),
          ),
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
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF25D366),
                ),
              )
            : const Icon(
                AppIcons.chat,
                size: 14,
                color: Color(0xFF25D366),
              ),
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

class _PlansBody extends ConsumerWidget {
  const _PlansBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(_plansProvider);

    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const ErrorState(what: 'plans'),
      data: (list) => RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async => ref.invalidate(_plansProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No plans yet',
                    style: TextStyle(color: AppTheme.inkHint, fontSize: 14),
                  ),
                ),
              )
            else
              CardList(
                children: list
                    .map(
                      (plan) => _PlanCard(
                        plan: plan,
                        onEdit: () => showAdaptiveSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => PlanFormSheet(plan: plan),
                        ).then((_) => ref.invalidate(_plansProvider)),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => showAdaptiveSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const PlanFormSheet(),
              ).then((_) => ref.invalidate(_plansProvider)),
              child: DottedBorderBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(AppIcons.add, size: 18, color: AppTheme.accent),
                    SizedBox(width: 6),
                    Text(
                      'Add new plan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final intervalLabel = interval == 'custom' && months != null
        ? '$months months'
        : interval;
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (plan['max_classes'] != null)
                        Text(
                          'Up to ${plan['max_classes']} classes',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Text(
                          formatCurrency(plan['price'] as num),
                          style: AppTheme.numberStyle(fontSize: 15),
                        ),
                        Text(
                          ' / $intervalLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    isActive
                        ? StatusPill.active()
                        : StatusPill.neutral(label: 'Inactive'),
                  ],
                ),
              ],
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        AppIcons.check,
                        size: 14,
                        color: AppTheme.statusActive,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        f,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ],
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
    _priceCtrl = TextEditingController(
      text: p != null ? (p['price'] as num).toString() : '',
    );
    _maxClassesCtrl = TextEditingController(
      text: p?['max_classes']?.toString() ?? '',
    );
    _monthsCtrl = TextEditingController(
      text: p?['billing_interval_months']?.toString() ?? '',
    );
    _featureCtrl = TextEditingController();
    _interval = p?['billing_interval'] as String? ?? 'monthly';
    _isActive = p?['is_active'] as bool? ?? true;
    _features = List<String>.from(p?['features'] ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _maxClassesCtrl.dispose();
    _monthsCtrl.dispose();
    _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final f = _featureCtrl.text.trim();
    if (f.isEmpty) return;
    setState(() {
      _features.add(f);
      _featureCtrl.clear();
    });
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
        await client
            .from('membership_plans')
            .update(data)
            .eq('id', widget.plan!['id']);
      } else {
        created = Map<String, dynamic>.from(
          await client.rpc(
                'create_membership_plan_secure',
                params: {
                  'p_gym_id': await ref.read(gymIdProvider.future),
                  'p_name': data['name'],
                  'p_price': data['price'],
                  'p_billing_interval': data['billing_interval'],
                  'p_features': data['features'],
                  'p_is_active': data['is_active'],
                  'p_billing_interval_months': data['billing_interval_months'],
                  'p_max_classes': data['max_classes'],
                },
              )
              as Map,
        );
      }

      if (created != null) unawaited(AppEvents.planCreated());
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete plan?',
      body:
          "This permanently deletes '${_nameCtrl.text.trim()}'. This can't be undone.",
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('membership_plans')
          .delete()
          .eq('id', widget.plan!['id']);
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.code == '23503'
            ? 'This plan has members assigned — deactivate it instead of deleting.'
            : 'Error: ${e.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
              SheetHeader(title: _isEdit ? 'Edit plan' : 'New plan'),
              const SizedBox(height: 18),
              const FieldLabel('Plan name'),
              TextFormField(
                controller: _nameCtrl,
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Price'),
                        TextFormField(
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            prefixText: '$currencySymbol ',
                          ),
                          validator: (v) {
                            if (v?.trim().isEmpty ?? true) return 'Required';
                            if (double.tryParse(v!) == null)
                              return 'Enter a valid price';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Duration'),
                        DropdownButtonFormField<String>(
                          value: _interval,
                          items: const [
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text('Monthly'),
                            ),
                            DropdownMenuItem(
                              value: 'quarterly',
                              child: Text('Quarterly'),
                            ),
                            DropdownMenuItem(
                              value: 'biannual',
                              child: Text('6 months'),
                            ),
                            DropdownMenuItem(
                              value: 'annual',
                              child: Text('Yearly'),
                            ),
                            DropdownMenuItem(
                              value: 'custom',
                              child: Text('Custom…'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _interval = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_interval == 'custom') ...[
                const SizedBox(height: 14),
                const FieldLabel('Duration (months)'),
                TextFormField(
                  controller: _monthsCtrl,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_interval != 'custom') return null;
                    if (v?.trim().isEmpty ?? true)
                      return 'Required for custom interval';
                    if (int.tryParse(v!) == null || int.parse(v) < 1)
                      return 'Enter a positive number';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 14),
              const FieldLabel('Max classes (blank = unlimited)'),
              TextFormField(
                controller: _maxClassesCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 18),
              const FieldLabel('Includes'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _featureCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Add a feature',
                        isDense: true,
                      ),
                      onFieldSubmitted: (_) => _addFeature(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: AppIcons.add,
                    onTap: _addFeature,
                    bg: AppTheme.accentSoft,
                    fg: AppTheme.accent,
                  ),
                ],
              ),
              if (_features.isNotEmpty)
                CardList(
                  children: _features
                      .asMap()
                      .entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                AppIcons.check,
                                size: 15,
                                color: AppTheme.statusActive,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: AppTheme.ink,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _features.removeAt(e.key)),
                                child: const Icon(
                                  AppIcons.close,
                                  size: 16,
                                  color: AppTheme.inkHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Active',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppTheme.ink,
                    ),
                  ),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                    : const Text('Save plan'),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _loading ? null : _delete,
                  child: const Text(
                    'Delete plan',
                    style: TextStyle(color: AppTheme.statusDanger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
