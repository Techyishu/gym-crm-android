/// Advance a "YYYY-MM-DD" billing date by [months] calendar months, relative to
/// the date itself — NOT to today. That was the old bug: collecting a payment
/// while next_payment_date already sat in next month produced the same date
/// back, so the member never left the upcoming-payments list and every
/// collection minted a fresh invoice.
///
/// Day-of-month is clamped to the target month's length (31 Jan -> 28/29 Feb).
/// Returns null on an unparseable date.
String? advancePaymentDate(String dateStr, {int months = 1}) {
  final d = DateTime.tryParse(dateStr.split('T').first);
  if (d == null) return null;
  final step = months < 1 ? 1 : months;
  final total = (d.month - 1) + step;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  final day = d.day < daysInMonth ? d.day : daysInMonth;
  return DateTime.utc(year, month, day).toIso8601String().split('T').first;
}
