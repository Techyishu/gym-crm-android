import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPush } from '../_shared/fcm.ts'

// Runs daily via pg_cron -> public.trigger_billing_expiry_push(). Pushes
// gym staff (profiles.id) when THEIR platform trial or
// subscription is about to expire — separate from push-reminders, which
// pushes gym MEMBERS about their membership renewal.
//
// Mirrors push-reminders' day-offset loop + notifications_log dedupe so a
// gym gets exactly one push per offset, not one every time the cron fires.

const CRON_SECRET = Deno.env.get('CRON_SECRET')!

const DAY_OFFSETS = [3, 1, 0]

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

  const { data: gyms, error: gymsErr } = await supabase
    .from('gyms')
    .select('id, plan, trial_ends_at, plan_expires_at')

  if (gymsErr) {
    console.error('[billing-expiry-push] gyms query:', gymsErr.message)
    return new Response(JSON.stringify({ error: gymsErr.message }), { status: 500 })
  }

  let sent = 0
  let skipped = 0
  let failed = 0
  const today = dateStr(new Date())

  for (const gym of gyms ?? []) {
    // Whichever expiry is active — trial end for gyms still trialing, plan
    // renewal date once subscribed.
    const expiryStr = gym.plan_expires_at ?? gym.trial_ends_at
    if (!expiryStr) continue
    const kind = gym.plan_expires_at ? 'plan_expiry' : 'trial_expiry'
    const expiryDateStr = dateStr(new Date(expiryStr))

    for (const daysBefore of DAY_OFFSETS) {
      const target = new Date()
      target.setUTCDate(target.getUTCDate() + daysBefore)
      if (dateStr(target) !== expiryDateStr) continue

      const type = `${kind}_${daysBefore}d`

      const { data: already } = await supabase
        .from('notifications_log')
        .select('id')
        .eq('gym_id', gym.id)
        .eq('type', type)
        .gte('created_at', `${today}T00:00:00Z`)
        .limit(1)
      if (already?.length) { skipped++; continue }

      const { data: profiles } = await supabase.from('profiles').select('id').eq('gym_id', gym.id)
      const userIds = (profiles ?? []).map(p => p.id as string)
      if (!userIds.length) { skipped++; continue }

      const title = kind === 'trial_expiry'
        ? (daysBefore === 0 ? 'Your trial ends today' : `Your trial ends in ${daysBefore} day${daysBefore === 1 ? '' : 's'}`)
        : (daysBefore === 0 ? 'Your subscription renews today' : `Your subscription renews in ${daysBefore} day${daysBefore === 1 ? '' : 's'}`)
      const body = kind === 'trial_expiry'
        ? 'Upgrade now to keep your members, billing, and check-in history.'
        : 'Make sure your payment method is up to date to avoid any interruption.'
      const url = '/staff/subscription'

      const { ok, error: errorText } = await sendPush(supabase, userIds, {
        title,
        body,
        data: { type, gym_id: gym.id, days_before: daysBefore, deep_link: url },
      })

      await supabase.from('notifications_log').insert({
        gym_id: gym.id,
        channel: 'push',
        type,
        status: ok ? 'sent' : 'failed',
        sent_at: ok ? new Date().toISOString() : null,
        error: ok ? null : errorText.slice(0, 500),
      })

      if (ok) {
        await supabase.from('staff_notifications').insert(
          (profiles ?? []).map(p => ({ user_id: p.id, gym_id: gym.id, title, body, url }))
        )
      }

      if (ok) sent++
      else { console.error(`[billing-expiry-push] FCM error (gym ${gym.id}):`, errorText); failed++ }
    }
  }

  console.log(`[billing-expiry-push] sent=${sent} skipped=${skipped} failed=${failed}`)
  return new Response(JSON.stringify({ sent, skipped, failed }), { status: 200 })
})
