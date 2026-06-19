final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _indianMobileRegex = RegExp(r'^[6-9]\d{9}$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value);

bool isValidIndianMobile(String value) =>
    _indianMobileRegex.hasMatch(value.replaceAll(RegExp(r'\D'), ''));

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
  return isValidIndianMobile(value) ? null : 'Enter a valid 10-digit mobile number';
}
