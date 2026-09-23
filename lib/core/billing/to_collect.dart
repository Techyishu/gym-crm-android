import 'package:supabase_flutter/supabase_flutter.dart';

/// "To collect" — the one rule for what a gym is owed *right now*, shared by
/// the Money card and the Home card so the two can never disagree again.
///
/// Home used to sum every open invoice regardless of due date, so an advance
/// bill due in 2028 showed as outstanding today while Money said ₹0.
///
/// Counts overdue-or-due-today items no older than [collectWindowDays]:
/// unpaid invoice balances, plus renewals that have no invoice yet. Older
/// unpaid bills are an old-dues problem, not today's collection task.
const collectWindowDays = 7;

/// Remaining balance on an invoice row fetched with a joined `payments` list —
/// invoice amount minus whatever has already been collected against it.
double remainingDue(Map<String, dynamic> invoice) {
  final amount = (invoice['amount'] as num?)?.toDouble() ?? 0;
  final invPayments = (invoice['payments'] as List?) ?? const [];
  final paid = invPayments
      .where((p) => (p as Map)['status'] == 'succeeded')
      .fold<double>(0, (s, p) => s + ((p as Map)['amount'] as num).toDouble());
  return (amount - paid).clamp(0, amount);
}

/// Active plan price minus any per-member discount — same rule
/// QuickCollectSheet uses to autofill the amount when it creates the invoice.
double activePlanPrice(Map<String, dynamic> member) {
  final memberships = (member['memberships'] as List?) ?? const [];
  for (final m in memberships) {
    final map = (m as Map).cast<String, dynamic>();
    if (map['status'] != 'active') continue;
    // A day pass never renews, so it has no projected due.
    if (map['billing_interval_days'] != null) return 0;
    final plan = map['membership_plans'] as Map?;
    if (plan == null || plan['price'] == null) continue;
    final listPrice = (plan['price'] as num).toDouble();
    final discount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    return (listPrice - discount).clamp(0, listPrice);
  }
  return 0;
}

/// Members whose renewal falls due within the window and may have no invoice
/// yet. Needs at least these columns; callers may select more.
const collectMemberColumns =
    'id, next_payment_date, memberships(status, discount_amount, billing_interval_days, membership_plans(price, name))';

PostgrestTransformBuilder<List<Map<String, dynamic>>> renewingMembersQuery(
  SupabaseClient client,
  String gymId, {
  String columns = collectMemberColumns,
}) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  return client
      .from('members')
      .select(columns)
      .eq('gym_id', gymId)
      .not('status', 'eq', 'cancelled')
      .lte(
        'next_payment_date',
        startOfToday
            .add(const Duration(days: collectWindowDays))
            .toIso8601String()
            .split('T')
            .first,
      )
      .order('next_payment_date');
}

typedef ToCollect = ({double total, int members, int items});

/// [invoices]: open/partial invoice rows with `member_id`, `amount`, `due_at`
/// and joined `payments(amount, status)`. [renewingMembers]: rows from
/// [renewingMembersQuery].
ToCollect computeToCollect({
  required List<Map<String, dynamic>> invoices,
  required List<Map<String, dynamic>> renewingMembers,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final oldCutoff = DateTime(
    at.year,
    at.month,
    at.day,
  ).subtract(const Duration(days: collectWindowDays));
  bool collectible(String? raw) {
    final due = DateTime.tryParse(raw ?? '');
    return due != null && !due.isAfter(at) && !due.isBefore(oldCutoff);
  }

  // Only invoices that are partial or due within the window take part — an
  // advance bill due months ahead must not hide that member's renewal due
  // today. (Money's query already applies this; Home fetches every open one.)
  final windowEnd = DateTime(
    at.year,
    at.month,
    at.day,
  ).add(const Duration(days: collectWindowDays + 1));
  final dues = invoices.where((i) {
    if (remainingDue(i) <= 0) return false;
    if (i['status'] == 'partial') return true;
    final due = DateTime.tryParse(i['due_at'] as String? ?? '');
    return due != null && due.isBefore(windowEnd);
  }).toList();
  final invoicedIds = dues.map((d) => d['member_id']).toSet();
  final projected = renewingMembers.where(
    (m) => !invoicedIds.contains(m['id']) && activePlanPrice(m) > 0,
  );

  final dueNow = dues.where((d) => collectible(d['due_at'] as String?));
  final projectedNow = projected.where(
    (m) => collectible(m['next_payment_date'] as String?),
  );

  return (
    total:
        dueNow.fold<double>(0, (s, d) => s + remainingDue(d)) +
        projectedNow.fold<double>(0, (s, m) => s + activePlanPrice(m)),
    members:
        dueNow.map((d) => d['member_id']).toSet().length + projectedNow.length,
    items: dueNow.length + projectedNow.length,
  );
}
