final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _indianMobileRegex = RegExp(r'^[6-9]\d{9}$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value);

bool isValidIndianMobile(String value) =>
    _indianMobileRegex.hasMatch(localMobileDigits(value));

/// The 10 local digits of a number that may or may not carry a country code.
///
/// Numbers are *stored* with the country code (WhatsApp and MSG91 need it),
/// but every form here asks for the bare 10 digits with "+91" painted beside
/// the box. Without this, loading a stored "+919812345603" into an edit field
/// left 12 digits in front of a 10-digit validator, and the member could never
/// be saved again — 1,019 members were stuck that way.
String localMobileDigits(String? value, {String dialCode = '91'}) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length > 10 && digits.startsWith(dialCode)) {
    return digits.substring(dialCode.length);
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
/// valid 10-digit Indian mobile number (matches signup_screen's INDIAN_MOBILE rule).
String? validateOptionalPhone(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  return isValidIndianMobile(value)
      ? null
      : 'Enter a valid 10-digit mobile number';
}

/// Stores the number the way WhatsApp/MSG91 need it — with the country code.
///
/// The add-member form paints "+91" beside the field as decoration only, so a
/// bare 10-digit number was saved and every reminder to that member silently
/// failed to send. Anything the user typed with its own "+" is left alone, and
/// an empty value stays empty.
String? phoneWithCountryCode(String? v, {String dialCode = '91'}) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.startsWith('+')) return value;
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  // Already carries the country code without the "+" (e.g. pasted "919812…").
  if (digits.length > 10 && digits.startsWith(dialCode)) return '+$digits';
  return '+$dialCode$digits';
}
