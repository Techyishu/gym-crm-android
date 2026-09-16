/**
 * Renders the invoice PDF that gets attached to the WhatsApp message.
 *
 * Split out of index.ts so it can be imported (and tested) without starting a
 * server or building a Supabase client.
 */

import { PDFDocument, rgb } from 'https://esm.sh/pdf-lib@1.17.1'
import fontkit from 'https://esm.sh/@pdf-lib/fontkit@1.1.1'
import { MANROPE_BOLD, MANROPE_REGULAR, UNSUPPORTED_TEXT } from './fonts.ts'

/** pdf-lib embeds PNG and JPEG only, and the invoice settings screen also
 * accepts WebP. A logo it cannot embed — or one that fails to fetch — must
 * never stop the invoice going out. */
async function embedLogo(pdf: PDFDocument, url: unknown) {
  if (typeof url !== 'string' || !url) return null
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    const bytes = new Uint8Array(await res.arrayBuffer())
    const isPng = bytes[0] === 0x89 && bytes[1] === 0x50
    const isJpg = bytes[0] === 0xff && bytes[1] === 0xd8
    if (!isPng && !isJpg) return null
    return isPng ? await pdf.embedPng(bytes) : await pdf.embedJpg(bytes)
  } catch {
    return null
  }
}

// Every field comes from the invoice's own `settings_snapshot` — the same
// frozen row invoice_pdf.dart renders from — in the same order, the same
// Manrope, and the same currency/date formats, so the PDF a customer gets on
// WhatsApp carries the gym's invoice customisation and matches the one staff
// share from the app.
const STATUS_INFO: Record<string, { label: string; color: [number, number, number] }> = {
  paid: { label: 'PAID', color: [0.0, 0.42, 0.0] },
  open: { label: 'PENDING', color: [0.85, 0.45, 0.0] },
  failed: { label: 'FAILED', color: [0.7, 0.1, 0.1] },
  void: { label: 'VOID', color: [0.4, 0.4, 0.4] },
}

/** Mirrors formatters.dart `DateFormat('d MMM yyyy')` — no leading zero, and
 * "Sep" rather than the "Sept" en-IN would give. */
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
function fmtDate(d: string | null) {
  if (!d) return '-'
  const dt = new Date(d)
  return `${dt.getUTCDate()} ${MONTHS[dt.getUTCMonth()]} ${dt.getUTCFullYear()}`
}

/** Mirrors formatters.dart `formatCurrency` — rupees, no decimals, grouped in
 * threes. `settings_snapshot` carries no currency code, so this assumes the
 * app's INR default; a gym on another currency would read wrong here. */
function money(amount: number) {
  return `₹${Math.round(amount).toLocaleString('en-US')}`
}

/** Mirrors `formatCurrencyExact` — GST lines must sum to the total, so they
 * keep paise. */
