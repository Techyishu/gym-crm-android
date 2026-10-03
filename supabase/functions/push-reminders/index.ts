import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPush } from '../_shared/fcm.ts'

// Runs daily via pg_cron -> net.http_post. For every gym with push reminders
// enabled, finds members whose next_payment_date lands exactly on one of the
// gym's configured day-offsets and sends an FCM push to their devices
// (device_tokens rows for members.user_id, written by the app after sign-in).

const CRON_SECRET = Deno.env.get('CRON_SECRET')!

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
    .select('id, name, push_reminder_days')
    .eq('push_reminder_enabled', true)

  if (gymsErr) {
    console.error('[push-reminders] gyms query:', gymsErr.message)
    return new Response(JSON.stringify({ error: gymsErr.message }), { status: 500 })
  }

  let sent = 0
  let failed = 0
  let skipped = 0

  for (const gym of gyms ?? []) {
    const days: number[] = gym.push_reminder_days ?? []

    for (const daysBefore of days) {
      const target = new Date()
      target.setUTCDate(target.getUTCDate() + daysBefore)
      const targetStr = dateStr(target)

      const { data: members, error: membersErr } = await supabase
        .from('members')
        .select('id, user_id, first_name')
        .eq('gym_id', gym.id)
        .eq('status', 'active')
        .eq('next_payment_date', targetStr)
        .not('user_id', 'is', null)

      if (membersErr) {
        console.error(`[push-reminders] members query (gym ${gym.id}):`, membersErr.message)
        continue
      }
      if (!members?.length) continue

      const { ok, error } = await sendPush(supabase, members.map(m => m.user_id as string), {
        title: 'Membership renewal',
        body: `Your gym membership expires in ${daysBefore} day${daysBefore === 1 ? '' : 's'}. Renew to keep your access!`,
        data: { type: 'renewal_reminder', gym_id: gym.id, days_before: daysBefore },
      })
      if (!ok) console.error(`[push-reminders] FCM error (gym ${gym.id}):`, error)

      const logRows = members.map(m => ({
        gym_id: gym.id,
        member_id: m.id,
        channel: 'push',
        type: 'reminder',
        status: ok ? 'sent' : 'failed',
        sent_at: ok ? new Date().toISOString() : null,
      }))
      await supabase.from('notifications_log').insert(logRows)

      if (ok) sent += members.length
      else failed += members.length
    }
  }

  console.log(`[push-reminders] sent=${sent} failed=${failed} skipped=${skipped}`)
  return new Response(JSON.stringify({ sent, failed, skipped }), { status: 200 })
})
