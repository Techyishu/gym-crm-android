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

function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '')
  return digits.startsWith('91') ? digits : `91${digits}`
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

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  const body = await req.json().catch(() => ({}))
  const accessToken = body?.accessToken as string | undefined
  if (!accessToken) return new Response('accessToken is required', { status: 400 })

  try {
    const phone = await verifyMsg91AccessToken(accessToken)
    const userId = await findOrCreateUserId(phone)

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
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    console.error('[verify-phone-otp] failed', e)
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
