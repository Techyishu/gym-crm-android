import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPush } from '../_shared/fcm.ts'

// Runs every 10 min via pg_cron -> public.trigger_send_push_notifications() ->
// net.http_post. Sends any push_notifications rows that are due, via FCM,
// targeted at profiles.id (staff). Mirrors the push-reminders function's
// auth pattern: verify_jwt is off, this checks its own CRON_SECRET instead.
//
// Also writes one row per recipient into staff_notifications so the same
// message shows up in the app's own notification inbox, not just as an OS
// push (which the user may miss, dismiss, or have disabled).

const CRON_SECRET = Deno.env.get('CRON_SECRET')!

type Segment = 'all' | 'trial_active' | 'trial_expired' | 'no_activity'
type Recipient = { id: string; gym_id: string }

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

  async function resolveRecipients(segment: Segment): Promise<Recipient[]> {
    const { data: gyms } = await supabase.from('gyms').select('id, trial_ends_at, plan').order('created_at', { ascending: false })
    if (!gyms?.length) return []

    const now = new Date()
    let filtered = gyms
    if (segment === 'trial_active') filtered = gyms.filter(g => g.trial_ends_at && new Date(g.trial_ends_at) > now && g.plan === 'starter')
    else if (segment === 'trial_expired') filtered = gyms.filter(g => g.trial_ends_at && new Date(g.trial_ends_at) <= now && g.plan === 'starter')
    else if (segment === 'no_activity') {
      const gymIds = gyms.map(g => g.id)
      const { data: checkIns } = await supabase.from('check_ins').select('gym_id').in('gym_id', gymIds)
      const activeGymIds = new Set((checkIns ?? []).map(c => c.gym_id))
      filtered = gyms.filter(g => !activeGymIds.has(g.id))
    }
    if (!filtered.length) return []

    const { data: profiles } = await supabase.from('profiles').select('id, gym_id').in('gym_id', filtered.map(g => g.id))
    return (profiles ?? []) as Recipient[]
  }

  const { data: due, error: dueErr } = await supabase
    .from('push_notifications')
    .select('id, title, body, url, segment, target_user_id')
    .eq('status', 'scheduled')
    .lte('scheduled_at', new Date().toISOString())

  if (dueErr) {
    console.error('[send-push-notifications] query:', dueErr.message)
    return new Response(JSON.stringify({ error: dueErr.message }), { status: 500 })
  }
  if (!due?.length) return new Response(JSON.stringify({ sent: 0 }), { status: 200 })

  let sent = 0
  let failed = 0

  for (const n of due) {
    let recipients: Recipient[]
    if (n.target_user_id) {
      const { data: profile } = await supabase.from('profiles').select('id, gym_id').eq('id', n.target_user_id).maybeSingle()
      recipients = profile ? [profile as Recipient] : []
    } else {
      recipients = await resolveRecipients(n.segment as Segment)
    }
    const userIds = recipients.map(r => r.id)

    if (!userIds.length) {
      await supabase.from('push_notifications').update({ status: 'sent', sent_at: new Date().toISOString(), recipient_count: 0 }).eq('id', n.id)
      sent++
      continue
    }

    const { ok, error: errorText } = await sendPush(supabase, userIds, {
      title: n.title,
      body: n.body,
      data: n.url ? { deep_link: n.url } : {},
    })

    if (ok) {
      await supabase.from('push_notifications').update({ status: 'sent', sent_at: new Date().toISOString(), recipient_count: userIds.length }).eq('id', n.id)
      await supabase.from('staff_notifications').insert(
        recipients.map(r => ({ user_id: r.id, gym_id: r.gym_id, title: n.title, body: n.body, url: n.url }))
      )
      sent++
    } else {
      console.error(`[send-push-notifications] FCM error (notification ${n.id}):`, errorText)
      await supabase.from('push_notifications').update({ status: 'failed', error: errorText.slice(0, 500) }).eq('id', n.id)
      failed++
    }
  }

  console.log(`[send-push-notifications] sent=${sent} failed=${failed}`)
  return new Response(JSON.stringify({ sent, failed }), { status: 200 })
})
