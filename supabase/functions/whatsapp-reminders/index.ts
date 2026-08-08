/**
 * WhatsApp reminder job — sends via a single shared MSG91 WhatsApp number
 * (not per-gym credentials). Gyms opt in via gyms.whatsapp_reminder_enabled
 * + whatsapp_reminder_days. Each configured offset is one nudge: [3, 7] → one
 * message when 7 days remain, another when 3 remain.
 *
 * Reminders are keyed off members.next_payment_date — the field staff set
 * when adding/renewing a member — not memberships.ends_at, which stays null
 * for the normal open-ended staff-added membership flow and is only ever
 * populated by the web self-registration path. Mirrors push-reminders'
 * date-matching logic.
 *
 * Every attempt (sent / failed / quota-exhausted) writes one row to
 * notifications_log with channel='whatsapp', type='reminder'.
 *
 * Two call modes:
 *   - No body / empty body → daily batch run across all gyms (cron).
 *   - { gym_id } in body → manual "Send now" for one gym only, triggered from
 *     the app. Requires the caller's JWT to belong to that gym (checked below).
 *
 * Credits model:
 *   - Each gym gets a free monthly quota based on plan/legacy status (planQuota() below).
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
 *   MSG91_TEMPLATE_NAME     (fallback template when gyms.whatsapp_template is
 *                            unset or names a template not in TEMPLATES below,
 *                            defaults to "payment_reminder")
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

const DAY_MS = 86400000

interface GymSettings {
  id: string
  name: string
  plan: string
  legacy_pricing: boolean
  whatsapp_reminder_enabled: boolean
  whatsapp_reminder_days: number[]
  whatsapp_credits: number
  whatsapp_monthly_quota_used: number
  whatsapp_template: string | null
}

/** Legacy (₹249, pre-price-change) gyms keep the old 100/mo cap regardless of
 * plan value; new tiers get their own cap. Keyed off legacy_pricing rather
 * than plan_price since plan_price is also used ad hoc for manual overrides. */
function planQuota(gym: { plan: string; legacy_pricing?: boolean }): number {
  if (gym.legacy_pricing) return 100
  if (gym.plan === 'pro') return 500
  if (gym.plan === 'elite') return 1500
  return 0
}

function dateStr(d: Date) {
  return d.toISOString().split('T')[0]
}

/**
 * Approved MSG91 templates the gym can pick between (gyms.whatsapp_template).
 * Key = MSG91 template name, value = how to fill its variable slots.
 * Adding a newly-approved template = one entry here + one entry in
 * _kWhatsAppTemplates in lib/features/staff/settings/reminders_screen.dart.
 *
 * ponytail: plain map, no DB table for templates — the edge function has to
 * know each template's variable layout anyway, so a table would only duplicate
 * half of it and let the two drift.
 */
type Vars = Record<string, { type: 'text'; value: string }>
interface Template {
  lang: string
  vars: (firstName: string, daysLeft: number, gymName: string) => Vars
}

// All approved templates happen to share the same three slots
// ({{1}} name, {{2}} days left, {{3}} gym name) — only wording and language
// differ. A template with a different slot layout just gets its own `vars`.
const sharedVars: Template['vars'] = (firstName, daysLeft, gymName) => ({
  body_1: { type: 'text', value: firstName },
  body_2: { type: 'text', value: String(daysLeft) },
  body_3: { type: 'text', value: gymName },
})

const TEMPLATES: Record<string, Template> = {
  // EN: "Hi {{1}}! Your membership expires in {{2}} days. Please contact {{3}} to renew."
  payment_reminder: { lang: MSG91_TEMPLATE_LANG, vars: sharedVars },
  // HI: "Hi {{1}}! 👋 आपकी {{3}} की मेंबरशिप {{2}} दिन में खत्म होने वाली है…"
  payment_reminder_2: { lang: 'hi', vars: sharedVars },
  // EN: "Hi {{1}}, just a quick reminder that your {{3}} membership will expire in {{2}} days…"
  payment_due_3: { lang: 'en', vars: sharedVars },
}

