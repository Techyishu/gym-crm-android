import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Firebase Cloud Messaging (HTTP v1) sender shared by every push edge function.
// Needs the FCM_SERVICE_ACCOUNT secret: the full service-account JSON from
// Firebase Console -> Project settings -> Service accounts, for the project
// the app's google-services.json / GoogleService-Info.plist belong to.
//
// Recipients are Supabase user ids; tokens come from public.device_tokens
// (written by the register_device_token RPC from the app).

type ServiceAccount = { project_id: string; client_email: string; private_key: string }

let cachedToken: { value: string; expiresAt: number } | null = null

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
  if (!raw) throw new Error('FCM_SERVICE_ACCOUNT secret is not set')
  return JSON.parse(raw)
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value

  const now = Math.floor(Date.now() / 1000)
  const unsigned =
    b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' })) +
    '.' +
    b64url(JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }))

  const der = Uint8Array.from(
    atob(sa.private_key.replace(/-----[^-]+-----|\s/g, '')),
    (c) => c.charCodeAt(0),
  )
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned))

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  })
  if (!res.ok) throw new Error(`FCM auth failed: ${await res.text()}`)
  const json = await res.json()
  cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 }
  return cachedToken.value
}

export type PushResult = { ok: boolean; sent: number; error: string }

/**
 * Sends one push to every registered device of the given users.
 * ok is false only if a send failed for a reason other than a dead token
 * (dead tokens are deleted from device_tokens and don't count as failures).
 * Users with no registered device are fine: ok stays true with sent = 0,
 * matching how the old OneSignal call behaved for unknown external ids.
 * `data` values must be strings (FCM requirement) — numbers are stringified.
 */
export async function sendPush(
  supabase: SupabaseClient,
  userIds: string[],
  msg: { title: string; body: string; data?: Record<string, string | number> },
): Promise<PushResult> {
  if (!userIds.length) return { ok: true, sent: 0, error: '' }

  const { data: rows, error: tokErr } = await supabase
    .from('device_tokens')
    .select('token')
    .in('user_id', userIds)
  if (tokErr) return { ok: false, sent: 0, error: `tokens query: ${tokErr.message}` }
  const tokens = (rows ?? []).map((r) => r.token as string)
  if (!tokens.length) return { ok: true, sent: 0, error: '' }

  let sa: ServiceAccount
  let bearer: string
  try {
    sa = serviceAccount()
    bearer = await accessToken(sa)
  } catch (e) {
    return { ok: false, sent: 0, error: (e as Error).message }
  }

  const data = Object.fromEntries(Object.entries(msg.data ?? {}).map(([k, v]) => [k, String(v)]))
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`

  let sent = 0
  const errors: string[] = []
  const dead: string[] = []

  // Chunked so a gym with hundreds of members doesn't open hundreds of sockets at once.
  for (let i = 0; i < tokens.length; i += 50) {
    await Promise.all(tokens.slice(i, i + 50).map(async (token) => {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: msg.title, body: msg.body },
              data,
              android: { priority: 'high' },
              apns: { payload: { aps: { sound: 'default' } } },
            },
          }),
        })
        if (res.ok) { sent++; return }
        const text = await res.text()
        // INVALID_ARGUMENT also covers a bad payload, so only treat it as a
        // dead token when the message names the registration token.
        if (res.status === 404 || text.includes('UNREGISTERED') ||
            (text.includes('INVALID_ARGUMENT') && /registration token/i.test(text))) {
          dead.push(token)
        } else {
          errors.push(text.slice(0, 200))
        }
      } catch (e) {
        errors.push((e as Error).message)
      }
    }))
  }

  if (dead.length) await supabase.from('device_tokens').delete().in('token', dead)

  return { ok: errors.length === 0, sent, error: errors.join(' | ').slice(0, 500) }
}
