-- Per-gym opt-in, default off — a gym never spends WhatsApp credits on
-- invoice messages unless it explicitly turns this on. Toggled from the
-- "Invoice WhatsApp messages" switch in reminders_screen.dart.
alter table public.gyms
  add column if not exists whatsapp_invoice_enabled boolean not null default false;

-- Fires the invoice-generated WhatsApp message the moment any row lands in
-- `invoices`, regardless of which path created it: generate_monthly_invoices()
-- cron, create_invoice_for_membership() trigger on new memberships, or a
-- staff-created invoice from the app. Single choke point, no app code needed.

create or replace function public.notify_invoice_whatsapp()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not exists (
    select 1 from gyms where id = new.gym_id and whatsapp_invoice_enabled
  ) then
    return new;
  end if;

  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw"}'::jsonb,
    body := jsonb_build_object('invoice_id', new.id)
  );
  return new;
end;
$function$;

create trigger trg_notify_invoice_whatsapp
  after insert on public.invoices
  for each row
  execute function public.notify_invoice_whatsapp();

-- Fires the invoice-paid WhatsApp message when billing_screen.dart's
-- `_save()` (or any other path) marks an invoice paid. Guards on the OLD
-- status too, so re-saving an already-paid invoice never double-sends.

create or replace function public.notify_invoice_paid_whatsapp()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status = 'paid' and old.status is distinct from 'paid'
    and exists (select 1 from gyms where id = new.gym_id and whatsapp_invoice_enabled)
  then
    perform net.http_post(
      url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
      headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9ybHFqaHF4ZXl1a3ZmenN1cnNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUzODM2NTgsImV4cCI6MjA5MDk1OTY1OH0.4JXUdbPTkofshaYaYSOJwE9qwQ2zwjUQljuu5cfgzzw"}'::jsonb,
      body := jsonb_build_object('invoice_id', new.id, 'event', 'paid')
    );
  end if;
  return new;
end;
$function$;

create trigger trg_notify_invoice_paid_whatsapp
  after update of status on public.invoices
  for each row
  execute function public.notify_invoice_paid_whatsapp();
