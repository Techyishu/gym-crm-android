/**
 * Guards the one thing that silently broke before: the WhatsApp PDF must read
 * the invoice's own `settings_snapshot`, not the gym row, so every invoice
 * customisation a gym sets in the app reaches the member's WhatsApp copy.
 *
 * Run: deno test --allow-net supabase/functions/send-whatsapp-invoice/index_test.ts
 */

import { buildInvoicePdf } from './pdf.ts'
import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1'
import fontkit from 'https://esm.sh/@pdf-lib/fontkit@1.1.1'
import { MANROPE_BOLD, MANROPE_REGULAR } from './fonts.ts'

/** The PDF embeds Manrope, so drawn text is stored as glyph ids, not ASCII.
 * Encoding the expected string through the same font gives the hex to look
 * for. Regular and bold have their own glyph runs, hence both encoders. */
const encoders = await (async () => {
  const doc = await PDFDocument.create()
  doc.registerFontkit(fontkit)
  const fonts = [await doc.embedFont(MANROPE_REGULAR), await doc.embedFont(MANROPE_BOLD)]
  return fonts.map((f) => (s: string) => f.encodeText(s).toString().slice(1, -1).toUpperCase())
})()

/** Everything a gym can customise, all switched on. */
const invoice = {
  id: '11111111-1111-4111-8111-111111111111',
  invoice_number: 'GYMX-000042',
  created_at: '2026-09-01T00:00:00Z',
  issued_at: '2026-09-01T00:00:00Z',
  generated_at: '2026-09-02T00:00:00Z',
  due_at: '2026-09-10T00:00:00Z',
  paid_at: null,
  status: 'open',
  amount: 1180,
  original_amount: 1180,
  discount_amount: 100,
  admission_fee: 500,
  taxable_amount: 1000,
  gst_amount: 180,
  cgst_amount: 90,
  sgst_amount: 90,
  igst_amount: 0,
  notes: 'Thanks for training with us.',
  description: 'Quarterly membership',
  membership_id_snapshot: 'M-0007',
  member_snapshot: { name: 'Asha Rao', email: 'asha@example.com', membership_id: 'M-0007' },
  settings_snapshot: {
    gym_name: 'Iron Yard',
    owner_name: 'R. Kapoor',
    contact_email: 'hello@ironyard.in',
    contact_phone: '+91 90000 00000',
    address: '2nd Floor, MG Road, Bengaluru',
    gstin: '29ABCDE1234F1Z5',
    invoice_prefix: 'GYMX',
    show_invoice_date: true,
    show_generated_date: true,
    show_membership_id: true,
    show_admission_fee: true,
    show_discount: true,
    show_gst_breakup: true,
    gst_percent: 18,
    refund_policy: 'Fees are non-refundable once the billing period has started. '.repeat(4),
    terms_and_conditions: 'Membership is personal and non-transferable. '.repeat(6),
  },
  gyms: { id: 'g1', name: 'Stale Gym Name From Gyms Table' },
  members: { first_name: 'Stale', last_name: 'Member', email: 'stale@example.com' },
}

/** pdf-lib Flate-compresses content streams, so inflate every stream and keep
 * the hex show-text operands. Streams that are not deflate (fonts, images)
 * simply fail to inflate. */
async function pdfHex(bytes: Uint8Array): Promise<string> {
  const raw = new TextDecoder('latin1').decode(bytes)
  // \n-anchored so the marker does not also match the trailing "endstream".
  const marker = /\nstream\r?\n/g
  let out = ''
  let m: RegExpExecArray | null
  while ((m = marker.exec(raw)) !== null) {
    const start = m.index + m[0].length
    let end = raw.indexOf('\nendstream', start)
    if (end < 0) continue
    // Trim the EOL padding PDF writers put before `endstream`; the inflater
    // rejects trailing bytes past the end of the deflate data.
    while (end > start && (bytes[end - 1] === 0x0a || bytes[end - 1] === 0x0d)) end--
    try {
      const inflated = await new Response(
        new Blob([bytes.slice(start, end)]).stream().pipeThrough(new DecompressionStream('deflate')),
      ).arrayBuffer()
      out += new TextDecoder('latin1').decode(new Uint8Array(inflated)).toUpperCase()
    } catch {
      // Not a deflate stream — nothing to read here.
    }
  }
  return out
}

