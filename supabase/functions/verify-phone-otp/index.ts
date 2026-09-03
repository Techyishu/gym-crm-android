/**
 * Mobile OTP login (Android app only). MSG91's Flutter widget SDK
 * (sendotp_flutter_sdk) only proves phone ownership client-side — it does
 * not create a Supabase session. This function is the bridge:
 *
 *   1. Client runs OTPWidget.sendOTP / verifyOTP, gets back an `access-token`.
 *   2. Client POSTs { accessToken, phone } here (phone is only a fallback
 *      hint — the verified phone MSG91 itself returns is what's trusted).
 *   3. This function re-verifies the access-token server-side against MSG91
 *      (control.msg91.com/api/v5/widget/verifyAccessToken) using the real
 *      MSG91_AUTHKEY secret, never trusting the client's claim alone.
 *   4. Finds-or-creates the Supabase auth user for that phone:
 *        a. phone_identities exact match → use that user_id.
 *        b. else profiles.phone / members.phone match → backfill
 *           phone_identities (links pre-existing email/Google accounts that
 *           already have a phone on file, so they don't get a duplicate
 *           account on first phone-OTP login).
 *        c. else admin.createUser with a synthetic email (new account —
 *           router sends them to /gym-setup, same as a first Google login).
 *   5. Mints a magiclink via admin.generateLink and returns { email,
 *      hashedToken } — the client finishes the login itself by calling
 *      supabase.auth.verifyOTP(email, token: hashedToken, type: magiclink),
 *      the same officially-supported call already used for email OTP login.
 *
 * Supabase secrets required:
 *   MSG91_AUTHKEY (already set — shared with whatsapp-reminders)
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const MSG91_AUTHKEY = Deno.env.get('MSG91_AUTHKEY')!

// Canonical form is always 91 + the 10 national digits. Deciding by prefix
// instead (`startsWith('91')`) silently breaks every Indian number that
// itself begins with 91 — e.g. 9116669678, a valid 10-digit mobile — which
// then never matched its own members row.
function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '').replace(/^0+/, '')
  return `91${digits.slice(-10)}`
}

async function verifyMsg91AccessToken(accessToken: string): Promise<string> {
  const res = await fetch('https://control.msg91.com/api/v5/widget/verifyAccessToken', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ authkey: MSG91_AUTHKEY, 'access-token': accessToken }),
  })
  const data = await res.json()
  if (data?.type !== 'success') {
    throw new Error(`MSG91 access-token verification failed: ${JSON.stringify(data)}`)
  }

  // MSG91's response shape for the verified identifier isn't documented for
  // this endpoint — check the common places it could show up, including
  // `message` being the phone number itself as a plain string (that's the
  // shape MSG91's own SDK uses for the sibling sendOTP call's reqId).
  const messageLooksLikePhone =
    typeof data?.message === 'string' && /^\+?\d{6,15}$/.test(data.message)

  const verifiedPhone =
    (messageLooksLikePhone ? data.message : undefined) ??
    data?.message?.mobile ??
    data?.message?.identifier ??
    data?.mobile ??
    data?.identifier
  if (!verifiedPhone) {
    throw new Error(`MSG91 response did not include a verified phone number: ${JSON.stringify(data)}`)
  }
  return normalizePhone(String(verifiedPhone))
}

// Member self-serve signup AND password reset: phone must match an existing
// `members` row for THIS specific gym (staff must have already added the
// member — just not invited them). Deliberately does not touch
// `phone_identities` — that table is keyed by phone alone (staff-only), and a
// member could share a phone with a staff account (e.g. family running the
// gym); mixing them would let one login resolve to the other's account.
//
// An already-claimed row (user_id set) is NOT an error: the caller has just
// proved ownership of that phone over SMS, which is exactly the proof a
// password reset needs, so we hand back the same user and let the client's
// "set password" step overwrite it.
async function findOrCreateMemberUserId(phone: string, gymId: string): Promise<{ userId: string; error?: string }> {
  const { data: members, error } = await supabase
    .from('members')
    .select('id, phone, user_id')
    .eq('gym_id', gymId)
  if (error) return { userId: '', error: 'Could not look up members for this gym' }

  const match = (members ?? []).find((m: { phone: string | null }) =>
    m.phone && normalizePhone(m.phone) === phone
  ) as { id: string; phone: string | null; user_id: string | null } | undefined

  if (!match) {
    return { userId: '', error: 'No member found with this number at this gym. Ask your gym to add you as a member first.' }
  }
  if (match.user_id) return { userId: match.user_id }

  const digits = phone.replace(/^91/, '').slice(-10)
  const syntheticEmail = `${digits}@member.gymcrm.internal`
  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    phone,
    email: syntheticEmail,
    phone_confirm: true,
    email_confirm: true,
  })
  if (createErr || !created?.user) return { userId: '', error: createErr?.message ?? 'Failed to create account' }

  await supabase.from('members').update({ user_id: created.user.id }).eq('id', match.id)
  return { userId: created.user.id }
}

async function findOrCreateUserId(phone: string): Promise<string> {
  const { data: existing } = await supabase
    .from('phone_identities')
    .select('user_id')
    .eq('phone', phone)
    .maybeSingle()
  if (existing?.user_id) return existing.user_id as string

  const [{ data: profileMatch }, { data: memberMatch }] = await Promise.all([
    supabase.from('profiles').select('id').eq('phone', phone).maybeSingle(),
    supabase.from('members').select('user_id').eq('phone', phone).maybeSingle(),
  ])
  const linkedUserId = profileMatch?.id ?? memberMatch?.user_id
  if (linkedUserId) {
    await supabase.from('phone_identities').insert({ phone, user_id: linkedUserId })
    return linkedUserId as string
  }

  const syntheticEmail = `p${phone}@phone.gymcrm.internal`
  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    phone,
    email: syntheticEmail,
    phone_confirm: true,
    email_confirm: true,
  })
  if (createErr || !created?.user) throw new Error(createErr?.message ?? 'Failed to create user')

  await supabase.from('phone_identities').insert({ phone, user_id: created.user.id })
  return created.user.id
}

// The web build calls this cross-origin, so the browser sends a CORS
// preflight first. Without these the OPTIONS gets the 405 below and the real
// POST is never sent — the member sees a generic failure after already
// burning an SMS. Native (Android/iOS) sends no preflight, which is why this
// only ever broke on web.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors })

  const body = await req.json().catch(() => ({}))
  const accessToken = body?.accessToken as string | undefined
  const gymId = body?.gymId as string | undefined
  if (!accessToken) return new Response('accessToken is required', { status: 400, headers: cors })

  try {
    const phone = await verifyMsg91AccessToken(accessToken)

    let userId: string
    if (gymId) {
      const result = await findOrCreateMemberUserId(phone, gymId)
      if (result.error) {
        return new Response(JSON.stringify({ error: result.error }), {
          status: 400,
          headers: { ...cors, 'Content-Type': 'application/json' },
        })
      }
      userId = result.userId
    } else {
      userId = await findOrCreateUserId(phone)
    }

    const { data: userRecord, error: userErr } = await supabase.auth.admin.getUserById(userId)
    if (userErr || !userRecord?.user?.email) throw new Error('Could not resolve user email')

    const { data: link, error: linkErr } = await supabase.auth.admin.generateLink({
      type: 'magiclink',
      email: userRecord.user.email,
    })
    if (linkErr || !link) throw new Error(linkErr?.message ?? 'Failed to generate session link')

    const hashedToken = link.properties?.hashed_token
    if (!hashedToken) throw new Error('No hashed_token in generated link')

    return new Response(
      JSON.stringify({ email: userRecord.user.email, hashedToken }),
      { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    console.error('[verify-phone-otp] failed', e)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }
})
