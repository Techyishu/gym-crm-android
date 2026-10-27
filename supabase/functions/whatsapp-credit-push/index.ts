import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPush } from '../_shared/fcm.ts'

// Runs daily via pg_cron -> public.trigger_whatsapp_credit_push(). Pushes the
// gym OWNER when their WhatsApp balance (free monthly quota + purchased
// credits, same pool whatsapp-reminders and send-whatsapp-invoice draw from)
// is low or exhausted.
//
// Rate: per quota cycle, "low" once, "exhausted" once plus one follow-up two
// days later. The old once-per-day dedupe sent ~15-20 identical pushes a month
// to the same gym, which trained owners to ignore them.

const CRON_SECRET = Deno.env.get('CRON_SECRET')!

/** "Low" fires with this many reminders left, unless app_config says otherwise. */
const DEFAULT_LOW_LEFT = 20
const EXHAUSTED_FOLLOW_UP_MS = 2 * 86400000

/**
 * Start of the gym's current quota cycle. The quota resets on the day-of-month
 * of plan_started_at (else created_at), clamped to short months, the same rule
 * as public.reset_whatsapp_quota_anniversaries().
 */
function cycleStart(anchorIso: string, now = new Date()): string {
  const anchorDay = new Date(anchorIso).getUTCDate()
  const day = (y: number, m: number) =>
    Math.min(anchorDay, new Date(Date.UTC(y, m + 1, 0)).getUTCDate())
  let y = now.getUTCFullYear()
  let m = now.getUTCMonth()
  if (now.getUTCDate() < day(y, m)) {
    m -= 1
    if (m < 0) { m = 11; y -= 1 }
  }
  return new Date(Date.UTC(y, m, day(y, m))).toISOString()
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

  // Only gyms using WhatsApp reminders. whatsapp_quota is the DB computed
  // column (public.whatsapp_quota(gyms)), so the price-plan quota lives in one
  // place instead of being mirrored here.
  const { data: gyms, error: gymsErr } = await supabase
    .from('gyms')
    .select('id, plan, plan_expires_at, plan_started_at, created_at, whatsapp_quota, whatsapp_credits, whatsapp_monthly_quota_used')
    .eq('whatsapp_reminder_enabled', true)

  if (gymsErr) {
    console.error('[whatsapp-credit-push] gyms query:', gymsErr.message)
    return new Response(JSON.stringify({ error: gymsErr.message }), { status: 500 })
  }

  const { data: lowRow } = await supabase
    .from('app_config')
    .select('value')
    .eq('key', 'whatsapp_low_warning')
    .maybeSingle()
  const LOW_LEFT = Number(lowRow?.value) > 0 ? Number(lowRow!.value) : DEFAULT_LOW_LEFT

  let sent = 0
  let skipped = 0
  let failed = 0
  const now = new Date()

  for (const gym of gyms ?? []) {
    // Paying gyms only. Unpaid gyms sit on their 10 signup credits and were
    // being told "running low" every single day.
    const quota = gym.whatsapp_quota ?? 0
    const expired = gym.plan_expires_at != null && new Date(gym.plan_expires_at) <= now
    if (quota <= 0 || gym.plan === 'free' || gym.plan === 'trial' || expired) continue

    const quotaLeft = Math.max(quota - (gym.whatsapp_monthly_quota_used ?? 0), 0)
    const remaining = quotaLeft + (gym.whatsapp_credits ?? 0)

    let type: string
    let title: string
    let body: string
    if (remaining <= 0) {
      type = 'whatsapp_credit_exhausted'
      title = 'WhatsApp reminders paused'
      body = `You've used this month's ${quota} reminders, so members aren't getting fee reminders. Buy more to restart them.`
    } else if (remaining <= LOW_LEFT) {
      type = 'whatsapp_credit_low'
      title = 'WhatsApp reminders running low'
      body = `Only ${remaining} WhatsApp reminder${remaining === 1 ? '' : 's'} left this month. Buy more so fee reminders don't stop.`
    } else {
      continue
    }

    const since = cycleStart(gym.plan_started_at ?? gym.created_at, now)
    const { data: prior } = await supabase
      .from('notifications_log')
      .select('created_at')
      .eq('gym_id', gym.id)
      .eq('type', type)
      .eq('status', 'sent')
      .gte('created_at', since)
      .order('created_at', { ascending: false })
    const priorCount = prior?.length ?? 0
    const due = type === 'whatsapp_credit_low'
      ? priorCount === 0
      : priorCount === 0 ||
        (priorCount === 1 && now.getTime() - Date.parse(prior![0].created_at) >= EXHAUSTED_FOLLOW_UP_MS)
    if (!due) { skipped++; continue }

    const { data: owner } = await supabase
      .from('profiles')
      .select('id')
      .eq('gym_id', gym.id)
      .eq('role', 'owner')
      .maybeSingle()
    if (!owner) { skipped++; continue }

    const url = '/staff/reminders'

    const { ok, error: errorText } = await sendPush(supabase, [owner.id], {
      title,
      body,
      data: { type, gym_id: gym.id, remaining, deep_link: url },
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
      await supabase.from('staff_notifications').insert({ user_id: owner.id, gym_id: gym.id, title, body, url })
      sent++
    } else {
      console.error(`[whatsapp-credit-push] FCM error (gym ${gym.id}):`, errorText)
      failed++
    }
  }

  console.log(`[whatsapp-credit-push] sent=${sent} skipped=${skipped} failed=${failed}`)
  return new Response(JSON.stringify({ sent, skipped, failed }), { status: 200 })
})
