import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/billing/to_collect.dart';

void main() {
  final now = DateTime(2026, 9, 23, 12);
  String day(int offset) => now.add(Duration(days: offset)).toIso8601String();

  Map<String, dynamic> inv(
    String member,
    double amount,
    int dueOffset, {
    String status = 'open',
    double paid = 0,
  }) => {
    'member_id': member,
    'amount': amount,
    'status': status,
    'due_at': day(dueOffset),
    'payments': [
      if (paid > 0) {'amount': paid, 'status': 'succeeded'},
    ],
  };

  Map<String, dynamic> renewal(String id, double price, int dueOffset) => {
    'id': id,
    'next_payment_date': day(dueOffset),
    'memberships': [
      {
        'status': 'active',
        'discount_amount': 0,
        'billing_interval_days': null,
        'membership_plans': {'price': price},
      },
    ],
  };

  test('future advance bills are not owed today (the Home ₹18,497 bug)', () {
    final r = computeToCollect(
      invoices: [inv('rajput', 7999, 18), inv('rajput', 7999, 82), inv('rajput', 2499, 722)],
      renewingMembers: const [],
      now: now,
    );
    expect(r.total, 0);
    expect(r.members, 0);
  });

  test('counts members, not invoices', () {
    final r = computeToCollect(
      invoices: [inv('a', 500, -1), inv('a', 300, -2), inv('b', 200, 0)],
      renewingMembers: const [],
      now: now,
    );
    expect(r.total, 1000);
    expect(r.members, 2);
    expect(r.items, 3);
  });

  test('bills older than the window are old dues, not to-collect', () {
    final r = computeToCollect(
      invoices: [inv('a', 500, -(collectWindowDays + 1))],
      renewingMembers: const [],
      now: now,
    );
    expect(r.total, 0);
  });

  test('partial balance counts only what is left', () {
    final r = computeToCollect(
      invoices: [inv('a', 1000, -1, status: 'partial', paid: 600)],
      renewingMembers: const [],
      now: now,
    );
    expect(r.total, 400);
  });

  test('a far-future bill does not hide a renewal due today', () {
    final r = computeToCollect(
      invoices: [inv('a', 2499, 722)],
      renewingMembers: [renewal('a', 999, 0)],
      now: now,
    );
    expect(r.total, 999);
    expect(r.members, 1);
  });

  test('a renewal that already has a due invoice is not counted twice', () {
    final r = computeToCollect(
      invoices: [inv('a', 999, -1)],
      renewingMembers: [renewal('a', 999, -1)],
      now: now,
    );
    expect(r.total, 999);
  });
}
