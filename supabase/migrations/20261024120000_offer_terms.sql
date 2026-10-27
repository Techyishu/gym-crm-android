-- Offers limited to specific billing terms, and showing the code of public offers.
--
-- A Dodo discount can be restricted to specific products (e.g. only the
-- 1-month ₹499 product). offers.terms mirrors that, so the paywall doesn't
-- advertise the discount on a 12-month plan Dodo won't discount, and checkout
-- doesn't send a code Dodo would reject for that product.

alter table public.offers
  add column terms text[]
  check (terms is null or terms <@ array['1mo', '3mo', '6mo', '12mo']);
-- null = every term.

-- Same as 20261022120000 except each offer also returns `terms`, and `code`
-- for 'everyone' and 'coupon' offers. Codes of 'selected' offers stay hidden:
-- they're meant for specific gyms and Dodo would accept them from anyone.
create or replace function public.get_paywall_pricing(p_coupon text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_gym_id uuid;
  v_plans  jsonb := '{}'::jsonb;
  v_plan   text;
  v_code   text;
  v_offer  public.offers;
  v_coupon_offer public.offers;
begin
  select gym_id into v_gym_id from public.profiles where id = auth.uid();
  if v_gym_id is null then
    raise exception 'no gym';
  end if;

  foreach v_plan in array array['starter', 'pro'] loop
    v_code := public.resolve_price_plan(v_gym_id, v_plan);
    if v_code is null then
      continue;
    end if;
    v_offer := public.resolve_offer(v_gym_id, v_code, p_coupon);
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
    'coupon_valid', case
      when nullif(trim(coalesce(p_coupon, '')), '') is null then null
      else v_coupon_offer.id is not null end
  );
end;
$$;
