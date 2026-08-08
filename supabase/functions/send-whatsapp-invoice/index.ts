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

/** Legacy (₹249, pre-price-change) gyms keep the old 100/mo cap regardless of
 * plan value; new tiers get their own cap. Keyed off legacy_pricing rather
 * than plan_price since plan_price is also used ad hoc for manual overrides. */
function planQuota(gym: { plan: string; legacy_pricing?: boolean }): number {
  if (gym.legacy_pricing) return 100
  if (gym.plan === 'pro') return 500
  if (gym.plan === 'elite') return 1500
  return 0
}

function invoiceNumber(id: string, createdAt: string) {
  const dt = new Date(createdAt)
  const month = `${dt.getUTCFullYear()}${String(dt.getUTCMonth() + 1).padStart(2, '0')}`
  const shortId = id.replace(/-/g, '').slice(0, 6).toUpperCase()
  return `INV-${month}-${shortId}`
}

// ponytail: pdf-lib's built-in Helvetica, not the app's Manrope (avoids a
// network font fetch inside the edge function) — but layout/sections/colors
// mirror invoice_pdf.dart section-for-section so the PDF a customer gets on
// WhatsApp matches what staff see in-app: header, status badge, dates,
// bill-to, line item, discount, total, notes, footer.
const STATUS_INFO: Record<string, { label: string; color: [number, number, number] }> = {
  paid: { label: 'PAID', color: [0.0, 0.42, 0.0] },
  open: { label: 'PENDING', color: [0.85, 0.45, 0.0] },
  failed: { label: 'FAILED', color: [0.7, 0.1, 0.1] },
  void: { label: 'VOID', color: [0.4, 0.4, 0.4] },
}

