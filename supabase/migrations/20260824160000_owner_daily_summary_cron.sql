-- Daily owner push: "₹4,500 collected today · 12 check-ins · 3 members due
-- tomorrow" — the numbers the dashboard already computes, delivered instead
-- of waited for. Nothing else in the app currently messages the owner on any
-- recurring schedule; every existing push/WhatsApp job targets members.
-- Edge function: supabase/functions/owner-daily-summary/index.ts
-- Dedupes via notifications_log (one push per gym per IST day), same pattern
-- as trigger_whatsapp_credit_push.
--
-- 14:30 UTC = 20:00 IST.

create or replace function public.trigger_owner_daily_summary()
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
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/owner-daily-summary',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

select cron.schedule(
  'owner-daily-summary-daily',
  '30 14 * * *',
  $$select public.trigger_owner_daily_summary()$$
);
