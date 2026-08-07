-- Per-gym choice of which approved MSG91 WhatsApp template the reminder job sends.
-- Value must match a key in TEMPLATES in supabase/functions/whatsapp-reminders/index.ts.
alter table gyms
  add column if not exists whatsapp_template text not null default 'payment_reminder';
