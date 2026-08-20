import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Runs daily via pg_cron -> public.trigger_whatsapp_credit_push(). Pushes the
// gym OWNER (external_id == profiles.id, role='owner') when their WhatsApp
// balance (free monthly quota + purchased credits, same pool whatsapp-reminders
// and send-whatsapp-invoice draw from) is low or exhausted.
//
// Mirrors billing-expiry-push's notifications_log dedupe so a gym gets at
// most one push per state (low / exhausted) per day, not one every cron tick.

const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID')!
const ONESIGNAL_REST_API_KEY = Deno.env.get('ONESIGNAL_REST_API_KEY')!
const CRON_SECRET = Deno.env.get('CRON_SECRET')!

const LOW_THRESHOLD = 10

// Mirrors planQuota() in whatsapp-reminders/index.ts — keep these in sync.
function planQuota(gym: { plan: string; legacy_pricing?: boolean }): number {
  if (gym.legacy_pricing) return 100
  if (gym.plan === 'pro') return 300
  if (gym.plan === 'elite') return 1500
  return 0
}

function dateStr(d: Date) {
  return d.toISOString().split('T')[0]
}

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  if (!auth.startsWith('Bearer ') || auth.slice(7) !== CRON_SECRET) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } }
  )

  // Only gyms actually using WhatsApp reminders — otherwise every starter
  // gym sitting at the default signup credit grant (10, same as LOW_THRESHOLD)
  // would false-positive as "low" forever, whether they use the feature or not.
  const { data: gyms, error: gymsErr } = await supabase
    .from('gyms')
    .select('id, plan, legacy_pricing, whatsapp_credits, whatsapp_monthly_quota_used')
    .eq('whatsapp_reminder_enabled', true)

  if (gymsErr) {
    console.error('[whatsapp-credit-push] gyms query:', gymsErr.message)
    return new Response(JSON.stringify({ error: gymsErr.message }), { status: 500 })
  }

  let sent = 0
  let skipped = 0
  let failed = 0
  const today = dateStr(new Date())

  for (const gym of gyms ?? []) {
    const quotaLeft = Math.max(planQuota(gym) - (gym.whatsapp_monthly_quota_used ?? 0), 0)
    const remaining = quotaLeft + (gym.whatsapp_credits ?? 0)

    let type: string
    let title: string
    let body: string
    if (remaining <= 0) {
      type = 'whatsapp_credit_exhausted'
      title = 'WhatsApp credits exhausted'
      body = "You've used all your WhatsApp reminders for this month. Top up now to keep renewal reminders going out."
    } else if (remaining <= LOW_THRESHOLD) {
      type = 'whatsapp_credit_low'
      title = 'WhatsApp credits running low'
      body = `Only ${remaining} WhatsApp reminder${remaining === 1 ? '' : 's'} left this month. Top up soon to avoid interruption.`
    } else {
      continue
    }

    const { data: already } = await supabase
      .from('notifications_log')
      .select('id')
      .eq('gym_id', gym.id)
      .eq('type', type)
      .gte('created_at', `${today}T00:00:00Z`)
      .limit(1)
    if (already?.length) { skipped++; continue }

    const { data: owner } = await supabase
      .from('profiles')
      .select('id')
      .eq('gym_id', gym.id)
      .eq('role', 'owner')
      .maybeSingle()
    if (!owner) { skipped++; continue }

    const url = '/staff/reminders'

    let ok = false
    let errorText = ''
    try {
      const res = await fetch('https://api.onesignal.com/notifications', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Key ${ONESIGNAL_REST_API_KEY}` },
        body: JSON.stringify({
          app_id: ONESIGNAL_APP_ID,
          include_aliases: { external_id: [owner.id] },
          target_channel: 'push',
          headings: { en: title },
          contents: { en: body },
          // Not using top-level "url" — OneSignal's native SDK auto-opens it
          // externally, bypassing our own in-app click handling.
          data: { type, gym_id: gym.id, remaining, deep_link: url },
        }),
      })
      ok = res.ok
      if (!ok) errorText = await res.text()
    } catch (e) {
      errorText = (e as Error).message
    }

    await supabase.from('notifications_log').insert({
      gym_id: gym.id,
      channel: 'push',
      type,
      status: ok ? 'sent' : 'failed',
      sent_at: ok ? new Date().toISOString() : null,
      error: ok ? null : errorText.slice(0, 500),
    })

    if (ok) {
      await supabase.from('staff_notifications').insert({ user_id: owner.id, gym_id: gym.id, title, body, url })
      sent++
    } else {
      console.error(`[whatsapp-credit-push] OneSignal error (gym ${gym.id}):`, errorText)
      failed++
    }
  }

  console.log(`[whatsapp-credit-push] sent=${sent} skipped=${skipped} failed=${failed}`)
  return new Response(JSON.stringify({ sent, skipped, failed }), { status: 200 })
})
