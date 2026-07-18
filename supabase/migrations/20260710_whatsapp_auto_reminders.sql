-- Auto WhatsApp reminder toggle per gym (mirrors push_reminder_enabled/days pattern).
-- Sending goes through a single shared MSG91 WhatsApp number (see supabase/functions/whatsapp-reminders),
-- not per-gym credentials like wa_phone_number_id/wa_access_token.
alter table gyms add column if not exists whatsapp_reminder_enabled boolean not null default false;
alter table gyms add column if not exists whatsapp_reminder_days integer[] not null default '{3}';
