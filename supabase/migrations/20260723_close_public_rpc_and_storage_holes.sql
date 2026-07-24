-- Security fix: four doors were reachable with no login at all.
-- Verified each fix against every real caller before applying (see chat).

-- 1. invoice-pdfs bucket allowed public LISTING (enumerate every invoice
--    across every gym). Bucket is public=true, so direct known-path GET
--    (client.storage.from('invoice-pdfs').getPublicUrl(...)) is served by
--    Storage's public route and never consults this policy — dropping it
--    only removes the ability to list/enumerate, not legitimate downloads.
drop policy if exists "Public can read invoice PDFs" on storage.objects;

-- 2. increment_whatsapp_credits had zero auth check — anon could credit or
--    zero-out any gym's WhatsApp balance by guessing a gym_id. Only real
--    caller is the Dodo webhook, which uses the service-role key (bypasses
--    grants entirely), so revoking anon/authenticated breaks nothing.
revoke execute on function public.increment_whatsapp_credits(uuid, integer) from anon, authenticated;

-- 3. trigger_push_reminders had zero auth check and no legitimate app
--    caller — it's meant to be invoked by a scheduled job, not a user.
--    Anon could spam-fire it as a notification-spam / cost vector.
revoke execute on function public.trigger_push_reminders() from anon, authenticated;

-- 4. get_member_stats had zero auth check — anon (or any signed-in user)
--    could pull any gym's member/revenue/lead stats by passing its gym_id.
--    Added the same "caller must be staff of this gym" guard every other
--    gym-scoped RPC already uses (see checkout_member, record_invoice_payment).
create or replace function public.get_member_stats(p_gym_id uuid, p_lead_days integer default 30)
returns json
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_staff_gym_id uuid;
  v_result json;
begin
  select gym_id into v_staff_gym_id from profiles where id = auth.uid();
  if v_staff_gym_id is null or v_staff_gym_id <> p_gym_id then
    raise exception 'unauthorized: gym mismatch';
  end if;

  with mem as (
    select status, joined_at, billing_interval_months from public.members where gym_id = p_gym_id
  ),
  monthly as (
    select
      to_char(date_trunc('month', joined_at::timestamptz), 'YYYY-MM') as month_key,
      count(*) as cnt
    from mem
    where joined_at is not null
      and joined_at::timestamptz >= now() - interval '365 days'
    group by 1
  ),
  plan_agg as (
    select billing_interval_months, count(*) as cnt
    from   mem
    where  status = 'active' and billing_interval_months is not null
    group by billing_interval_months
  ),
  leads_window as (
    select status from public.leads
    where gym_id = p_gym_id
      and created_at >= now() - make_interval(days => p_lead_days)
  )
  select json_build_object(
    'total',       (select count(*)                           from mem),
    'active',      (select count(*) from mem where status = 'active'),
    'frozen',      (select count(*) from mem where status = 'frozen'),
    'expired',     (select count(*) from mem where status = 'expired'),
    'cancelled',   (select count(*) from mem where status = 'cancelled'),
    'new_last_30d', (select count(*) from mem where joined_at is not null and joined_at::timestamptz >= now() - interval '30 days'),
    'avg_tenure_days', (select avg(extract(epoch from (now() - joined_at)) / 86400.0)
                         from mem where status = 'active' and joined_at is not null),
    'growth_data', coalesce(
      (select json_agg(json_build_object('key', month_key, 'count', cnt) order by month_key)
       from   monthly),
      '[]'::json
    ),
    'plan_mix', coalesce(
      (select json_agg(json_build_object('months', billing_interval_months, 'count', cnt) order by cnt desc)
       from   plan_agg),
      '[]'::json
    ),
    'leads_total',     (select count(*) from leads_window),
    'leads_trial',     (select count(*) from leads_window where status = 'trial'),
    'leads_converted', (select count(*) from leads_window where status = 'converted')
  ) into v_result;

  return v_result;
end;
$function$;
