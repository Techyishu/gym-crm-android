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

  group('localMobileDigits', () {
    test('strips the stored country code so edit forms show 10 digits', () {
      // The bug: a stored number went straight into a 10-digit-validated
      // field, so 1,019 members could never be saved again.
      expect(localMobileDigits('+919812345603'), '9812345603');
      expect(localMobileDigits('919812345603'), '9812345603');
      expect(isValidIndianMobile('+919812345603'), isTrue);
    });

    test('leaves a bare 10-digit number alone', () {
      expect(localMobileDigits('9812345603'), '9812345603');
      expect(localMobileDigits(null), '');
    });

    test('does not eat a local number that happens to start with 91', () {
      // 9123456789 is a valid local number; only >10 digits carry a code.
      expect(localMobileDigits('9123456789'), '9123456789');
    });
  });
}
