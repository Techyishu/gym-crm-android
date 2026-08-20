-- Daily push to gym owners when their WhatsApp balance (free monthly quota +
-- purchased whatsapp_credits, same pool whatsapp-reminders and
-- send-whatsapp-invoice draw from) is low (<=10 remaining) or exhausted (<=0).
-- Scoped to whatsapp_reminder_enabled=true gyms only — starter gyms default
-- to exactly 10 signup credits (== LOW_THRESHOLD), which false-positived as
-- "low" for every starter gym regardless of whether they use the feature
-- (caught in prod 2026-08-13, ~120 gyms pushed before this gate was added).
-- Edge function: supabase/functions/whatsapp-credit-push/index.ts
-- Dedupes via notifications_log (one push per state per gym per day), same
-- pattern as trigger_billing_expiry_push.

create or replace function public.trigger_whatsapp_credit_push()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
    from vault.decrypted_secrets
   where name = 'push_reminders_cron_secret';

  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/whatsapp-credit-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule(
  'whatsapp-credit-push-daily',
  '15 4 * * *',
  $$select public.trigger_whatsapp_credit_push()$$
);
