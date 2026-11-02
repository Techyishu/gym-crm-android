import 'package:country_picker/country_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _indianMobileRegex = RegExp(r'^[6-9]\d{9}$');

// Gym-level country, seeded from gyms.settings['country'] on profile load
// (same as setCurrency). Gyms that never picked one are Indian.
String _gymCountry = 'IN';
String _gymDialCode = '91';

String get gymCountry => _gymCountry;

/// The gym's dial code without "+", e.g. "91", "971".
String get gymDialCode => _gymDialCode;

void setGymCountry(String? iso) {
  final c = (iso == null || iso.isEmpty) ? 'IN' : iso.toUpperCase();
  _gymCountry = c;
  _gymDialCode = Country.tryParse(c)?.phoneCode ?? '91';
}

bool isValidEmail(String value) => _emailRegex.hasMatch(value);

/// India keeps the strict 10-digit 6-9 rule. Elsewhere numbering plans vary
/// too much for one regex, so only the length is checked.
// ponytail: length-only outside India; add libphonenumber if gyms report bad numbers getting through
bool isValidMobile(String value, {String? dialCode}) {
  final dial = dialCode ?? _gymDialCode;
  // Trunk "0" allowed: "09812345678" is a fine Indian number to type.
  final local = localMobileDigits(
    value,
    dialCode: dial,
  ).replaceFirst(RegExp(r'^0+'), '');
  if (dial == '91') return _indianMobileRegex.hasMatch(local);
  return local.length >= 6 && local.length <= 13;
}

/// The local digits of a number that may or may not carry a country code.
///
/// Numbers are *stored* with the country code (WhatsApp and MSG91 need it),
/// but every form here asks for the bare local digits with the dial code
/// painted beside the box. Without this, loading a stored "+919812345603" into
/// an edit field left 12 digits in front of a 10-digit validator, and the
/// member could never be saved again — 1,019 members were stuck that way.
String localMobileDigits(String? value, {String? dialCode}) {
  final dial = dialCode ?? _gymDialCode;
  final raw = (value ?? '').trim();
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith(dial) && (raw.startsWith('+') || digits.length > 10)) {
    return digits.substring(dial.length);
  }
  return digits;
}

/// For optional email fields: empty is allowed, anything entered must be valid.
String? validateOptionalEmail(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return isValidEmail(value) ? null : 'Enter a valid email address';
}

/// For optional phone fields: empty is allowed, anything entered must be a
/// valid mobile number for the gym's country (see [isValidMobile]).
String? validateOptionalPhone(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return isValidMobile(value) ? null : 'Enter a valid mobile number';
}

/// Stores the number the way WhatsApp/MSG91 need it — with the country code.
///
/// The add-member form paints the dial code beside the field as decoration
/// only, so a bare local number was saved and every reminder to that member
/// silently failed to send. Anything the user typed with its own "+" is left
/// alone, and an empty value stays empty. Defaults to the gym's dial code.
String? phoneWithCountryCode(String? v, {String? dialCode}) {
  final dial = dialCode ?? _gymDialCode;
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.startsWith('+')) return value;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  // Already carries the country code without the "+" (e.g. pasted "919812…").
  if (digits.length > 10 && digits.startsWith(dial)) return '+$digits';
  // Drop the trunk "0" locals dial with ("07911 123456" → +44 7911 123456).
  return '+$dial${digits.replaceFirst(RegExp(r'^0+'), '')}';
}

/// Digits for a wa.me link ("919812345678"), country code included.
String whatsAppDigits(String? phone) =>
    (phoneWithCountryCode(phone) ?? '').replaceAll('+', '');

/// A user-facing message when a write was rejected by the
/// `members_no_duplicate_phone` trigger (block_duplicate_member_phone), or
/// null if [error] is something else.
String? duplicatePhoneMessage(Object error) {
  if (error is! PostgrestException) return null;
  if (!error.message.contains('phone number already exists in this gym')) {
    return null;
  }
  return 'A member with this phone number already exists in this gym.';
}
