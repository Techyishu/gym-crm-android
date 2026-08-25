import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Runs daily via pg_cron -> public.trigger_owner_daily_summary(), ~8pm IST.
// Pushes the gym OWNER (external_id == profiles.id, role='owner') a one-line
// summary of the day: money collected, check-ins, and who's due tomorrow —
// the exact numbers the dashboard already computes, just delivered instead of
// waited for. Nothing else in the app currently messages the owner on any
// recurring schedule.
//
// Skips gyms where nothing happened today (all three numbers are zero) —
// an empty "₹0 collected · 0 check-ins" push trains people to ignore the
// channel. Dedupes via notifications_log, one push per gym per IST day,
// same pattern as whatsapp-credit-push.

const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID')!
const ONESIGNAL_REST_API_KEY = Deno.env.get('ONESIGNAL_REST_API_KEY')!
const CRON_SECRET = Deno.env.get('CRON_SECRET')!

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000

// Indian gyms run their busiest check-in window from ~5-7am. A UTC-midnight
// cutoff would chop that off (00:00 UTC == 5:30am IST) and undercount every
// gym's morning. Compute the actual IST calendar date, then anchor "start of
// day" to real IST midnight as a UTC instant.
function istDateStr(d: Date) {
  return new Date(d.getTime() + IST_OFFSET_MS).toISOString().split('T')[0]
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

  const now = new Date()
  const todayIst = istDateStr(now)
  const tomorrowIst = istDateStr(new Date(now.getTime() + 86_400_000))
  const startOfDayIso = `${todayIst}T00:00:00+05:30`

  const { data: gyms, error: gymsErr } = await supabase
    .from('gyms')
    .select('id, name, settings')
    .not('status', 'in', '(suspended,cancelled)')

  if (gymsErr) {
    console.error('[owner-daily-summary] gyms query:', gymsErr.message)
    return new Response(JSON.stringify({ error: gymsErr.message }), { status: 500 })
  }

  let sent = 0
  let skipped = 0
  let failed = 0

  for (const gym of gyms ?? []) {
    const { data: owner } = await supabase
      .from('profiles')
      .select('id')
      .eq('gym_id', gym.id)
      .eq('role', 'owner')
      .maybeSingle()
    if (!owner) { skipped++; continue }

    const { data: already } = await supabase
      .from('notifications_log')
      .select('id')
      .eq('gym_id', gym.id)
      .eq('type', 'owner_daily_summary')
      .gte('created_at', `${todayIst}T00:00:00Z`)
      .limit(1)
    if (already?.length) { skipped++; continue }

    const [paymentsRes, checkinsRes, dueRes] = await Promise.all([
      supabase
        .from('payments')
        .select('amount, invoices!inner(gym_id, is_demo_data)')
        .eq('invoices.gym_id', gym.id)
        .eq('invoices.is_demo_data', false)
        .eq('status', 'succeeded')
        .gte('created_at', startOfDayIso),
      supabase
        .from('check_ins')
        .select('id', { count: 'exact', head: true })
        .eq('gym_id', gym.id)
        .eq('is_demo_data', false)
        .gte('checked_in_at', startOfDayIso),
      supabase
        .from('members')
        .select('id', { count: 'exact', head: true })
        .eq('gym_id', gym.id)
        .eq('status', 'active')
        .eq('is_demo_data', false)
        .eq('next_payment_date', tomorrowIst),
    ])

    const collected = (paymentsRes.data ?? []).reduce(
      (sum, p) => sum + (Number(p.amount) || 0), 0
    )
    const checkins = checkinsRes.count ?? 0
    const dueTomorrow = dueRes.count ?? 0

    if (collected === 0 && checkins === 0 && dueTomorrow === 0) { skipped++; continue }

    const currency = (gym.settings as Record<string, unknown> | null)?.currency as string ?? 'INR'
    const money = new Intl.NumberFormat('en-IN', {
      style: 'currency', currency, maximumFractionDigits: 0,
    }).format(collected)

    const body = [
      `${money} collected today`,
      `${checkins} check-in${checkins === 1 ? '' : 's'}`,
      dueTomorrow > 0 ? `${dueTomorrow} member${dueTomorrow === 1 ? '' : 's'} due tomorrow` : null,
    ].filter(Boolean).join(' · ')

    const title = "Today's summary"
    const url = '/staff/dashboard'

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
          data: { type: 'owner_daily_summary', gym_id: gym.id, deep_link: url },
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
      type: 'owner_daily_summary',
      status: ok ? 'sent' : 'failed',
      sent_at: ok ? new Date().toISOString() : null,
      error: ok ? null : errorText.slice(0, 500),
    })

    if (ok) {
      await supabase.from('staff_notifications').insert({ user_id: owner.id, gym_id: gym.id, title, body, url })
      sent++
    } else {
      console.error(`[owner-daily-summary] OneSignal error (gym ${gym.id}):`, errorText)
      failed++
    }
  }

  console.log(`[owner-daily-summary] sent=${sent} skipped=${skipped} failed=${failed}`)
  return new Response(JSON.stringify({ sent, skipped, failed }), { status: 200 })
})
