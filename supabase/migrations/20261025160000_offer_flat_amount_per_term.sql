-- Offers can be a flat rupee amount (e.g. ₹50 off) as well as a percentage,
-- and are resolved per term, so 1/3/6/12 months can each run their own offer
-- (one offers row + one Dodo discount code per term).

alter table public.offers alter column percent_off drop not null;
alter table public.offers add column if not exists amount_off int;
alter table public.offers add constraint offers_amount_off_check
  check (amount_off is null or amount_off >= 1);
-- Exactly one of percent_off / amount_off.
alter table public.offers add constraint offers_one_discount_check
  check ((percent_off is null) <> (amount_off is null));

-- p_term: when set, only offers covering that term, and the biggest rupee
-- discount on that term's price wins. Without it, the old behaviour (biggest %).
drop function if exists public.resolve_offer(uuid, text, text);
create function public.resolve_offer(
  p_gym_id uuid,
  p_plan_code text,
  p_coupon text,
  p_term text default null
)
returns public.offers
language sql
stable
security definer
set search_path to ''
as $function$
  select o.*
  from public.offers o
  left join public.pricing_plan_terms t
    on t.plan_code = p_plan_code and t.term = p_term
  where o.active
    and o.starts_at <= now()
    and (o.ends_at is null or o.ends_at > now())
    and (o.plan_codes is null or p_plan_code = any (o.plan_codes))
    and (p_term is null or o.terms is null or p_term = any (o.terms))
    and (
      o.audience = 'everyone'
      or (o.audience = 'selected'
          and exists (select 1 from public.offer_gyms og
                      where og.offer_id = o.id and og.gym_id = p_gym_id))
      or (o.audience = 'coupon' and o.code = upper(trim(coalesce(p_coupon, ''))))
    )
  order by coalesce(o.amount_off * 100,
                    t.price_paise * o.percent_off / 100,
                    o.percent_off) desc nulls last
  limit 1;
$function$;

create or replace function public.get_paywall_pricing(p_coupon text default null::text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
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
    -- Plan-level offer kept for older app builds; current builds read the
    -- per-term 'offer' inside each term.
    v_offer := case when v_subscribed then null
                    else public.resolve_offer(v_gym.id, v_code, p_coupon, '1mo') end;
    v_plans := v_plans || jsonb_build_object(v_plan, jsonb_build_object(
      'code', v_code,
      'monthly_price', (select monthly_price from public.pricing_plans where code = v_code),
      'whatsapp_quota', coalesce(
        (select whatsapp_quota from public.pricing_plans where code = v_code),
        public.plan_whatsapp_quota(v_plan, false)),
      'terms', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'term', t.term, 'months', t.months, 'price', t.price_paise / 100,
                 'offer', case when v_subscribed or o.id is null then null else jsonb_build_object(
                   'name', o.name,
                   'percent_off', o.percent_off,
                   'amount_off', o.amount_off,
                   'cycles', o.cycles,
                   'code', case when o.audience <> 'selected' then o.code end,
                   'is_coupon', o.audience = 'coupon') end)
               order by t.months)
        from public.pricing_plan_terms t
        left join lateral public.resolve_offer(v_gym.id, v_code, p_coupon, t.term) o on true
        where t.plan_code = v_code), '[]'::jsonb),
      'offer', case when v_offer.id is null then null else jsonb_build_object(
        'name', v_offer.name,
        'percent_off', v_offer.percent_off,
        'amount_off', v_offer.amount_off,
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
      'term', v_gym.plan_term,
      'plan_price', v_gym.plan_price,
      'discount_pct', v_gym.plan_discount_pct,
      'discount_cycles_left', v_gym.plan_discount_cycles_left) end,
    'coupon_valid', case
      when nullif(trim(coalesce(p_coupon, '')), '') is null then null
      else v_coupon_offer.id is not null end
  );
end;
$function$;
