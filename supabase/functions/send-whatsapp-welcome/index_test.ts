/**
 * Run: deno test supabase/functions/send-whatsapp-welcome/index_test.ts
 */

const { pickTemplate, normalizeIndianPhone } = await import('./templates.ts')

Deno.test('pickTemplate defaults to English for anything but the exact Hinglish key', () => {
  if (pickTemplate('welcome_hin_1') !== 'welcome_hin_1') throw new Error('Hinglish key not honoured')
  if (pickTemplate('welcome_1') !== 'welcome_1') throw new Error('English key not honoured')
  if (pickTemplate(undefined) !== 'welcome_1') throw new Error('missing template should default to English')
  if (pickTemplate('typo') !== 'welcome_1') throw new Error('unknown template should default to English, not throw')
})

Deno.test('normalizeIndianPhone always yields 91 + last 10 digits', () => {
  const cases: [string, string][] = [
    ['9876543210', '919876543210'],
    ['919876543210', '919876543210'],
    ['09876543210', '919876543210'],
    ['+91 98765 43210', '919876543210'],
  ]
  for (const [input, expected] of cases) {
    const got = normalizeIndianPhone(input)
    if (got !== expected) throw new Error(`normalizeIndianPhone(${input}) = ${got}, expected ${expected}`)
  }
})
