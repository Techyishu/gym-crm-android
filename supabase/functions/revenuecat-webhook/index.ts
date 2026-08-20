/**
 * RevenueCat → Supabase webhook.
 *
 * Setup in RC Dashboard:
 *   Integrations → Webhooks → Add endpoint
 *   URL    : https://<project>.supabase.co/functions/v1/revenuecat-webhook
 *   Secret : set a random string, store it as RC_WEBHOOK_SECRET in Supabase secrets
 *
 * Supabase secrets required:
 *   SUPABASE_URL              (auto-injected)
 *   SUPABASE_SERVICE_ROLE_KEY (auto-injected)
 *   RC_WEBHOOK_SECRET         (set via: supabase secrets set RC_WEBHOOK_SECRET=xxx)
 *
 * RC sends app_user_id = Supabase auth user ID because we call
 * Purchases.logIn(supabaseUserId) in main.dart after sign-in.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// RC event types that mean "subscription is alive"
const ACTIVE_EVENTS = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
  'TRANSFER',
])

// RC event types that mean "subscription ended"
const LAPSED_EVENTS = new Set([
  'CANCELLATION',
  'EXPIRATION',
  'BILLING_ISSUE',
])

// Consumable WhatsApp credit-pack products — App Store Connect product ID → credits.
const CREDIT_PRODUCTS: Record<string, number> = {
  gymcrm_credits_200: 200,
  gymcrm_credits_300: 300,
  gymcrm_credits_500: 500,
}

interface RcEvent {
  type: string
  app_user_id: string
  expiration_at_ms: number | null
  product_id: string | null
  period_type: string | null
  store: string
}

interface RcPayload {
  event: RcEvent
}

async function getGymId(userId: string): Promise<string | null> {
  const { data } = await supabase
    .from('profiles')
    .select('gym_id')
    .eq('id', userId)
    .maybeSingle()
  return data?.gym_id ?? null
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  // ── Auth: verify RC webhook secret ───────────────────────────────────────────
  const secret = Deno.env.get('RC_WEBHOOK_SECRET')
  if (secret) {
    const authHeader = req.headers.get('Authorization') ?? ''
    const provided = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7)
      : authHeader
    if (provided !== secret) {
      console.error('[rc-webhook] Invalid Authorization header')
      return new Response('Unauthorized', { status: 401 })
    }
  }

  // ── Parse body ────────────────────────────────────────────────────────────────
  let payload: RcPayload
  try {
    payload = await req.json()
  } catch {
    return new Response('Bad JSON', { status: 400 })
  }

  const event = payload?.event
  if (!event?.type || !event?.app_user_id) {
    return new Response('Missing event fields', { status: 400 })
  }

  const { type, app_user_id, expiration_at_ms, product_id } = event

  console.log(`[rc-webhook] event=${type} user=${app_user_id} product=${product_id}`)

  // ── Resolve gym ───────────────────────────────────────────────────────────────
  const gymId = await getGymId(app_user_id)
  if (!gymId) {
    // User may not have a staff profile (member-only account) — not an error.
    console.warn(`[rc-webhook] No gym for user=${app_user_id}, skipping`)
    return new Response('ok', { status: 200 })
  }

  // ── Consumable credit-pack purchase (one-time, not a subscription) ────────────
  if (type === 'NON_RENEWING_PURCHASE' && product_id && CREDIT_PRODUCTS[product_id]) {
    const credits = CREDIT_PRODUCTS[product_id]
    const { error } = await supabase.rpc('increment_whatsapp_credits', {
      p_gym_id: gymId,
      p_amount: credits,
    })
    if (error) {
      console.error(`[rc-webhook] credit increment failed: ${error.message}`)
      return new Response('DB error', { status: 500 })
    }
    console.log(`[rc-webhook] gym=${gymId} +${credits} whatsapp credits (${product_id})`)
    return new Response('ok', { status: 200 })
  }

  const expiresAt = expiration_at_ms
    ? new Date(expiration_at_ms).toISOString()
    : null

  // ── Handle active events ──────────────────────────────────────────────────────
  if (ACTIVE_EVENTS.has(type)) {
    const { error } = await supabase
      .from('gyms')
      .update({
        plan: 'pro',
        plan_expires_at: expiresAt,
        apple_subscription_id: app_user_id, // ties this gym to the RC user
        // Otherwise planExpiryDaysRemaining() falls back to this stale date
        // and shows a "trial ending" nag to an already-paying gym.
        trial_ends_at: null,
      })
      .eq('id', gymId)

    if (error) {
      console.error(`[rc-webhook] DB update failed: ${error.message}`)
      // Return 500 so RC retries the webhook.
      return new Response('DB error', { status: 500 })
    }

    console.log(`[rc-webhook] gym=${gymId} → pro, expires=${expiresAt}`)
    return new Response('ok', { status: 200 })
  }

  // ── Handle lapsed events ──────────────────────────────────────────────────────
  if (LAPSED_EVENTS.has(type)) {
    const { error } = await supabase
      .from('gyms')
      .update({
        plan: 'free',
        plan_expires_at: expiresAt, // RC sends the date it actually expired
      })
      .eq('id', gymId)

    if (error) {
      console.error(`[rc-webhook] DB update failed: ${error.message}`)
      return new Response('DB error', { status: 500 })
    }

    console.log(`[rc-webhook] gym=${gymId} → free, expired=${expiresAt}`)
    return new Response('ok', { status: 200 })
  }

  // Unknown event type — ack so RC doesn't keep retrying.
  console.log(`[rc-webhook] Unhandled event type: ${type}`)
  return new Response('ok', { status: 200 })
})
