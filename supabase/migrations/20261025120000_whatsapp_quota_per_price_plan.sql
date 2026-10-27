-- WhatsApp monthly quota follows the gym's locked price plan.
-- ₹299 Pro (pro_299) gets 100 reminders a month; ₹499 Pro keeps 300. Gyms can
-- top up with purchased credits as before.
--
-- pricing_plans.whatsapp_quota overrides the plan default only when the gym is
-- actually on that plan (pp.plan = g.plan). A locked-but-unpaid gym (plan
-- 'free') still gets plan_whatsapp_quota('free') = 0, and a gym with no
-- price_plan (manual grants, older payers) keeps the plan default.

alter table public.pricing_plans add column if not exists whatsapp_quota int;
update public.pricing_plans set whatsapp_quota = 100 where code = 'pro_299';

-- Also a PostgREST computed column: select('..., whatsapp_quota') on gyms.
create or replace function public.whatsapp_quota(g public.gyms)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when coalesce(g.legacy_pricing, false) or g.price_plan is null
      then public.plan_whatsapp_quota(g.plan, g.legacy_pricing)
    else coalesce(
      (select pp.whatsapp_quota from public.pricing_plans pp
        where pp.code = g.price_plan and pp.plan = g.plan),
      public.plan_whatsapp_quota(g.plan, g.legacy_pricing))
  end;
$$;

create or replace function public.consume_whatsapp_allowance(p_gym_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_bucket text;
begin
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
$function$;

-- Paywall states the reminder allowance of the plan being sold.
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
    v_offer := case when v_subscribed then null
                    else public.resolve_offer(v_gym.id, v_code, p_coupon) end;
    v_plans := v_plans || jsonb_build_object(v_plan, jsonb_build_object(
      'code', v_code,
      'monthly_price', (select monthly_price from public.pricing_plans where code = v_code),
      'whatsapp_quota', coalesce(
        (select whatsapp_quota from public.pricing_plans where code = v_code),
        public.plan_whatsapp_quota(v_plan, false)),
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