const shows = (hex: string, s: string) => encoders.some((enc) => hex.includes(enc(s)))

Deno.test('renders the customised fields from settings_snapshot', async () => {
  const hex = await pdfHex(await buildInvoicePdf(invoice))
  for (
    const expected of [
      'IRON YARD', // custom gym_name wins over gyms.name
      'GYMX-000042', // the real invoice_number, not a recomputed one
      'R. Kapoor',
      'hello@ironyard.in',
      '29ABCDE1234F1Z5',
      'Asha Rao', // member_snapshot wins over the live members row
      'M-0007',
      'ADMISSION FEE',
      'TAXABLE VALUE',
      'CGST',
      'REFUND POLICY',
      'TERMS & CONDITIONS',
      'GENERATED',
    ]
  ) {
    if (!shows(hex, expected)) throw new Error(`missing from PDF: ${expected}`)
  }
  if (shows(hex, 'STALE GYM NAME')) throw new Error('fell back to the gyms table')
})

Deno.test('matches the app PDF formatting', async () => {
  const hex = await pdfHex(await buildInvoicePdf(invoice))
  // formatCurrency: rupee sign, grouped, no decimals.
  if (!shows(hex, '\u20B91,180')) throw new Error('total is not formatted like formatCurrency')
  // formatCurrencyExact: GST lines keep paise so they sum to the total.
  if (!shows(hex, '\u20B91,000.00')) throw new Error('taxable value lost its paise')
  // DateFormat('d MMM yyyy'): no leading zero, "Sep" not "Sept".
  if (!shows(hex, '1 Sep 2026')) throw new Error('date is not formatted like formatDate')
  if (shows(hex, 'Rs. ')) throw new Error('still falling back to "Rs."')
})

Deno.test('drops characters the embedded font cannot encode', async () => {
  // A Devanagari gym name used to throw and kill the whole send.
  const bytes = await buildInvoicePdf({
    ...invoice,
    settings_snapshot: { ...invoice.settings_snapshot, gym_name: 'लोहा Yard', terms_and_conditions: 'नियम ok' },
  })
  if (bytes.length === 0) throw new Error('no PDF produced')
})

Deno.test('honours the hide toggles', async () => {
  const hidden = {
    ...invoice,
    settings_snapshot: {
      ...invoice.settings_snapshot,
      show_invoice_date: false,
      show_generated_date: false,
      show_membership_id: false,
      show_admission_fee: false,
      show_discount: false,
      show_gst_breakup: false,
    },
  }
  const hex = await pdfHex(await buildInvoicePdf(hidden))
  for (
    const gone of ['ISSUE DATE', 'GENERATED', 'M-0007', 'ADMISSION FEE', 'DISCOUNT', 'CGST']
  ) {
    if (shows(hex, gone)) throw new Error(`should be hidden but rendered: ${gone}`)
  }
  if (!shows(hex, 'DUE DATE')) throw new Error('due date is not toggleable and must stay')
})

// The failed logo fetch leaves Deno's connect timer behind; the point of the
// test is that the PDF still renders.
Deno.test({
  name: 'a broken logo URL still produces an invoice',
  sanitizeOps: false,
  sanitizeResources: false,
  async fn() {
    const bytes = await buildInvoicePdf({
    ...invoice,
      settings_snapshot: { ...invoice.settings_snapshot, logo_url: 'http://127.0.0.1:1/nope.png' },
    })
    if (bytes.length === 0) throw new Error('no PDF produced')
  },
})
