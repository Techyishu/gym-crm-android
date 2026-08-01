import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/billing/advance_payment_date.dart';

void main() {
  test('advances from the date itself, not from today', () {
    // The regression: due 2026-08-01 collected in July used to return 2026-08-01.
    expect(advancePaymentDate('2026-08-01'), '2026-09-01');
    expect(advancePaymentDate('2026-08-01', months: 4), '2026-12-01');
  });

  test('crosses year boundaries', () {
    expect(advancePaymentDate('2026-12-15'), '2027-01-15');
    expect(advancePaymentDate('2026-11-30', months: 14), '2028-01-30');
  });

  test('clamps day to shorter months', () {
    expect(advancePaymentDate('2026-01-31'), '2026-02-28');
    expect(advancePaymentDate('2028-01-31'), '2028-02-29'); // leap year
    expect(advancePaymentDate('2026-03-31'), '2026-04-30');
  });

  test('tolerates timestamps, bad input and bad month counts', () {
    expect(advancePaymentDate('2026-08-01T00:00:00+00:00'), '2026-09-01');
    expect(advancePaymentDate('2026-08-01', months: 0), '2026-09-01');
    expect(advancePaymentDate('not-a-date'), isNull);
  });
}
