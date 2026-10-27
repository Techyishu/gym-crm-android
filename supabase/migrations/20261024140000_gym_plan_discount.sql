-- What a subscribed gym actually pays while a Dodo discount is running.
--
-- plan_price stays the plan's list price (₹499). These two say the gym is on
-- 50% off with N discounted payments still to come, so the paywall can show
-- "₹249.50/month for 5 more months, then ₹499" instead of ₹499. Written by the
-- Dodo webhook from the subscription's discount_id / discount_cycles_remaining
-- and cleared once Dodo reports no discount left.

alter table public.gyms
  add column plan_discount_pct integer check (plan_discount_pct between 1 and 100),
  add column plan_discount_cycles_left integer check (plan_discount_cycles_left >= 0);

-- Server-managed, like the other billing columns.
create or replace function block_owner_billing_edit()
returns trigger
language plpgsql
as $f$
begin
  if auth.role() <> 'service_role' and
     (new.plan is distinct from old.plan
      or new.plan_expires_at is distinct from old.plan_expires_at
      or new.trial_ends_at is distinct from old.trial_ends_at
      or new.dodo_subscription_id is distinct from old.dodo_subscription_id
      or new.dodo_customer_id is distinct from old.dodo_customer_id
      or new.apple_subscription_id is distinct from old.apple_subscription_id
      or new.plan_price is distinct from old.plan_price
      or new.price_plan is distinct from old.price_plan
      or new.plan_discount_pct is distinct from old.plan_discount_pct
      or new.plan_discount_cycles_left is distinct from old.plan_discount_cycles_left
      or new.status is distinct from old.status) then
    raise exception 'billing fields are server-managed';
  end if;
  return new;
end;
$f$;

-- Same as 20261024120000, plus:
--   'current' — the gym's own subscription (price, running discount), and
--   no offers for a gym with a live subscription: it already bought, and
--   Dodo allows one redemption per customer anyway.
create or replace function public.get_paywall_pricing(p_coupon text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_gym    public.gyms;
  v_plans  jsonb := '{}'::jsonb;
  v_plan   text;
  v_code   text;
  v_offer  public.offers;
  v_coupon_offer public.offers;
  v_subscribed boolean;
begin
  select g.* into v_gym
  from public.profiles p join public.gyms g on g.id = p.gym_id
  where p.id = auth.uid();
  if v_gym.id is null then
    raise exception 'no gym';
  end if;
  v_subscribed := v_gym.dodo_subscription_id is not null
               or v_gym.apple_subscription_id is not null;

  foreach v_plan in array array['starter', 'pro'] loop
    v_code := public.resolve_price_plan(v_gym.id, v_plan);
    if v_code is null then
      continue;
    end if;
    v_offer := case when v_subscribed then null
                    else public.resolve_offer(v_gym.id, v_code, p_coupon) end;
    v_plans := v_plans || jsonb_build_object(v_plan, jsonb_build_object(
      'code', v_code,
      'monthly_price', (select monthly_price from public.pricing_plans where code = v_code),
      'terms', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'term', t.term, 'months', t.months, 'price', t.price_paise / 100)
               order by t.months)
        from public.pricing_plan_terms t where t.plan_code = v_code), '[]'::jsonb),
      'offer', case when v_offer.id is null then null else jsonb_build_object(
        'name', v_offer.name,
        'percent_off', v_offer.percent_off,
        'cycles', v_offer.cycles,
        'terms', v_offer.terms,
        'code', case when v_offer.audience <> 'selected' then v_offer.code end,
        'is_coupon', v_offer.audience = 'coupon') end
    ));
  end loop;

  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    select * into v_coupon_offer from public.offers o
    where o.audience = 'coupon' and o.active
      and o.code = upper(trim(p_coupon))
      and o.starts_at <= now() and (o.ends_at is null or o.ends_at > now());
  end if;

  return jsonb_build_object(
    'plans', v_plans,
    'current', case when not v_subscribed then null else jsonb_build_object(
      'plan', v_gym.plan,
      'plan_price', v_gym.plan_price,
      'discount_pct', v_gym.plan_discount_pct,
      'discount_cycles_left', v_gym.plan_discount_cycles_left) end,
    'coupon_valid', case
      when nullif(trim(coalesce(p_coupon, '')), '') is null then null
      else v_coupon_offer.id is not null end
  );
end;
$$;
