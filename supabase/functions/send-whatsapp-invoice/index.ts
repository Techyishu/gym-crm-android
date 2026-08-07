/**
 * Sends the "invoice generated" WhatsApp message via the shared MSG91 number
 * (same integrated number as whatsapp-reminders). Fired by a DB trigger
 * (trg_notify_invoice_whatsapp) right after any `insert into invoices`, no
 * matter which of the app's creation paths produced it: the
 * generate_monthly_invoices() cron, the create_invoice_for_membership()
 * trigger on new memberships, or a staff-created invoice from the app.
 *
 * Steps: fetch invoice + member + gym -> render a PDF -> upload to the
 * public `invoice-pdfs` bucket (same path convention as the app's manual
 * "Share as PDF" button: `${invoiceId}.pdf`) -> send MSG91 template with a
 * dynamic-URL button pointing at that PDF.
 *
 * Uses the same whatsapp_credits / whatsapp_monthly_quota_used pool as
 * whatsapp-reminders — one shared per-gym WhatsApp budget across both
 * features, not gated on whatsapp_reminder_enabled since this is a
 * transactional message, not a marketing nudge.
 *
 * Supabase secrets required: MSG91_AUTHKEY, MSG91_INTEGRATED_NUMBER
 * (same secrets whatsapp-reminders already uses).
 *
 * Handles two events, both pending MSG91 approval, both reusing the same
 * `invoice-pdfs` bucket link as their button:
 *
 * "invoice_generated" — fired by trg_notify_invoice_whatsapp (AFTER INSERT):
 * "Hi {{1}}! A new invoice #{{2}} for ₹{{3}} has been generated for your
 * membership at {{4}}. Please tap the button below to view and download
 * your invoice at your convenience."
 *
 * "invoice_paid" — fired by trg_notify_invoice_paid_whatsapp
 * (AFTER UPDATE OF status, new.status = 'paid'):
 * "Hi {{1}}, we've received your payment of ₹{{2}} for invoice #{{3}} at
 * {{4}}. Thank you for your continued membership — tap below to view your
 * receipt."
 *
 * Button (both): dynamic URL, static prefix
 * ".../storage/v1/object/public/invoice-pdfs/", var = "{invoiceId}.pdf"
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { PDFDocument, StandardFonts, rgb } from 'https://esm.sh/pdf-lib@1.17.1'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const MSG91_AUTHKEY = Deno.env.get('MSG91_AUTHKEY')!
const MSG91_INTEGRATED_NUMBER = Deno.env.get('MSG91_INTEGRATED_NUMBER') ?? '919472968913'
const TEMPLATE_LANG = 'en'

type InvoiceEvent = 'generated' | 'paid'
const TEMPLATE_NAME: Record<InvoiceEvent, string> = {
  generated: 'invoice_generated',
  paid: 'invoice_paid',
}

const PLAN_QUOTA: Record<string, number> = { pro: 100, starter: 0 }

function invoiceNumber(id: string, createdAt: string) {
  const dt = new Date(createdAt)
  const month = `${dt.getUTCFullYear()}${String(dt.getUTCMonth() + 1).padStart(2, '0')}`
  const shortId = id.replace(/-/g, '').slice(0, 6).toUpperCase()
  return `INV-${month}-${shortId}`
}

// ponytail: plain single-page layout via pdf-lib's built-in Helvetica — not
// pixel parity with the app's branded PDF (invoice_pdf.dart, custom fonts,
// discount rows, notes), just enough for a customer to see what they owe.
// Upgrade to matching the app's design if customers ask for it.
async function buildInvoicePdf(inv: Record<string, unknown>): Promise<Uint8Array> {
  const member = inv.members as Record<string, unknown> | null
  const gym = inv.gyms as Record<string, unknown> | null

  const gymName = (gym?.name as string) ?? 'Gym'
  const memberName = member
    ? `${member.first_name ?? ''} ${member.last_name ?? ''}`.trim()
    : 'Member'
  const amount = (inv.amount as number) ?? 0
  const description = (inv.description as string) || 'Membership fee'
  const status = (inv.status as string) ?? 'open'
  const invNum = invoiceNumber(inv.id as string, inv.created_at as string)
  const dueAt = inv.due_at ? new Date(inv.due_at as string).toDateString() : '-'

  const pdf = await PDFDocument.create()
  const page = pdf.addPage([595, 400]) // A4 width, short page
  const font = await pdf.embedFont(StandardFonts.Helvetica)
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold)

  let y = 350
  const draw = (text: string, opts: { size?: number; f?: typeof font; x?: number } = {}) => {
    page.drawText(text, { x: opts.x ?? 40, y, size: opts.size ?? 12, font: opts.f ?? font, color: rgb(0.1, 0.1, 0.1) })
    y -= (opts.size ?? 12) + 10
  }

  draw(gymName.toUpperCase(), { size: 18, f: bold })
  draw(`INVOICE ${invNum}`, { size: 11 })
  y -= 8
  draw(`Bill to: ${memberName}`, { size: 13, f: bold })
  draw(`Due: ${dueAt}`, { size: 10 })
  draw(`Status: ${status.toUpperCase()}`, { size: 10 })
  y -= 8
  draw(description, { size: 12 })
  draw(`Amount: ₹${amount}`, { size: 16, f: bold })

  return pdf.save()
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  const { invoice_id: invoiceId, event } = await req.json().catch(() => ({}))
  if (!invoiceId) return new Response('invoice_id required', { status: 400 })
  const invoiceEvent: InvoiceEvent = event === 'paid' ? 'paid' : 'generated'

  const { data: inv, error: invErr } = await supabase
    .from('invoices')
    .select(
      '*, members(first_name, last_name, phone), gyms(id, name, plan, whatsapp_credits, whatsapp_monthly_quota_used)',
    )
    .eq('id', invoiceId)
    .single()

  if (invErr || !inv) {
    console.error('[send-whatsapp-invoice] invoice fetch failed', invErr)
    return new Response('Invoice not found', { status: 404 })
  }

  const member = inv.members as Record<string, unknown> | null
  const gym = inv.gyms as Record<string, unknown> | null
  const phone = member?.phone as string | null
  if (!phone || !gym) return new Response('No phone or gym on invoice', { status: 200 })

  const quota = PLAN_QUOTA[gym.plan as string] ?? 0
  const quotaUsed = (gym.whatsapp_monthly_quota_used as number) ?? 0
  const credits = (gym.whatsapp_credits as number) ?? 0
  const usingQuota = quota - quotaUsed > 0
  if (!usingQuota && credits <= 0) {
    await logSend(gym.id as string, inv.member_id as string, invoiceEvent, 'failed', 'no quota or credits left')
    return new Response(JSON.stringify({ sent: false, reason: 'no quota' }), { status: 200 })
  }

  try {
    const pdfBytes = await buildInvoicePdf(inv)
    const fileName = `${invoiceId}.pdf`

    const { error: uploadErr } = await supabase.storage
      .from('invoice-pdfs')
      .upload(fileName, pdfBytes, { contentType: 'application/pdf', upsert: true })
    if (uploadErr) throw new Error(`upload failed: ${uploadErr.message}`)

    const to = phone.replace(/\D/g, '')
    const withCountryCode = to.startsWith('91') ? to : `91${to}`
    const firstName = (member?.first_name as string) ?? 'there'
    const invNum = invoiceNumber(inv.id as string, inv.created_at as string)

    // invoice_generated: {{1}} name, {{2}} invoice#, {{3}} amount, {{4}} gym
    // invoice_paid:      {{1}} name, {{2}} amount,   {{3}} invoice#, {{4}} gym
    const bodyVars = invoiceEvent === 'paid'
      ? [firstName, String(inv.amount), invNum, gym.name as string]
      : [firstName, invNum, String(inv.amount), gym.name as string]

    const res = await fetch('https://control.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/', {
      method: 'POST',
      headers: { accept: 'application/json', authkey: MSG91_AUTHKEY, 'content-type': 'application/json' },
      body: JSON.stringify({
        integrated_number: MSG91_INTEGRATED_NUMBER,
        content_type: 'template',
        payload: {
          type: 'template',
          template: {
            name: TEMPLATE_NAME[invoiceEvent],
            language: { code: TEMPLATE_LANG, policy: 'deterministic' },
            to_and_components: [{
              to: [withCountryCode],
              components: {
                body_1: { type: 'text', value: bodyVars[0] },
                body_2: { type: 'text', value: bodyVars[1] },
                body_3: { type: 'text', value: bodyVars[2] },
                body_4: { type: 'text', value: bodyVars[3] },
                button_1: { subtype: 'url', type: 'text', value: fileName },
              },
            }],
          },
          messaging_product: 'whatsapp',
        },
      }),
    })

    const data = await res.json()
    if (data.hasError) throw new Error(data.errors ?? 'MSG91 send failed')

    await logSend(gym.id as string, inv.member_id as string, invoiceEvent, 'sent')
    if (usingQuota) {
      await supabase.from('gyms').update({ whatsapp_monthly_quota_used: quotaUsed + 1 }).eq('id', gym.id as string)
    } else {
      await supabase.from('gyms').update({ whatsapp_credits: credits - 1 }).eq('id', gym.id as string)
    }

    return new Response(JSON.stringify({ sent: true }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  } catch (e) {
    console.error('[send-whatsapp-invoice] send failed', gym.id, e)
    await logSend(gym.id as string, inv.member_id as string, invoiceEvent, 'failed', (e as Error).message)
    return new Response(JSON.stringify({ sent: false, error: (e as Error).message }), { status: 200 })
  }
})

async function logSend(
  gymId: string,
  memberId: string,
  event: InvoiceEvent,
  status: 'sent' | 'failed',
  error?: string,
) {
  const { error: logErr } = await supabase.from('notifications_log').insert({
    gym_id: gymId,
    member_id: memberId,
    channel: 'whatsapp',
    type: event === 'paid' ? 'invoice_paid' : 'invoice_generated',
    status,
    sent_at: status === 'sent' ? new Date().toISOString() : null,
    error: error ?? null,
  })
  if (logErr) console.error('[send-whatsapp-invoice] log insert failed', logErr)
}
