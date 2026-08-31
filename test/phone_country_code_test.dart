import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/utils/validators.dart';

void main() {
  group('phoneWithCountryCode', () {
    test('adds the country code to a bare 10-digit number', () {
      // The bug this guards: the add-member form paints "+91" as decoration
      // only, so bare digits reached the database and WhatsApp reminders to
      // that member silently never sent.
      expect(phoneWithCountryCode('9800112233'), '+919800112233');
    });

    test('leaves a number the user already typed with "+" alone', () {
      expect(phoneWithCountryCode('+14155550123'), '+14155550123');
    });

    test('does not double the country code on a pasted 91… number', () {
      expect(phoneWithCountryCode('919800112233'), '+919800112233');
    });

    test('strips spaces and dashes', () {
      expect(phoneWithCountryCode(' 98001-12233 '), '+919800112233');
    });

    test('empty and null stay null so the column is not written', () {
      expect(phoneWithCountryCode(''), isNull);
      expect(phoneWithCountryCode(null), isNull);
      expect(phoneWithCountryCode('   '), isNull);
    });

    test('honours a non-India dial code', () {
      expect(phoneWithCountryCode('4155550123', dialCode: '1'), '+14155550123');
    });
  });
}
