/**
 * ZKTeco / eSSL ADMS push receiver.
 *
 * Device config (in device web UI or LCD menu):
 *   Server address : <project>.supabase.co
 *   Port           : 443
 *   Server path    : /functions/v1/biometric-adms/<GYM_TOKEN>
 *
 * The device appends /iclock/cdata and /iclock/getrequest to that path,
 * so full URLs are:
 *   GET  /functions/v1/biometric-adms/<TOKEN>/iclock/cdata   — handshake
 *   POST /functions/v1/biometric-adms/<TOKEN>/iclock/cdata?table=ATTLOG
 *   POST /functions/v1/biometric-adms/<TOKEN>/iclock/cdata?table=OPERLOG
 *   POST /functions/v1/biometric-adms/<TOKEN>/iclock/getrequest
 *
 * Fallback (older devices without path config):
 *   Append ?key=<GYM_TOKEN> to the base URL — token extracted from query string.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

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

function parseAttlog(body: string): AttRecord[] {
  return body
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(Boolean)
    .map(line => {
      const parts = line.split('\t')
      return {
        employeeId: parts[0]?.trim() ?? '',
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
  const sn     = params.get('SN') ?? ''

  // ── Token extraction ─────────────────────────────────────────────────────────
  // Primary: token is a path segment after "biometric-adms"
  //   e.g. /functions/v1/biometric-adms/abc123/iclock/cdata
  // Fallback: ?key=<token>
  const parts    = url.pathname.split('/')
  const funcIdx  = parts.indexOf('biometric-adms')
  const pathToken = funcIdx >= 0 ? (parts[funcIdx + 1] ?? '') : ''
  const token    = pathToken || (params.get('key') ?? '')
  // Sub-path after token: "iclock/cdata" or "iclock/getrequest"
  const subPath  = parts.slice(funcIdx + 2).join('/')

  if (!token) {
    return new Response('Missing token — configure Server Path in device settings', { status: 400 })
  }

  // ── Device lookup ─────────────────────────────────────────────────────────────
  const { data: device, error } = await supabase
    .from('biometric_devices')
    .select('id, gym_id')
    .eq('token', token)
    .maybeSingle()

  if (error || !device) {
    return new Response('Invalid token', { status: 401 })
  }

  // Update last ping + capture device SN on first connect
  const pingUpdate: Record<string, unknown> = { last_ping_at: new Date().toISOString() }
  if (sn) pingUpdate.device_sn = sn
  await supabase.from('biometric_devices').update(pingUpdate).eq('id', device.id)

  // ── Route by path + method ────────────────────────────────────────────────────

  // Command poll — device asks "any jobs for me?"
  if (subPath === 'iclock/getrequest') {
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
        .select('id, status')
        .eq('gym_id', device.gym_id)
        .eq('biometric_id', rec.employeeId)
        .maybeSingle()

      if (!member) {
        // Unknown employee ID — skip silently
        // Gym staff can assign biometric_id in the member edit sheet
        console.warn(`[biometric-adms] Unknown employee_id=${rec.employeeId} gym=${device.gym_id}`)
        continue
      }

      if (member.status !== 'active') continue

      // Duplicate check: one punch per member per calendar day (IST = UTC+5:30)
      const ist = new Date(rec.datetime + 'Z')
      ist.setHours(ist.getHours() + 5, ist.getMinutes() + 30)
      const dayStartIst = new Date(ist.getFullYear(), ist.getMonth(), ist.getDate())
      const dayStartUtc = new Date(dayStartIst.getTime() - 5.5 * 60 * 60 * 1000)

      const { data: existing } = await supabase
        .from('check_ins')
        .select('id')
        .eq('member_id', member.id)
        .gte('checked_in_at', dayStartUtc.toISOString())
        .limit(1)
        .maybeSingle()

      if (existing) continue

      // Device sends local IST wall-clock time with no TZ marker — convert to real UTC.
      const checkedInAtUtc = new Date(new Date(rec.datetime + 'Z').getTime() - 5.5 * 60 * 60 * 1000)

      const { error: insErr } = await supabase.from('check_ins').insert({
        member_id:     member.id,
        gym_id:        device.gym_id,
        method:        'biometric',
        checked_in_at: checkedInAtUtc.toISOString(),
      })

      if (!insErr) inserted++
    }

    return new Response(`OK: ${inserted}`, { status: 200 })
  }

  return new Response('OK', { status: 200 })
})