async function sendReminder(
  phone: string,
  firstName: string,
  daysLeft: number,
  gymName: string,
  templateName: string,
) {
  const template = TEMPLATES[templateName]
  if (!template) throw new Error(`unknown whatsapp template "${templateName}"`)

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
          name: templateName,
          language: { code: template.lang, policy: 'deterministic' },
          to_and_components: [{
            to: [withCountryCode],
            components: template.vars(firstName, daysLeft, gymName),
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

// ponytail: fire-and-await, one row per member. Batching only matters above a
// few hundred sends per run, and quota caps us well below that.
// notifications_log.status is CHECK-constrained to sent|failed|pending, so a
// quota-exhausted skip is logged as 'failed' with the reason in `error`.
async function logSend(
  gymId: string,
  memberId: string,
  status: 'sent' | 'failed',
  error?: string,
) {
  const { error: logErr } = await supabase.from('notifications_log').insert({
    gym_id: gymId,
    member_id: memberId,
    channel: 'whatsapp',
    type: 'reminder',
    status,
    sent_at: status === 'sent' ? new Date().toISOString() : null,
    error: error ?? null,
  })
  if (logErr) console.error('[whatsapp-reminders] log insert failed', logErr)
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
    .select('id, name, plan, legacy_pricing, whatsapp_reminder_enabled, whatsapp_reminder_days, whatsapp_credits, whatsapp_monthly_quota_used, whatsapp_template')
    .eq('whatsapp_reminder_enabled', true)
  if (filterGymId) gymsQuery = gymsQuery.eq('id', filterGymId)

  const { data: gyms, error: gymsErr } = await gymsQuery as { data: GymSettings[] | null; error: unknown }
  if (gymsErr) {
    console.error('[whatsapp-reminders] gyms query failed', gymsErr)
    return new Response('Query failed', { status: 500 })
  }

  const today = dateStr(new Date())
  const todayMs = Date.parse(`${today}T00:00:00Z`)

  let sent = 0
  for (const gym of gyms ?? []) {
    const days: number[] = gym.whatsapp_reminder_days ?? []
    if (!days.length) continue

    // Window, not exact-date match: anyone due between today and the widest
    // configured offset. An exact match only fired on one calendar day per
    // cycle, so a member added late or a cron blip skipped them permanently.
    const maxDays = Math.max(...days)
    const until = new Date()
    until.setUTCDate(until.getUTCDate() + maxDays)

    const { data: members, error: membersErr } = await supabase
      .from('members')
      .select('id, first_name, phone, next_payment_date')
      .eq('gym_id', gym.id)
      .eq('status', 'active')
      .gte('next_payment_date', today)
      .lte('next_payment_date', dateStr(until))
      .not('phone', 'is', null)

    if (membersErr) {
      console.error(`[whatsapp-reminders] members query (gym ${gym.id}):`, membersErr)
      continue
    }
    if (!members?.length) continue

    // A window means the same member matches on every day of it, so we need to
    // know what was already sent. Each configured offset is one bucket: days
    // [3,7] → a 7-day bucket covering 7..4 days left, a 3-day bucket covering
    // 3..0. A member gets one message per bucket, so [3,7] really does nudge
    // twice. The bucket's start date is derivable from the member's own due
    // date (due - offset), so no extra column is needed to tell them apart.
    const cooldownFrom = new Date()
    cooldownFrom.setUTCDate(cooldownFrom.getUTCDate() - (maxDays + 1))
    const { data: recent } = await supabase
      .from('notifications_log')
      .select('member_id, sent_at')
      .eq('gym_id', gym.id)
      .eq('channel', 'whatsapp')
      .eq('type', 'reminder')
      .eq('status', 'sent')
      .gte('sent_at', cooldownFrom.toISOString())

    const sentAtByMember = new Map<string, number[]>()
    for (const row of recent ?? []) {
      if (!row.member_id || !row.sent_at) continue
      const list = sentAtByMember.get(row.member_id) ?? []
      list.push(Date.parse(row.sent_at))
      sentAtByMember.set(row.member_id, list)
    }

    const ascDays = [...days].sort((a, b) => a - b)
    const quota = planQuota(gym)
    // Unknown/removed template name falls back to the default rather than
    // failing every send for that gym.
    const templateName = gym.whatsapp_template && TEMPLATES[gym.whatsapp_template]
      ? gym.whatsapp_template
      : MSG91_TEMPLATE_NAME

    for (const member of members) {
      if (!member.phone) continue

      const dueMs = Date.parse(`${member.next_payment_date}T00:00:00Z`)
      const daysLeft = Math.max(0, Math.round((dueMs - todayMs) / DAY_MS))

      // Smallest configured offset the member still qualifies for.
      const bucket = ascDays.find(d => daysLeft <= d)
      if (bucket === undefined) continue

      // Already messaged since this bucket opened? Then this nudge is done.
      const bucketStartMs = dueMs - bucket * DAY_MS
      const prior = sentAtByMember.get(member.id) ?? []
      if (prior.some(ts => ts >= bucketStartMs)) continue

      const quotaLeft = quota - gym.whatsapp_monthly_quota_used
      const usingQuota = quotaLeft > 0
      if (!usingQuota && gym.whatsapp_credits <= 0) {
        await logSend(gym.id, member.id, 'failed', 'no quota or credits left')
        continue
      }

      try {
        await sendReminder(member.phone, member.first_name, daysLeft, gym.name, templateName)
        sent++
        await logSend(gym.id, member.id, 'sent')
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
        await logSend(gym.id, member.id, 'failed', (e as Error).message)
      }
    }
  }

  return new Response(JSON.stringify({ sent }), { status: 200, headers: { 'Content-Type': 'application/json' } })
})
