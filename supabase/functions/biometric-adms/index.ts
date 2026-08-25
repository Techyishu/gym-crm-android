/**
 * ZKTeco / eSSL ADMS push receiver.
 *
 * Device config (device menu → Comm → Cloud Server):
 *   Server Mode    : ADMS
 *   Server Address : bio.gymcrm.in
 *   Port           : 58594
 *   HTTPS          : OFF
 *   Server Path    : (leave blank / default)
 *
 * Gym identity is resolved from the device's own hardware serial number
 * (sent automatically as ?SN=... on every ADMS request — not something the
 * gym configures). Staff pairs a device once in-app by typing that serial
 * number in (Settings → Biometric Device → Connect a Device), which
 * upserts a row into biometric_devices(gym_id, device_sn).
 *
 * Full request shapes (device appends these itself):
 *   GET  /iclock/cdata?SN=...                      — handshake
 *   POST /iclock/cdata?SN=...&table=ATTLOG          — attendance push
 *   POST /iclock/cdata?SN=...&table=OPERLOG         — enroll/op log (acked, ignored)
 *   POST /iclock/getrequest?SN=...                  — command poll
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// Writes into the same error_logs table the app itself uses, so a failed
// punch is visible without digging through function logs. Awaited (not
// fire-and-forget) — the edge runtime can terminate right after the
// response returns, which would silently drop an un-awaited insert.
async function logError(message: string, gymId: string | null, deviceInfo?: Record<string, unknown>) {
  const { error } = await supabase.from('error_logs').insert({
    gym_id: gymId,
    source: 'biometric-adms',
    message,
    page: 'biometric-checkin',
    device_info: deviceInfo ?? null,
  })
  if (error) console.error('[biometric-adms] failed to write error_logs:', error.message)
}

// ── ADMS handshake response ────────────────────────────────────────────────────
// Exact format ZKTeco/eSSL expects. Fields control push interval and behaviour.
function handshakeResponse(sn: string): Response {
  const body = [
    `GET OPTION FROM: ${sn}`,
    'Stamp=0',
    'OpStamp=0',
    'ErrorDelay=30',
    'Delay=10',
    'TransTimes=00:00;14:05',
    'TransInterval=1',
    'TransFlag=TransData AttLog OpLog EnrollUser',
    'Realtime=1',
    'Encrypt=None',
    'ServerVer=2.2',
    'PushProtVer=2.2',
  ].join('\r\n')

  return new Response(body, {
    status: 200,
    headers: { 'Content-Type': 'text/plain' },
  })
}

// ── ATTLOG parser ──────────────────────────────────────────────────────────────
// Each line: employee_id<TAB>datetime<TAB>verify_mode<TAB>in_out<TAB>...\r\n
interface AttRecord {
  employeeId: string
  datetime: string
  verifyMode: string
}

// Devices vary in whether they zero-pad employee IDs ("001" vs "1") — strip
// leading zeros so a punch always matches however staff typed the ID in-app.
function normalizeEmployeeId(id: string): string {
  return id.replace(/^0+(?=\d)/, '')
}

function parseAttlog(body: string): AttRecord[] {
  // Some real devices delimit records with commas instead of newlines
  // (confirmed against hardware-tested implementations) — split on either.
  return body
    .split(/\r\n|\r|,|\n/)
    .map(l => l.trim())
    .filter(Boolean)
    .map(line => {
      const parts = line.split('\t')
      return {
        employeeId: normalizeEmployeeId(parts[0]?.trim() ?? ''),
        datetime:   parts[1]?.trim() ?? '',
        verifyMode: parts[2]?.trim() === '4' ? 'face' : 'fingerprint',
      }
    })
    .filter(r => r.employeeId)
}

// ── Main handler ───────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  const url    = new URL(req.url)
  const params = url.searchParams
  // Uppercase so a case mismatch between the device's SN and what staff
  // typed while pairing can never silently break the match.
  const sn     = (params.get('SN') ?? '').trim().toUpperCase()

  if (!sn) {
    return new Response('Missing SN — device did not send a serial number', { status: 400 })
  }

  // ── Device lookup by serial number ────────────────────────────────────
  const { data: device, error } = await supabase
    .from('biometric_devices')
    .select('id, gym_id')
    .eq('device_sn', sn)
    .maybeSingle()

  if (error || !device) {
    await logError(`Unknown device SN=${sn} — not paired to any gym`, null, { sn })
    return new Response(
      `Unknown device SN=${sn} — pair it first in-app (Settings → Biometric Device → Connect a Device)`,
      { status: 401 },
    )
  }

  await supabase.from('biometric_devices').update({ last_ping_at: new Date().toISOString() }).eq('id', device.id)

  // ── Route by path + method ────────────────────────────────────────────────────

  // Command poll — device asks "any jobs for me?"
  if (url.pathname.endsWith('/getrequest')) {
    return new Response('OK', { status: 200 })
  }

  // Handshake — device fetches config
  if (req.method === 'GET') {
    return handshakeResponse(sn)
  }

  // Attendance / operation log push
  if (req.method === 'POST') {
    const table = params.get('table') ?? ''

    if (table !== 'ATTLOG') {
      // OPERLOG, USERLOG, etc. — just ack
      return new Response('OK: 0', { status: 200 })
    }

    // ── Process attendance punches ───────────────────────────────────────────
    const body    = await req.text()
    const records = parseAttlog(body)

    if (records.length === 0) {
      return new Response('OK: 0', { status: 200 })
    }

    let inserted = 0

    for (const rec of records) {
      // Look up member by (gym_id, biometric_id)
      const { data: member } = await supabase
        .from('members')
        .select('id, first_name, last_name, status')
        .eq('gym_id', device.gym_id)
        .eq('biometric_id', rec.employeeId)
        .maybeSingle()

      if (!member) {
        // Unknown employee ID — gym staff can assign biometric_id in the member edit sheet
        await logError(`Unknown employee_id=${rec.employeeId} — no member has this Biometric ID`, device.gym_id, { sn, employeeId: rec.employeeId })
        continue
      }

      if (member.status !== 'active') {
        // Device authenticates locally — it already let them in. We can't
        // block that, only alert the owner it happened.
        const name = `${member.first_name} ${member.last_name ?? ''}`.trim()
        await supabase.rpc('notify_owner_expired_checkin', {
          p_gym_id: device.gym_id,
          p_member_name: name,
          p_member_status: member.status,
          p_method: 'biometric',
        })
        continue
      }

      // Device sends local IST wall-clock time with no TZ marker — convert to real UTC.
      const checkedInAtUtc = new Date(new Date(rec.datetime + 'Z').getTime() - 5.5 * 60 * 60 * 1000)

      // Duplicate check: one punch per member per calendar day (IST).
      // Derive the IST calendar date from the already-correct UTC instant above —
      // using UTC-only getters/setters avoids the day-overflow bug that broke this
      // for any punch after ~18:30 IST when it used local setHours()/getFullYear().
      const istView = new Date(checkedInAtUtc.getTime() + 5.5 * 60 * 60 * 1000)
      const dayStartUtc = new Date(
        Date.UTC(istView.getUTCFullYear(), istView.getUTCMonth(), istView.getUTCDate())
        - 5.5 * 60 * 60 * 1000,
      )

      const { data: existing } = await supabase
        .from('check_ins')
        .select('id')
        .eq('member_id', member.id)
        .gte('checked_in_at', dayStartUtc.toISOString())
        .limit(1)
        .maybeSingle()

      if (existing) continue

      const { error: insErr } = await supabase.from('check_ins').insert({
        member_id:     member.id,
        gym_id:        device.gym_id,
        method:        'biometric',
        checked_in_at: checkedInAtUtc.toISOString(),
      })

      if (!insErr) {
        inserted++
      } else {
        await logError(`Failed to insert check-in: ${insErr.message}`, device.gym_id, { sn, employeeId: rec.employeeId })
      }
    }

    return new Response(`OK: ${inserted}`, { status: 200 })
  }

  return new Response('OK', { status: 200 })
})
