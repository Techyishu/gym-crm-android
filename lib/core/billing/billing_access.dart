bool hasActiveBillingAccess(Map<String, dynamic>? gym, {bool ignoreTrial = false}) {
  if (gym == null) return false;

  final now = DateTime.now().toUtc();
  final plan = gym['plan'] as String?;
  final planExpiresAt = gym['plan_expires_at'] as String?;
  final trialEndsAt = gym['trial_ends_at'] as String?;
  final dodoId = gym['dodo_subscription_id'] as String?;

  // Grandfathered pro with no expiry
  if (plan == 'pro' && planExpiresAt == null) return true;

  // Pro with active recurring subscription
  if (plan == 'pro' && dodoId != null && planExpiresAt != null) {
    if (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false) return true;
  }

  // Any plan with a future expiry date (starter, one-time, etc.)
  if (planExpiresAt != null) {
    if (DateTime.tryParse(planExpiresAt)?.toUtc().isAfter(now) ?? false) return true;
  }

  // Within trial period — iOS ignores this, must pay via StoreKit before use.
  if (!ignoreTrial && trialEndsAt != null) {
    if (DateTime.tryParse(trialEndsAt)?.toUtc().isAfter(now) ?? false) return true;
  }

  return false;
}

/// Returns how many trial days remain, or null if trial has ended / no trial.
int? trialDaysRemaining(Map<String, dynamic>? gym) {
  if (gym == null) return null;
  final trialEndsAt = gym['trial_ends_at'] as String?;
  if (trialEndsAt == null) return null;
  final end = DateTime.tryParse(trialEndsAt)?.toUtc();
  if (end == null) return null;
  final diff = end.difference(DateTime.now().toUtc()).inDays;
  return diff > 0 ? diff : null;
}

/// Days remaining before `plan_expires_at`/`trial_ends_at` (whichever is set),
/// or null if there's no expiry to warn about. Can be negative (already expired
/// but still within some grace window) — callers decide the cutoff.
int? planExpiryDaysRemaining(Map<String, dynamic>? gym) {
  if (gym == null) return null;
  final expiryStr = gym['plan_expires_at'] as String? ?? gym['trial_ends_at'] as String?;
  if (expiryStr == null) return null;
  final expiry = DateTime.tryParse(expiryStr)?.toUtc();
  if (expiry == null) return null;
  return expiry.difference(DateTime.now().toUtc()).inDays;
}