function moneyExact(amount: number) {
  return `₹${amount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

/** Owner-entered text can hold characters outside the embedded font subset
 * (a Devanagari gym name, an emoji in the terms). pdf-lib throws on those, so
 * drop them rather than fail the whole send. */
function safe(t: string) {
  return t.replace(UNSUPPORTED_TEXT, '')
}

export async function buildInvoicePdf(inv: Record<string, unknown>): Promise<Uint8Array> {
  const member = inv.members as Record<string, unknown> | null
  const gym = inv.gyms as Record<string, unknown> | null
  // settings_snapshot / member_snapshot are NOT NULL on invoices (migration
  // 20260828062304) — frozen at issue time, so re-sending an old invoice never
  // picks up today's settings.
  const settings = (inv.settings_snapshot as Record<string, unknown>) ?? {}
  const memberSnapshot = (inv.member_snapshot as Record<string, unknown>) ?? {}

  const gymName = ((settings.gym_name as string) || (gym?.name as string) || 'Gym').toUpperCase()
  const address = settings.address as string | undefined
  const phone = settings.contact_phone as string | undefined
  const website = settings.contact_email as string | undefined
  const ownerName = settings.owner_name as string | undefined
  const gstin = settings.gstin as string | undefined
  const refundPolicy = settings.refund_policy as string | undefined
  const terms = settings.terms_and_conditions as string | undefined

  const memberName = (memberSnapshot.name as string) ||
    (member ? `${member.first_name ?? ''} ${member.last_name ?? ''}`.trim() : 'Member')
  const memberEmail = (memberSnapshot.email as string) ?? (member?.email as string) ?? ''
  const membershipId = (inv.membership_id_snapshot as string) ??
    (memberSnapshot.membership_id as string | undefined)

  const status = (inv.status as string) ?? 'open'
  const amount = (inv.amount as number) ?? 0
  const originalAmount = inv.original_amount as number | null
  const discountAmount = (inv.discount_amount as number) ?? 0
  const hasDiscount = discountAmount > 0 && settings.show_discount !== false
  const admissionFee = (inv.admission_fee as number) ?? 0
  const showAdmissionFee = settings.show_admission_fee !== false && admissionFee > 0
  const taxableAmount = (inv.taxable_amount as number) ?? amount
  const gstAmount = (inv.gst_amount as number) ?? 0
  const cgstAmount = (inv.cgst_amount as number) ?? 0
  const sgstAmount = (inv.sgst_amount as number) ?? 0
  const igstAmount = (inv.igst_amount as number) ?? 0
  const showGst = settings.show_gst_breakup === true && gstAmount > 0
  const notes = inv.notes as string | null
  const description = (inv.description as string) || 'Membership fee'

  const invNum = inv.invoice_number as string
  const issueDate = settings.show_invoice_date !== false
    ? fmtDate((inv.issued_at as string) ?? (inv.created_at as string))
    : null
  const generatedDate = settings.show_generated_date !== false
    ? fmtDate((inv.generated_at as string) ?? (inv.created_at as string))
    : null
  const dueDate = fmtDate(inv.due_at as string | null)
  const paidOn = inv.paid_at ? fmtDate(inv.paid_at as string) : null

  const statusInfo = STATUS_INFO[status] ?? { label: 'DRAFT', color: [0.4, 0.4, 0.4] }

  const pdf = await PDFDocument.create()
  // A4: the customisable sections (admission fee, GST breakup, refund policy,
  // terms) need the extra height over the old 595x700 page.
  const page = pdf.addPage([595, 842])
  pdf.registerFontkit(fontkit)
  const font = await pdf.embedFont(MANROPE_REGULAR)
  const bold = await pdf.embedFont(MANROPE_BOLD)
  const logo = await embedLogo(pdf, settings.logo_url)

  const marginX = 40
  let y = 792

  const grey = (v: number) => rgb(v, v, v)
  const text = (
    t: string,
    opts: { size?: number; f?: typeof font; x?: number; color?: readonly [number, number, number] } = {},
  ) => {
    const [r, g, b] = opts.color ?? [0.1, 0.1, 0.1]
    page.drawText(safe(t), {
      x: opts.x ?? marginX,
      y,
      size: opts.size ?? 11,
      font: opts.f ?? font,
      color: rgb(r, g, b),
    })
  }
  const nl = (h = 16) => { y -= h }
  const hr = (color = grey(0.85)) => {
    page.drawLine({ start: { x: marginX, y }, end: { x: 555, y }, thickness: 1, color })
    nl(14)
  }
  /** Free-text fields (notes, refund policy, terms) are owner-authored and
   * arbitrarily long — unwrapped they run off the right edge of the page. */
  const paragraph = (t: string, size: number, color: [number, number, number]) => {
    const maxWidth = 555 - marginX
    let line = ''
    const flush = () => { if (line) { text(line, { size, color }); nl(size + 3); line = '' } }
    for (const word of safe(t).split(/\s+/)) {
      const next = line ? `${line} ${word}` : word
      if (font.widthOfTextAtSize(next, size) > maxWidth && line) flush()
      else line = next
      if (!line) line = word
    }
    flush()
  }
  /** Right-aligned value, the way the app's PDF aligns its amount column. */
  const rightText = (
    v: string,
    opts: { size?: number; f?: typeof font; dy?: number; color?: readonly [number, number, number] } = {},
  ) => {
    const size = opts.size ?? 13
    const f = opts.f ?? bold
    const [r, g, b] = opts.color ?? [0.1, 0.1, 0.1]
    page.drawText(safe(v), {
      x: 555 - f.widthOfTextAtSize(safe(v), size),
      y: y + (opts.dy ?? 0),
      size,
      font: f,
      color: rgb(r, g, b),
    })
  }
  /** Label + right-aligned amount, used by the admission-fee and GST lines. */
  const amountRow = (label: string, value: string) => {
    text(label, { size: 10, color: [0.4, 0.4, 0.4] })
    rightText(value)
    nl(20)
  }

  // Header: gym block (left) + invoice#/status (right)
  if (logo) {
    const h = 34
    const w = (logo.width / logo.height) * h
    page.drawImage(logo, { x: marginX, y: y - h + 12, width: Math.min(w, 160), height: h })
    nl(h + 6)
  }
  text(gymName, { size: 18, f: bold })
  // Right-aligned to the margin, like the app's header column.
  const yStart = y
  rightText('INVOICE', { size: 9, f: font, color: [0.5, 0.5, 0.5] })
  y = yStart - 16
  rightText(invNum, { size: 13 })
  const badgeWidth = bold.widthOfTextAtSize(statusInfo.label, 9) + 16
  page.drawRectangle({
    x: 555 - badgeWidth,
    y: yStart - 36,
    width: badgeWidth,
    height: 16,
    color: rgb(...statusInfo.color),
  })
  page.drawText(statusInfo.label, {
    x: 555 - badgeWidth + 8,
    y: yStart - 32,
    size: 9,
    font: bold,
    color: rgb(1, 1, 1),
  })
  y = yStart

  nl(18)
  if (ownerName) { text(ownerName, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (address) { text(address, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (phone) { text(phone, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (website) { text(website, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }
  if (gstin) { text(`GSTIN: ${gstin}`, { size: 10, color: [0.4, 0.4, 0.4] }); nl(14) }

  nl(10)
  page.drawLine({ start: { x: marginX, y }, end: { x: 555, y }, thickness: 2, color: rgb(0.1, 0.1, 0.1) })
  nl(24)

  // Dates row — each column appears only if its toggle is on, so the row packs
  // left instead of leaving a gap where a hidden date used to sit.
  // Order matches invoice_pdf.dart: issue, due, generated, paid.
  const dateCols: Array<[string, string, [number, number, number]]> = []
  if (issueDate) dateCols.push(['ISSUE DATE', issueDate, [0.1, 0.1, 0.1]])
  dateCols.push(['DUE DATE', dueDate, [0.1, 0.1, 0.1]])
  if (generatedDate) dateCols.push(['GENERATED', generatedDate, [0.1, 0.1, 0.1]])
  if (paidOn) dateCols.push(['PAID ON', paidOn, [0.0, 0.42, 0.0]])
  dateCols.forEach(([label], i) => {
    page.drawText(label, { x: marginX + i * 130, y, size: 9, font, color: grey(0.5) })
  })
  nl(15)
  dateCols.forEach(([, value, color], i) => {
    page.drawText(value, { x: marginX + i * 130, y, size: 12, font: bold, color: rgb(...color) })
  })
  nl(24)
  hr()

  // Bill to
  text('BILL TO', { size: 9, color: [0.5, 0.5, 0.5] })
  nl(16)
  text(memberName, { size: 14, f: bold })
  nl(16)
  if (memberEmail) { text(memberEmail, { size: 11, color: [0.4, 0.4, 0.4] }); nl(16) }
  if (membershipId && settings.show_membership_id !== false) {
    text(`Membership ID: ${membershipId}`, { size: 11, color: [0.4, 0.4, 0.4] })
    nl(16)
  }
  nl(6)
  hr()

  // Line item
  text('DESCRIPTION', { size: 9, color: [0.5, 0.5, 0.5] })
  rightText('AMOUNT', { size: 9, f: font, color: [0.5, 0.5, 0.5] })
  nl(16)
  hr(grey(0.9))
  text(description, { size: 13 })
  rightText(money(originalAmount ?? amount))
  nl(20)
  hr()

  if (hasDiscount) {
    text('DISCOUNT', { size: 10, color: [0.0, 0.42, 0.0] })
    rightText(`\u2212 ${money(discountAmount)}`, { color: [0.0, 0.42, 0.0] })
    nl(20)
    hr()
  }

  if (showAdmissionFee) {
    amountRow('ADMISSION FEE', money(admissionFee))
    hr()
  }

  if (showGst) {
    // Paise, like the app: the GST parts have to add up to the total.
    amountRow('TAXABLE VALUE', moneyExact(taxableAmount))
    if (cgstAmount > 0) amountRow('CGST', moneyExact(cgstAmount))
    if (sgstAmount > 0) amountRow('SGST', moneyExact(sgstAmount))
    if (igstAmount > 0) amountRow('IGST', moneyExact(igstAmount))
    hr()
  }

  // Total
  nl(6)
  text('TOTAL DUE', { size: 10, color: [0.4, 0.4, 0.4] })
  rightText(money(amount), { size: 22, dy: -2 })
  nl(28)
  hr()

  const block = (label: string, body: string) => {
    // Stop before the footer rule rather than printing over it.
    if (y < 110) return
    nl(4)
    text(label, { size: 9, color: [0.5, 0.5, 0.5] })
    nl(16)
    paragraph(body, 10, [0.4, 0.4, 0.4])
    nl(8)
  }

  if (notes) block('NOTES', notes)
  if (refundPolicy) block('REFUND POLICY', refundPolicy)
  if (terms) block('TERMS & CONDITIONS', terms)

  // Footer, pinned near bottom
  const footerY = 40
  page.drawLine({ start: { x: marginX, y: footerY + 14 }, end: { x: 555, y: footerY + 14 }, thickness: 1, color: grey(0.85) })
  page.drawText(invNum, { x: marginX, y: footerY, size: 9, font, color: grey(0.6) })
  page.drawText('Powered by GymCRM', { x: 470, y: footerY, size: 9, font, color: grey(0.6) })

  return pdf.save()
}
