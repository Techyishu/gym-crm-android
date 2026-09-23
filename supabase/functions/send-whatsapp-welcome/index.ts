/**
 * Sends the "welcome" WhatsApp message via the shared MSG91 number — called
 * directly by the app (not a DB trigger) from the "$name added" confirmation
 * sheet's "Send welcome message" button in members_screen.dart. Staff picks
 * the moment and the language per member; there is no auto-send on insert,
 * deliberately, so a bulk add never blasts a batch of them at once.
 *
 * Uses the same whatsapp_credits / whatsapp_monthly_quota_used pool as
 * whatsapp-reminders and send-whatsapp-invoice — one shared per-gym budget
 * across all three.
 *
 * Supabase secrets required: MSG91_AUTHKEY, MSG91_INTEGRATED_NUMBER (same
 * secrets the other two WhatsApp functions already use).
 *
 * Approved MSG91 templates (both UTILITY-shaped, both pending Meta's actual
 * category verdict on submission):
 *
 * "welcome_1" (EN):
 * "Hi {{1}}, welcome to {{2}}! 🎉 Your membership is now active. We're glad
 * to have you with us. Need anything? Call us: 📞 {{3}} See you at the gym! 💪"
 *
 * "welcome_hin_1" (Hinglish, submitted under the 'en' language code — same
 * convention as payment_reminder/payment_due_3, which are also Latin-script
 * Hinglish under 'en'; payment_reminder_2 is the only Devanagari one and
 * uses 'hi'):
 * "Hi {{1}} 👋 {{2}} family mein aapka swagat hai! 🎉 Aapki membership ab
 * active hai. Kisi bhi help ke liye humein call karein: 📞 {{3}} see you in
 * the gym! 💪"
 *
 * {{1}} = member first name, {{2}} = gym name, {{3}} = gym contact number.
 *
 * gym_contact = the owner's own phone, exactly what setup_gym() wrote to
 * profiles.phone at signup — NOT gym_invoice_settings.contact_phone, which
 * only ~10% of gyms have ever filled in.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { TEMPLATES, pickTemplate, normalizeIndianPhone } from './templates.ts'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const MSG91_AUTHKEY = Deno.env.get('MSG91_AUTHKEY')!
const MSG91_INTEGRATED_NUMBER = Deno.env.get('MSG91_INTEGRATED_NUMBER') ?? '919472968913'

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
    type: 'welcome',
    status,
    sent_at: status === 'sent' ? new Date().toISOString() : null,
    error: error ?? null,
  })
  if (logErr) console.error('[send-whatsapp-welcome] log insert failed', logErr)
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
  const { data: userData, error: userError } = await supabase.auth.getUser(jwt)
  if (userError || !userData.user) return new Response('Unauthorized', { status: 401 })

  const { member_id: memberId, template } = await req.json().catch(() => ({}))
  if (!memberId) return new Response('member_id required', { status: 400 })
  const templateName = pickTemplate(template)

  const { data: member, error: memberErr } = await supabase
    .from('members')
    .select('id, first_name, phone, gym_id')
    .eq('id', memberId)
    .single()
  if (memberErr || !member) return new Response('Member not found', { status: 404 })
  if (!member.phone) return new Response('Member has no phone', { status: 200 })

  // The caller must actually belong to this member's gym — same check
  // whatsapp-reminders' manual "Send now" mode already does.
  const { data: access } = await supabase
    .from('staff_gym_access')
    .select('gym_id')
    .eq('profile_id', userData.user.id)
    .eq('gym_id', member.gym_id)
    .maybeSingle()
  if (!access) return new Response('Forbidden', { status: 403 })

  const { data: gym } = await supabase
    .from('gyms')
    .select('id, name')
    .eq('id', member.gym_id)
    .single()
  if (!gym) return new Response('Gym not found', { status: 404 })

  // The owner's own phone from signup (setup_gym → profiles.phone) — the
  // only reliably-populated contact number a gym has on file.
  const { data: owner } = await supabase
    .from('profiles')
    .select('phone')
    .eq('gym_id', gym.id)
    .eq('role', 'owner')
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle()
  const gymContact = owner?.phone
  if (!gymContact) {
    await logSend(gym.id, member.id, 'failed', 'no owner phone on file for gym_contact')
    return new Response(JSON.stringify({ sent: false, reason: 'no gym contact number' }), { status: 200 })
  }

  const { data: bucket, error: consumeErr } = await supabase
    .rpc('consume_whatsapp_allowance', { p_gym_id: gym.id })
  if (consumeErr) {
    console.error('[send-whatsapp-welcome] allowance rpc failed', consumeErr)
    return new Response(JSON.stringify({ sent: false, error: 'allowance check failed' }), { status: 200 })
  }
  if (!bucket) {
    await logSend(gym.id, member.id, 'failed', 'no quota or credits left')
    return new Response(JSON.stringify({ sent: false, reason: 'no quota' }), { status: 200 })
  }

  try {
    const withCountryCode = normalizeIndianPhone(member.phone as string)

    const res = await fetch('https://control.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/', {
      method: 'POST',
      headers: { accept: 'application/json', authkey: MSG91_AUTHKEY, 'content-type': 'application/json' },
      body: JSON.stringify({
        integrated_number: MSG91_INTEGRATED_NUMBER,
        content_type: 'template',
        payload: {
          type: 'template',
          template: {
            name: templateName,
            language: { code: TEMPLATES[templateName].lang, policy: 'deterministic' },
            to_and_components: [{
              to: [withCountryCode],
              components: {
                body_1: { type: 'text', value: member.first_name },
                body_2: { type: 'text', value: gym.name },
                body_3: { type: 'text', value: gymContact },
              },
            }],
          },
          messaging_product: 'whatsapp',
        },
      }),
    })

    const data = await res.json()
    if (data.hasError) throw new Error(data.errors ?? 'MSG91 send failed')

    await logSend(gym.id, member.id, 'sent')
    return new Response(JSON.stringify({ sent: true }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  } catch (e) {
    console.error('[send-whatsapp-welcome] send failed', gym.id, e)
    await supabase.rpc('refund_whatsapp_allowance', { p_gym_id: gym.id, p_bucket: bucket })
    await logSend(gym.id, member.id, 'failed', (e as Error).message)
    return new Response(JSON.stringify({ sent: false, error: (e as Error).message }), { status: 200 })
  }
})
