/**
 * Staff approve (or reject) a member's portal signup request — the
 * no-SMS path for non-Indian numbers (see migration
 * 20261028120000_member_signup_requests.sql). Indian numbers still sign up
 * through verify-phone-otp.
 *
 *   POST { requestId, approve: boolean }   (caller's staff JWT required)
 *
 * On approve: creates the member's auth user on the same synthetic email
 * verify-phone-otp uses (last 10 digits @member.gymcrm.internal — the login
 * screen derives the same one), with the bcrypt hash the member chose, and
 * links it to the members row. If the member already has an account, this is
 * a password reset: only the hash is replaced.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const admin = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

// Must match memberSyntheticEmail() in the app and verify-phone-otp.
function syntheticEmail(phone: string) {
  const digits = phone.replace(/\D/g, '')
  return `${digits.slice(-10)}@member.gymcrm.internal`
}

async function linkAccount(memberId: string, existingUserId: string | null, phone: string, hash: string): Promise<string | null> {
  if (existingUserId) {
    const { error } = await admin.auth.admin.updateUserById(existingUserId, { password_hash: hash })
    return error ? 'Could not update the member\'s password.' : null
  }

  const email = syntheticEmail(phone)
  const { data: orphanId } = await admin.rpc('auth_user_id_for_email', { p_email: email })
  if (orphanId) {
    // Same rule as verify-phone-otp: only adopt an account no member row uses.
    const { count, error: countErr } = await admin
      .from('members')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', orphanId)
    if (countErr) return 'Could not check existing accounts. Please try again.'
    if ((count ?? 0) > 0) {
      return 'This mobile number is already registered to another member account.'
    }
    const { error: pwErr } = await admin.auth.admin.updateUserById(orphanId as string, { password_hash: hash })
    if (pwErr) return 'Could not set the member\'s password.'
    const { error: relinkErr } = await admin.from('members').update({ user_id: orphanId }).eq('id', memberId)
    return relinkErr ? 'Could not link the account to the member.' : null
  }

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    password_hash: hash,
  })
  if (createErr || !created?.user) return createErr?.message ?? 'Could not create the account.'

  // Without the link the account looks like a brand-new owner to the router
  // (no members row, no profile) — delete it rather than leave it half-made.
  const { error: linkErr } = await admin.from('members').update({ user_id: created.user.id }).eq('id', memberId)
  if (linkErr) {
    await admin.auth.admin.deleteUser(created.user.id)
    return 'Could not link the account to the member.'
  }
  return null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const body = await req.json().catch(() => ({}))
  const requestId = body?.requestId as string | undefined
  const approve = body?.approve === true
  if (!requestId) return json({ error: 'requestId is required' }, 400)

  // Permission check runs as the caller, so RLS helpers see their auth.uid().
  const authHeader = req.headers.get('Authorization') ?? ''
  const asCaller = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: { user: caller } } = await asCaller.auth.getUser()
  if (!caller) return json({ error: 'Not signed in' }, 401)
  const { data: allowed, error: permErr } = await asCaller.rpc('can_decide_member_signup', { p_request_id: requestId })
  if (permErr || allowed !== true) {
    return json({ error: 'This request is no longer pending, or you cannot approve members.' }, 403)
  }

  const { data: request, error: reqErr } = await admin
    .from('member_signup_requests')
    .select('id, phone, password_hash, member_id, members(user_id)')
    .eq('id', requestId)
    .single()
  if (reqErr || !request) return json({ error: 'Request not found' }, 404)

  if (approve) {
    if (!request.password_hash) return json({ error: 'Request has no password. Ask the member to sign up again.' }, 400)
    const existingUserId = (request.members as { user_id: string | null } | null)?.user_id ?? null
    const err = await linkAccount(request.member_id, existingUserId, request.phone, request.password_hash)
    if (err) {
      console.error('[approve-member-signup]', requestId, err)
      return json({ error: err }, 400)
    }
  }

  const { error: doneErr } = await admin
    .from('member_signup_requests')
    .update({
      status: approve ? 'approved' : 'rejected',
      password_hash: null,
      decided_at: new Date().toISOString(),
      decided_by: caller.id,
    })
    .eq('id', requestId)
  if (doneErr) console.error('[approve-member-signup] status update failed', doneErr)

  return json({ ok: true })
})
