-- International gyms (gyms.settings->>'country' set and not 'IN'):
--  1. No automatic WhatsApp. Meta bills per message by the recipient's
--     country, ~12-40x India's rate, so reminders/invoice/welcome sends
--     through MSG91 would cost more than the plan earns. Staff still have the
--     free manual wa.me button. Gyms without a country are Indian, unchanged.
--  2. Their own USD price list. Dormant until the Dodo product ids are filled
--     in and the plan is flipped to is_default (see bottom) — until then
--     international gyms keep getting the INR plans, exactly as today.

-- ── 1. WhatsApp gate ────────────────────────────────────────────────────────
-- Every MSG91 sender (whatsapp-reminders, send-whatsapp-invoice,
-- send-whatsapp-welcome) claims a unit here first and treats null as "nothing
-- left", so this one check stops all of them.
create or replace function public.consume_whatsapp_allowance(p_gym_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_bucket text;
begin
  if exists (
    select 1 from gyms
     where id = p_gym_id
       and coalesce(settings->>'country', 'IN') <> 'IN'
  ) then
    return null;
  end if;

  update gyms
     set whatsapp_monthly_quota_used = whatsapp_monthly_quota_used + 1
   where id = p_gym_id
     and whatsapp_monthly_quota_used < public.whatsapp_quota(gyms)
  returning 'quota' into v_bucket;

  if v_bucket is null then
    update gyms
       set whatsapp_credits = whatsapp_credits - 1
     where id = p_gym_id
       and whatsapp_credits > 0
    returning 'credits' into v_bucket;
  end if;

  return v_bucket;
end;
$$;

-- ── 2. USD pricing ──────────────────────────────────────────────────────────
alter table public.pricing_plans
  add column if not exists market text not null default 'IN'
    check (market in ('IN', 'INTL')),
  add column if not exists currency text not null default 'INR';

-- One default per plan *per market*, so ₹299 Pro and $10 Pro can both be live.
drop index if exists public.pricing_plans_one_default_per_plan;
create unique index pricing_plans_one_default_per_plan
  on public.pricing_plans (plan, market) where is_default;

-- price_paise holds the smallest unit of `currency` — cents here. The env
-- names only satisfy pricing_plan_terms_check while the plan is dormant;
-- paste the real Dodo product ids into dodo_product_id when activating.
insert into public.pricing_plans (code, plan, label, monthly_price, is_default, whatsapp_quota, market, currency)
values ('pro_usd_10', 'pro', 'Pro $10 (international)', 10, false, 0, 'INTL', 'USD')
on conflict (code) do nothing;

insert into public.pricing_plan_terms (plan_code, term, months, price_paise, dodo_product_id, dodo_product_env)
values
  ('pro_usd_10', '1mo',  1,  1000, null, 'DODO_PRODUCT_ID_PRO_USD_1MO'),
  ('pro_usd_10', '3mo',  3,  2800, null, 'DODO_PRODUCT_ID_PRO_USD_3MO'),
  ('pro_usd_10', '6mo',  6,  5000, null, 'DODO_PRODUCT_ID_PRO_USD_6MO'),
  ('pro_usd_10', '12mo', 12, 10000, null, 'DODO_PRODUCT_ID_PRO_USD_12MO')
on conflict do nothing;

-- A gym's locked price_plan still wins (existing payers keep their price).
-- Otherwise: the default plan of the gym's market. International gyms fall
-- back to the Indian default until an INTL plan is switched on, so nothing
-- changes for them before the Dodo products exist.
create or replace function public.resolve_price_plan(p_gym_id uuid, p_plan text)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  with g as (
    select g.price_plan,
           case when coalesce(g.settings->>'country', 'IN') = 'IN' then 'IN' else 'INTL' end as market
      from public.gyms g where g.id = p_gym_id
  )
  select coalesce(
    (select pp.code from g join public.pricing_plans pp on pp.code = g.price_plan
      where pp.plan = p_plan),
    (select pp.code from g join public.pricing_plans pp
        on pp.plan = p_plan and pp.is_default and pp.market = g.market),
    (select pp.code from g join public.pricing_plans pp
        on pp.plan = p_plan and pp.is_default and pp.market = 'IN'
      where g.market = 'INTL'
        and not exists (select 1 from public.pricing_plans x
                         where x.market = 'INTL' and x.is_default)),
    -- No gym row (shouldn't happen): the Indian default, as before.
    (select code from public.pricing_plans where plan = p_plan and is_default and market = 'IN')
  );
$$;

-- To switch USD pricing on once the Dodo products exist:
--   update pricing_plan_terms set dodo_product_id = 'pdt_…' where plan_code = 'pro_usd_10' and term = '1mo'; (×4)
--   update pricing_plans set is_default = true where code = 'pro_usd_10';
