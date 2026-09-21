/// Day passes: short, non-renewing plans. Stored as a `custom` plan with
/// `billing_interval_days` set; 30+ days is just a monthly plan.
const int maxDayPassDays = 29;

/// True for a `membership_plans` row that is a day pass.
bool isDayPassPlan(Map<String, dynamic>? plan) =>
    plan != null && plan['billing_interval_days'] != null;

/// True when the member's active membership is a day pass. Needs
/// `memberships(status, billing_interval_days)` in the query that fetched it.
bool hasActiveDayPass(Map<String, dynamic> member) {
  final memberships = (member['memberships'] as List?) ?? const [];
  return memberships.any((m) {
    final ms = (m as Map).cast<String, dynamic>();
    return ms['status'] == 'active' && ms['billing_interval_days'] != null;
  });
}

/// Last valid day of a pass that starts on [startDate] ("YYYY-MM-DD") and runs
/// [days] days, counting the start day: a 1-day pass ends the day it starts.
/// The member stays active through this date and expires the day after.
/// Returns null on an unparseable date.
String? dayPassEndDate(String startDate, int days) {
  final d = DateTime.tryParse(startDate.split('T').first);
  if (d == null) return null;
  final step = days < 1 ? 1 : days;
  return DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).add(Duration(days: step - 1)).toIso8601String().split('T').first;
}
