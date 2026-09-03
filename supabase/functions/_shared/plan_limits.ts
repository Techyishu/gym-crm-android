/**
 * Plan limits shared by every edge function that spends a gym's WhatsApp
 * allowance. Was duplicated in whatsapp-reminders and send-whatsapp-invoice,
 * which meant a pricing change had to be made twice and stayed correct only by
 * luck.
 *
 * Mirrors public.plan_whatsapp_quota() in the database — change both together.
 *
 * 'free' is the unpaid default (renamed from 'starter' in migration
 * 20260903000000_plan_tier_starter.sql); 'starter' is the paid ₹299 tier.
 */
export function planQuota(gym: { plan: string; legacy_pricing?: boolean }): number {
  if (gym.legacy_pricing) return 100
  if (gym.plan === 'starter') return 100
  if (gym.plan === 'pro') return 300
  if (gym.plan === 'elite') return 1500
  return 0
}
