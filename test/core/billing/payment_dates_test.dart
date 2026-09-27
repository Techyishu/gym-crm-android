import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/billing/payment_dates.dart';

void main() {
  test('overdue member with only an old bill is collected as a renewal', () {
    final old = [
      {'id': 'old', 'due_at': '2026-08-13T00:00:00Z'},
    ];
    final overdue = ymd(today.subtract(const Duration(days: 10)));
    final upcoming = ymd(today.add(const Duration(days: 10)));
    expect(preferredCollectInvoice(old, overdue), isNull);
    // An active member paying an old due still settles that bill.
    expect(preferredCollectInvoice(old, upcoming)?['id'], 'old');
  });

  test('an untouched past default valid-till does not block a collect', () {
    final past = today.subtract(const Duration(days: 20));
    expect(paymentDatesError(today, past, defaultTill: past), isNull);
    // ...but a past date the owner typed themselves is still rejected.
    expect(
      paymentDatesError(
        today,
        past,
        defaultTill: today.add(const Duration(days: 30)),
      ),
      'Valid till must be after the payment date',
    );
  });

  test(
    'collection prefers the current renewal invoice over an older balance',
    () {
      final invoices = [
        {'id': 'old', 'due_at': '2026-08-23T00:00:00Z'},
        {'id': 'renewal', 'due_at': '2026-09-23T00:00:00Z'},
      ];

      expect(preferredCollectInvoice(invoices, '2026-09-23')?['id'], 'renewal');
      expect(
        billRenewsPlan(dueDate: '2026-08-23', nextPaymentDate: '2026-09-23'),
        isFalse,
      );
    },
  );
}
