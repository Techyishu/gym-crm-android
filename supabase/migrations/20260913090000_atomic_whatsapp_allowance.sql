-- Atomic WhatsApp allowance accounting.
--
-- Before this, whatsapp-reminders and send-whatsapp-invoice each did a
-- read-modify-write in TypeScript: read whatsapp_monthly_quota_used, add one in
-- memory, write the absolute value back. The window between read and write
-- spans a PDF build, a storage upload and the MSG91 call — several seconds —
-- so concurrent invocations all read the same value and all wrote the same
-- value. Increments were silently lost and gyms sent past their cap
-- (Fitnesshub Dehradun: 436 sent, counter stuck at 300, Sept 2026).
--
-- consume_whatsapp_allowance() makes the check and the decrement one atomic
-- statement per bucket. Under READ COMMITTED, an UPDATE that blocks on a
-- concurrently-locked row re-evaluates its WHERE clause against the new row
-- version, so the `< quota` / `> 0` guards cannot be passed by two callers.

create or replace function public.consume_whatsapp_allowance(p_gym_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_bucket text;
begin
  -- Free monthly quota first; credits are purchased and roll over.
  update gyms
     set whatsapp_monthly_quota_used = whatsapp_monthly_quota_used + 1
   where id = p_gym_id
     and whatsapp_monthly_quota_used < plan_whatsapp_quota(plan, legacy_pricing)
  returning 'quota' into v_bucket;

  if v_bucket is null then
    update gyms
       set whatsapp_credits = whatsapp_credits - 1
     where id = p_gym_id
       and whatsapp_credits > 0
    returning 'credits' into v_bucket;
  end if;

  return v_bucket; -- null = nothing left to spend, caller must not send
end;
$$;

-- Give the slot back when the send itself fails, so a MSG91 outage does not
-- burn a gym's allowance.
create or replace function public.refund_whatsapp_allowance(p_gym_id uuid, p_bucket text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_bucket = 'quota' then
    update gyms
       set whatsapp_monthly_quota_used = greatest(whatsapp_monthly_quota_used - 1, 0)
     where id = p_gym_id;
  elsif p_bucket = 'credits' then
    update gyms set whatsapp_credits = whatsapp_credits + 1 where id = p_gym_id;
  end if;
end;
$$;

revoke all on function public.consume_whatsapp_allowance(uuid) from public, anon, authenticated;
revoke all on function public.refund_whatsapp_allowance(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_whatsapp_allowance(uuid) to service_role;
grant execute on function public.refund_whatsapp_allowance(uuid, text) to service_role;
