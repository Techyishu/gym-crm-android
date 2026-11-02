import 'package:flutter_test/flutter_test.dart';
import 'package:gym_crm/core/utils/formatters.dart' show currencyForCountry;
import 'package:gym_crm/core/utils/validators.dart';
import 'package:gym_crm/features/auth/providers/auth_provider.dart';

void main() {
  tearDown(() => setGymCountry(null));

  test('Indian gym: behaviour unchanged', () {
    setGymCountry(null);
    expect(gymDialCode, '91');
    expect(isValidMobile('9812345678'), isTrue);
    expect(isValidMobile('09812345678'), isTrue);
    expect(isValidMobile('+919812345678'), isTrue);
    expect(isValidMobile('5812345678'), isFalse);
    expect(phoneWithCountryCode('9812345678'), '+919812345678');
    expect(phoneWithCountryCode('919812345678'), '+919812345678');
    // A real 10-digit mobile that itself starts with 91.
    expect(phoneWithCountryCode('9116669678'), '+919116669678');
    expect(localMobileDigits('+919812345678'), '9812345678');
    expect(whatsAppDigits('98123 45678'), '919812345678');
  });

  test('UAE gym uses its own dial code', () {
    setGymCountry('AE');
    expect(gymDialCode, '971');
    expect(isValidMobile('501234567'), isTrue);
    expect(phoneWithCountryCode('0501234567'), '+971501234567');
    expect(localMobileDigits('+971501234567'), '501234567');
    expect(whatsAppDigits('+447911123456'), '447911123456');
  });

  test('country picks its currency', () {
    expect(currencyForCountry('IN'), 'INR');
    expect(currencyForCountry('AE'), 'AED');
    expect(currencyForCountry('US'), 'USD');
    expect(currencyForCountry('GB'), 'GBP');
    expect(currencyForCountry('DE'), 'EUR');
  });

  test('member login email stays the same for Indian numbers', () {
    final full = phoneWithCountryCode('9812345678', dialCode: '91')!;
    expect(memberSyntheticEmail(full), memberSyntheticEmail('9812345678'));
  });
}
