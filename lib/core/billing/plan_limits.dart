import 'package:supabase_flutter/supabase_flutter.dart';


/// Plan tiers, in ascending order of what they unlock.
///
/// `free` is the unpaid default every new gym starts on (renamed from
/// 'starter' in migration 20260903000000_plan_tier_starter.sql, which freed
/// that name for the paid ₹299 tier). A gym on `free` is either inside its
/// trial or already sitting behind the paywall — `hasActiveBillingAccess`
/// decides which, and this file does not.
enum PlanTier { free, starter, pro, elite }

PlanTier planTierOf(Map<String, dynamic>? gym) => switch (gym?['plan']) {
  'starter' => PlanTier.starter,
  'pro' => PlanTier.pro,
  'elite' => PlanTier.elite,
  _ => PlanTier.free,
};

/// Members a gym may hold, or null for unlimited.
///
/// Mirrors public.plan_member_limit() — the database trigger is what actually
/// enforces this (members are inserted from the add-member sheet, the CSV
/// importer and the web app). The value here exists so the app can warn before
/// the insert fails, not instead of it.
int? memberLimit(PlanTier tier) => tier == PlanTier.starter ? 100 : null;

/// Staff logins a gym may hold, or null for unlimited.
/// Mirrors public.plan_staff_limit().
int? staffLimit(PlanTier tier) => tier == PlanTier.starter ? 1 : null;

/// Free WhatsApp messages per month. Mirrors public.plan_whatsapp_quota() and
/// supabase/functions/_shared/plan_limits.ts — change all three together.
///
/// Legacy (₹249) gyms keep their old 100 regardless of tier, keyed off
/// `legacy_pricing` rather than plan_price, which is also used for manual
/// overrides.
int whatsappQuota(Map<String, dynamic>? gym) {
  if (gym?['legacy_pricing'] == true) return 100;
  return switch (planTierOf(gym)) {
    PlanTier.starter => 100,
    PlanTier.pro => 300,
    PlanTier.elite => 1500,
    PlanTier.free => 0,
  };
}

/// Reminder offsets a gym may configure. Each configured offset is one message
/// per member per cycle, so this — not the raw credit count — is the real
/// multiplier on WhatsApp cost.
int reminderDaysLimit(PlanTier tier) => tier == PlanTier.starter ? 1 : 3;

/// Whether biometric device support is available on this tier.
///
/// The only feature Starter does not get. Everything else — leads, expenses,
/// batches, exports, reports — is identical to Pro; the tiers differ by the
/// caps above, not by what the app can do. That is deliberate: a gym that
/// used a feature through its trial and then paid us should never find it
/// gone the next morning.
///
/// Gated at the biometric sheet rather than on GymModule.attendance, because
/// that module is "Check-in & biometric" and QR check-in stays on every tier —
/// it is the feature most correlated with a gym still being active a month
/// later. The menu entry stays visible on Starter and explains the upgrade.
bool allowsBiometric(PlanTier tier) => tier != PlanTier.starter;

/// A user-facing message when a write was rejected by a plan-limit trigger,
/// or null if [error] is something else.
///
/// Reading the limit off the trigger's own exception rather than re-counting
/// client-side: the count would be a second round-trip that can still lose a
/// race against a concurrent insert, and the database is the thing that
/// actually said no.
String? planLimitMessage(Object error) {
  if (error is! PostgrestException) return null;
  final message = error.message;
  if (message.contains('member_limit_reached')) {
    return 'Starter is limited to ${memberLimit(PlanTier.starter)} members. '
        'Upgrade to Pro for unlimited members.';
  }
  if (message.contains('staff_limit_reached')) {
    return 'Starter includes ${staffLimit(PlanTier.starter)} login. '
        'Upgrade to Pro to add staff.';
  }
  return null;
}

