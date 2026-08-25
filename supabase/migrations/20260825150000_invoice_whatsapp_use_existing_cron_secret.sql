-- Reuse the project's existing Vault-backed cron secret for invoice WhatsApp
-- triggers. Edge Function secrets are not readable from Postgres, so triggers
-- use the same Vault entry as the other scheduled database calls.
create or replace function public.notify_invoice_whatsapp()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_secret text;
begin
  if not exists (select 1 from public.gyms where id = new.gym_id and whatsapp_invoice_enabled) then return new; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_reminders_cron_secret';
  if v_secret is null then raise warning 'push_reminders_cron_secret is not configured'; return new; end if;
  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('invoice_id', new.id)
  );
  return new;
end;
$$;

create or replace function public.notify_invoice_paid_whatsapp()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_secret text;
begin
  if new.status <> 'paid' or old.status is not distinct from 'paid'
     or not exists (select 1 from public.gyms where id = new.gym_id and whatsapp_invoice_enabled) then return new; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_reminders_cron_secret';
  if v_secret is null then raise warning 'push_reminders_cron_secret is not configured'; return new; end if;
  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('invoice_id', new.id, 'event', 'paid')
  );
  return new;
end;
$$;

revoke all on function public.notify_invoice_whatsapp() from public;
revoke all on function public.notify_invoice_paid_whatsapp() from public;
