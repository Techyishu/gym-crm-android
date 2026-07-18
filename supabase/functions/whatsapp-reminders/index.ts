/**
 * WhatsApp reminder job — sends via a single shared MSG91 WhatsApp number
 * (not per-gym credentials). Gyms opt in via gyms.whatsapp_reminder_enabled
 * + whatsapp_reminder_days (e.g. [3, 1] → remind 3 days and 1 day before the
 * member's next payment is due).
 *
 * Reminders are keyed off members.next_payment_date — the field staff set
 * when adding/renewing a member — not memberships.ends_at, which stays null
 * for the normal open-ended staff-added membership flow and is only ever
 * populated by the web self-registration path. Mirrors push-reminders'
 * date-matching logic.
 *
 * Two call modes:
 *   - No body / empty body → daily batch run across all gyms (cron).
 *   - { gym_id } in body → manual "Send now" for one gym only, triggered from
 *     the app. Requires the caller's JWT to belong to that gym (checked below).
 *
 * Credits model:
 *   - Each gym gets a free monthly quota based on plan (PLAN_QUOTA below).
 *     Tracked by whatsapp_monthly_quota_used, reset to 0 on the 1st of each
 *     month by the "whatsapp-quota-monthly-reset" cron job (pure SQL, no
 *     edge function call needed for that part).
 *   - whatsapp_credits is a purchased top-up balance that never auto-resets
 *     and rolls over — consumed only after the monthly quota runs out.
 *
 * Scheduled via pg_cron + pg_net: cron job "whatsapp-reminders-daily", runs
 * 09:00 IST daily (see migration whatsapp_reminders_cron).
 *
 * Supabase secrets required:
 *   MSG91_AUTHKEY           (supabase secrets set MSG91_AUTHKEY=xxx)
 *   MSG91_INTEGRATED_NUMBER (the shared WhatsApp number, digits only, defaults to 919472968913)
 *   MSG91_TEMPLATE_NAME     (approved MSG91 template name, defaults to "payment_reminder")
 *   MSG91_TEMPLATE_LANG     (approved MSG91 template language code, defaults to en)
 *
 * "payment_reminder" template body:
 * "Hi {{1}}! Your membership expires in {{2}} days. Please contact {{3}} to renew."
 * — {{1}} = first name, {{2}} = days left, {{3}} = gym name.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const MSG91_AUTHKEY = Deno.env.get('MSG91_AUTHKEY')!
const MSG91_INTEGRATED_NUMBER = Deno.env.get('MSG91_INTEGRATED_NUMBER') ?? '919472968913'
const MSG91_TEMPLATE_NAME = Deno.env.get('MSG91_TEMPLATE_NAME') ?? 'payment_reminder'
const MSG91_TEMPLATE_LANG = Deno.env.get('MSG91_TEMPLATE_LANG') ?? 'en'

const PLAN_QUOTA: Record<string, number> = { pro: 100, starter: 0 }

interface GymSettings {
  id: string
  name: string
  plan: string
  whatsapp_reminder_enabled: boolean
  whatsapp_reminder_days: number[]
  whatsapp_credits: number
  whatsapp_monthly_quota_used: number
}

function dateStr(d: Date) {
  return d.toISOString().split('T')[0]
}

async function sendReminder(phone: string, firstName: string, daysLeft: number, gymName: string) {
  const to = phone.replace(/\D/g, '')
  const withCountryCode = to.startsWith('91') ? to : `91${to}`

  const res = await fetch('https://control.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      authkey: MSG91_AUTHKEY,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      integrated_number: MSG91_INTEGRATED_NUMBER,
      content_type: 'template',
      payload: {
        type: 'template',
        template: {
          name: MSG91_TEMPLATE_NAME,
          language: { code: MSG91_TEMPLATE_LANG, policy: 'deterministic' },
          to_and_components: [{
            to: [withCountryCode],
            components: {
              body_1: { type: 'text', value: firstName },
              body_2: { type: 'text', value: String(daysLeft) },
              body_3: { type: 'text', value: gymName },
            },
          }],
        },
        messaging_product: 'whatsapp',
      },
    }),
  })

  const data = await res.json()
  if (data.hasError) throw new Error(data.errors ?? 'MSG91 send failed')
  return data
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  const body = await req.json().catch(() => ({}))
  const filterGymId = body?.gym_id as string | undefined

  // Manual per-gym trigger — verify the caller actually belongs to this gym
  // before letting them spend that gym's credits/quota.
  if (filterGymId) {
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    const { data: userData, error: userError } = await supabase.auth.getUser(jwt)
    if (userError || !userData.user) return new Response('Unauthorized', { status: 401 })

    const { data: profile } = await supabase
      .from('profiles')
      .select('gym_id')
      .eq('id', userData.user.id)
      .single()
    if (profile?.gym_id !== filterGymId) return new Response('Forbidden', { status: 403 })
  }

  let gymsQuery = supabase
    .from('gyms')
    .select('id, name, plan, whatsapp_reminder_enabled, whatsapp_reminder_days, whatsapp_credits, whatsapp_monthly_quota_used')
    .eq('whatsapp_reminder_enabled', true)
  if (filterGymId) gymsQuery = gymsQuery.eq('id', filterGymId)

  const { data: gyms, error: gymsErr } = await gymsQuery as { data: GymSettings[] | null; error: unknown }
  if (gymsErr) {
    console.error('[whatsapp-reminders] gyms query failed', gymsErr)
    return new Response('Query failed', { status: 500 })
  }

  let sent = 0
  for (const gym of gyms ?? []) {
    for (const daysBefore of gym.whatsapp_reminder_days ?? []) {
      const target = new Date()
      target.setUTCDate(target.getUTCDate() + daysBefore)
      const targetStr = dateStr(target)

      const { data: members, error: membersErr } = await supabase
        .from('members')
        .select('first_name, phone')
        .eq('gym_id', gym.id)
        .eq('status', 'active')
        .eq('next_payment_date', targetStr)
        .not('phone', 'is', null)

      if (membersErr) {
        console.error(`[whatsapp-reminders] members query (gym ${gym.id}):`, membersErr)
        continue
      }
      if (!members?.length) continue

      const quota = PLAN_QUOTA[gym.plan] ?? 0

      for (const member of members) {
        if (!member.phone) continue

        const quotaLeft = quota - gym.whatsapp_monthly_quota_used
        const usingQuota = quotaLeft > 0
        if (!usingQuota && gym.whatsapp_credits <= 0) continue

        try {
          await sendReminder(member.phone, member.first_name, daysBefore, gym.name)
          sent++
          if (usingQuota) {
            gym.whatsapp_monthly_quota_used += 1
            await supabase.from('gyms')
              .update({ whatsapp_monthly_quota_used: gym.whatsapp_monthly_quota_used })
              .eq('id', gym.id)
          } else {
            gym.whatsapp_credits -= 1
            await supabase.from('gyms')
              .update({ whatsapp_credits: gym.whatsapp_credits })
              .eq('id', gym.id)
          }
        } catch (e) {
          console.error('[whatsapp-reminders] send failed', gym.id, e)
        }
      }
    }
  }

  return new Response(JSON.stringify({ sent }), { status: 200, headers: { 'Content-Type': 'application/json' } })
})