function fmtDate(d: string | null) {
  if (!d) return '-'
  return new Date(d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
}

async function buildInvoicePdf(inv: Record<string, unknown>): Promise<Uint8Array> {
  const member = inv.members as Record<string, unknown> | null
  const gym = inv.gyms as Record<string, unknown> | null
  const settings = (gym?.settings as Record<string, unknown>) ?? {}

  const gymName = ((gym?.name as string) ?? 'Gym').toUpperCase()
  const address = settings.address as string | undefined
  const phone = settings.phone as string | undefined
  const website = settings.website as string | undefined

  const memberName = member
    ? `${member.first_name ?? ''} ${member.last_name ?? ''}`.trim()
    : 'Member'
  const memberEmail = (member?.email as string) ?? ''

  const status = (inv.status as string) ?? 'open'
  const amount = (inv.amount as number) ?? 0
  const originalAmount = inv.original_amount as number | null
  const discountAmount = (inv.discount_amount as number) ?? 0
  const hasDiscount = discountAmount > 0
  const notes = inv.notes as string | null
  const description = (inv.description as string) || 'Membership fee'

  const invNum = invoiceNumber(inv.id as string, inv.created_at as string)
  const issueDate = fmtDate(inv.created_at as string)
  const dueDate = fmtDate(inv.due_at as string | null)
  const paidOn = inv.paid_at ? fmtDate(inv.paid_at as string) : null

  const statusInfo = STATUS_INFO[status] ?? { label: 'DRAFT', color: [0.4, 0.4, 0.4] }

  const pdf = await PDFDocument.create()
  const page = pdf.addPage([595, 700])
  const font = await pdf.embedFont(StandardFonts.Helvetica)
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold)

  const marginX = 40
  let y = 650

  const grey = (v: number) => rgb(v, v, v)
  const text = (
    t: string,
    opts: { size?: number; f?: typeof font; x?: number; color?: readonly [number, number, number] } = {},
  ) => {
    const [r, g, b] = opts.color ?? [0.1, 0.1, 0.1]
    page.drawText(t, { x: opts.x ?? marginX, y, size: opts.size ?? 11, font: opts.f ?? font, color: rgb(r, g, b) })
  }
  const nl = (h = 16) => { y -= h }
  const hr = (color = grey(0.85)) => {
    page.drawLine({ start: { x: marginX, y }, end: { x: 555, y }, thickness: 1, color })
    nl(14)
  }

  // Header: gym block (left) + invoice#/status (right)
  text(gymName, { size: 18, f: bold })
  const rightX = 400
  const yStart = y
  page.drawText('INVOICE', { x: rightX, y: yStart, size: 9, font, color: grey(0.5) })
  page.drawText(invNum, { x: rightX, y: yStart - 16, size: 13, font: bold })
  page.drawRectangle({ x: rightX, y: yStart - 36, width: 90, height: 16, color: rgb(...statusInfo.color) })
  page.drawText(statusInfo.label, { x: rightX + 6, y: yStart - 32, size: 9, font: bold, color: rgb(1, 1, 1) })

  nl(18)
  if (address) { text(address, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (phone) { text(phone, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (website) { text(website, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }

  nl(10)
  page.drawLine({ start: { x: marginX, y }, end: { x: 555, y }, thickness: 2, color: rgb(0.1, 0.1, 0.1) })
  nl(24)

  // Dates row
  text('ISSUE DATE', { size: 9, color: [0.5, 0.5, 0.5] })
  page.drawText('DUE DATE', { x: marginX + 160, y, size: 9, font, color: grey(0.5) })
  if (paidOn) page.drawText('PAID ON', { x: marginX + 320, y, size: 9, font, color: grey(0.5) })
  nl(15)
  text(issueDate, { size: 12, f: bold })
  page.drawText(dueDate, { x: marginX + 160, y, size: 12, font: bold })
  if (paidOn) page.drawText(paidOn, { x: marginX + 320, y, size: 12, font: bold, color: rgb(0.0, 0.42, 0.0) })
  nl(24)
  hr()

  // Bill to
  text('BILL TO', { size: 9, color: [0.5, 0.5, 0.5] })
  nl(16)
  text(memberName, { size: 14, f: bold })
  nl(16)
  if (memberEmail) { text(memberEmail, { size: 11, color: [0.4, 0.4, 0.4] }); nl(16) }
  nl(6)
  hr()

  // Line item
  text('DESCRIPTION', { size: 9, color: [0.5, 0.5, 0.5] })
  page.drawText('AMOUNT', { x: 480, y, size: 9, font, color: grey(0.5) })
  nl(16)
  hr(grey(0.9))
  text(description, { size: 13 })
  page.drawText(`Rs. ${originalAmount ?? amount}`, { x: 460, y, size: 13, font: bold })
  nl(20)
  hr()

  if (hasDiscount) {
    text('DISCOUNT', { size: 10, color: [0.0, 0.42, 0.0] })
    page.drawText(`- Rs. ${discountAmount}`, { x: 460, y, size: 13, font: bold, color: rgb(0.0, 0.42, 0.0) })
    nl(20)
    hr()
  }

  // Total
  nl(6)
  text('TOTAL DUE', { size: 10, color: [0.4, 0.4, 0.4] })
  page.drawText(`Rs. ${amount}`, { x: 430, y: y - 2, size: 22, font: bold })
  nl(28)
  hr()

  if (notes) {
    nl(4)
    text('NOTES', { size: 9, color: [0.5, 0.5, 0.5] })
    nl(16)
    text(notes, { size: 11, color: [0.4, 0.4, 0.4] })
    nl(18)
  }

  // Footer, pinned near bottom
  const footerY = 40
  page.drawLine({ start: { x: marginX, y: footerY + 14 }, end: { x: 555, y: footerY + 14 }, thickness: 1, color: grey(0.85) })
  page.drawText(invNum, { x: marginX, y: footerY, size: 9, font, color: grey(0.6) })
  page.drawText('Powered by GymCRM', { x: 470, y: footerY, size: 9, font, color: grey(0.6) })

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
      '*, members(first_name, last_name, phone, email), gyms(id, name, plan, legacy_pricing, whatsapp_credits, whatsapp_monthly_quota_used, settings)',
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

  const quota = planQuota(gym as { plan: string; legacy_pricing?: boolean })
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
