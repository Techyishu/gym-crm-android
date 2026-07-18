import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

// Gym-level currency, seeded from gyms.settings['currency'] on profile load.
// Defaults to INR for existing gyms that never picked one.
String _currencyCode = 'INR';
NumberFormat _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

String get currencyCode => _currencyCode;
String get currencySymbol => _currency.currencySymbol;

void setCurrency(String? code) {
  final c = (code == null || code.isEmpty) ? 'INR' : code;
  if (c == _currencyCode) return;
  _currencyCode = c;
  _currency = NumberFormat.simpleCurrency(name: c, decimalDigits: 0);
}
final _date = DateFormat('d MMM yyyy');
final _dateShort = DateFormat('d MMM');
final _dateTime = DateFormat('d MMM yyyy, h:mm a');
final _month = DateFormat('MMM yyyy');

String formatCurrency(num amount) => _currency.format(amount);

/// Compact money for dashboards/reports. INR keeps lakh notation (₹1.20L);
/// other currencies use standard compact (e.g. $120K).
String formatCurrencyCompact(num amount) {
  if (_currencyCode == 'INR') {
    if (amount >= 100000) {
      return '$currencySymbol${(amount / 100000).toStringAsFixed(2)}L';
    }
    if (amount >= 1000) {
      return '$currencySymbol${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
    }
    return formatCurrency(amount);
  }
  return NumberFormat.compactSimpleCurrency(name: _currencyCode).format(amount);
}
String formatDate(DateTime dt) => _date.format(dt);
String formatDateShort(DateTime dt) => _dateShort.format(dt);
String formatDateTime(DateTime dt) => _dateTime.format(dt);
String formatMonth(DateTime dt) => _month.format(dt);

String formatDateFromString(String? s) {
  if (s == null) return '-';
  try {
    return formatDate(DateTime.parse(s).toLocal());
  } catch (e) {
    debugPrint('[GymCRM] formatDateFromString error for "$s": $e');
    return s;
  }
}

String formatDateTimeFromString(String? s) {
  if (s == null) return '-';
  try {
    return formatDateTime(DateTime.parse(s).toLocal());
  } catch (e) {
    debugPrint('[GymCRM] formatDateTimeFromString error for "$s": $e');
    return s;
  }
}

String timeAgo(String? s) {
  if (s == null) return '-';
  try {
    final dt = DateTime.parse(s).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return formatDate(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  } catch (e) {
    debugPrint('[GymCRM] timeAgo error for "$s": $e');
    return s;
  }
}

String initials(String firstName, String lastName) {
  final f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
  final l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
  return '$f$l';
}
