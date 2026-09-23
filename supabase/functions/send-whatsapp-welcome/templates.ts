/**
 * Pure template logic, split out of index.ts so it can be imported (and
 * tested) without triggering that file's top-level Deno.serve.
 */

export type WelcomeTemplate = 'welcome_1' | 'welcome_hin_1'

export const TEMPLATES: Record<WelcomeTemplate, { lang: string }> = {
  welcome_1: { lang: 'en' },
  welcome_hin_1: { lang: 'en' },
}

/** Anything but the exact Hinglish key falls back to English — a typo or a
 * future third option should never leave the send with no template at all. */
export function pickTemplate(requested: unknown): WelcomeTemplate {
  return requested === 'welcome_hin_1' ? 'welcome_hin_1' : 'welcome_1'
}

/** 91 + the last 10 digits, always — same normalisation as the other two
 * WhatsApp functions, so a number saved as 09876543210 or 919876543210
 * still lands on the right template. */
export function normalizeIndianPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '').replace(/^0+/, '')
  return `91${digits.slice(-10)}`
}
