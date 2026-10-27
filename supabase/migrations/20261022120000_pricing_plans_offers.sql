-- Database-driven pricing: plans, per-gym price lock, and offers.
--
-- pricing_plans        one row per price point ('pro_299', 'pro_499', ...).
--                      is_default marks what an unlocked gym is offered.
-- pricing_plan_terms   1/3/6/12-month ladder per plan, each tied to a Dodo product.
-- gyms.price_plan      the gym's locked plan. Set by the Dodo webhook on the first
--                      paid subscription, or by an admin. Never cleared, so a
--                      locked gym keeps its price even after cancel + resubscribe.
--                      null = follow the current default.
-- offers / offer_gyms  % off via a Dodo discount code, auto-applied at checkout
--                      (everyone / selected gyms) or typed by the owner (coupon).
--
-- Changing a lock or the default never touches a live Dodo subscription: Dodo
-- bills against the product a subscription was created on until someone calls
-- changePlan, and nothing here does.
--
-- Additive only. plan_price / plan_expires_at / legacy_pricing are not touched.

-- ── 1. Plans ─────────────────────────────────────────────────────────────────

create table public.pricing_plans (
  code          text primary key,
  plan          text not null check (plan in ('starter', 'pro', 'elite')),
  label         text not null,
  -- ₹/month list price. Written to gyms.plan_price when a gym subscribes, and
  -- what the paywall shows as "your price".
  monthly_price integer not null check (monthly_price > 0),
  is_default    boolean not null default false,
  created_at    timestamptz not null default now()
);

create unique index pricing_plans_one_default_per_plan
  on public.pricing_plans (plan) where is_default;

create table public.pricing_plan_terms (
  plan_code   text not null references public.pricing_plans (code) on delete cascade,
  term        text not null check (term in ('1mo', '3mo', '6mo', '12mo')),
  months      integer not null check (months in (1, 3, 6, 12)),
  price_paise integer not null check (price_paise > 0),
  -- The Dodo product to bill. dodo_product_env names a Vercel env var holding
  -- the product id instead — the live ids for the original products only exist
  -- there. The checkout prefers the env var when both are set, matching how
  -- lib/dodopayments.ts resolved them before this table existed.
  dodo_product_id  text unique,
  dodo_product_env text,
  primary key (plan_code, term),
  check (dodo_product_id is not null or dodo_product_env is not null)
);

-- Prices copied from the hardcoded tables in gym-crm/lib/dodopayments.ts and
-- paywall_screen.dart as of this migration.
insert into public.pricing_plans (code, plan, label, monthly_price, is_default) values
  ('pro_499',     'pro',     'Pro ₹499',          499, true),
  ('pro_249',     'pro',     'Pro ₹249 (legacy)', 249, false),
  ('pro_299',     'pro',     'Pro ₹299',          299, false),
  ('starter_299', 'starter', 'Starter ₹299',      299, true),
  ('elite_999',   'elite',   'Elite ₹999',        999, true);

insert into public.pricing_plan_terms (plan_code, term, months, price_paise, dodo_product_id, dodo_product_env) values
  ('pro_499', '1mo',  1,  49900,  null, 'DODO_PRODUCT_ID_PRO_1MO'),
  ('pro_499', '3mo',  3,  139900, null, 'DODO_PRODUCT_ID_PRO_3MO'),
  ('pro_499', '6mo',  6,  259900, null, 'DODO_PRODUCT_ID_PRO_6MO'),
  ('pro_499', '12mo', 12, 479900, null, 'DODO_PRODUCT_ID_PRO_12MO'),
  ('pro_249', '1mo',  1,  24900,  'pdt_0Ne2koBp2IZCF9l9klZ1b', 'DODO_PRODUCT_ID_PRO_LEGACY'),
  ('pro_249', '3mo',  3,  69400,  'pdt_0NlI9s2bexR61Mzwwegj9', 'DODO_PRODUCT_ID_PRO_LEGACY_3MO'),
  ('pro_249', '6mo',  6,  131500, 'pdt_0NlIA0KQM7ZEHFNmfFNmw', 'DODO_PRODUCT_ID_PRO_LEGACY_6MO'),
  ('pro_249', '12mo', 12, 239000, 'pdt_0NlIDT6RzXCRV4YNUXYwN', 'DODO_PRODUCT_ID_PRO_LEGACY_12MO'),
  ('starter_299', '1mo',  1,  29900,  null, 'DODO_PRODUCT_ID_STARTER_1MO'),
  ('starter_299', '3mo',  3,  83900,  null, 'DODO_PRODUCT_ID_STARTER_3MO'),
  ('starter_299', '6mo',  6,  157900, null, 'DODO_PRODUCT_ID_STARTER_6MO'),
  ('starter_299', '12mo', 12, 287000, null, 'DODO_PRODUCT_ID_STARTER_12MO'),
  ('elite_999', '1mo',  1,  99900,  null, 'DODO_PRODUCT_ID_ELITE_1MO'),
  ('elite_999', '6mo',  6,  529900, null, 'DODO_PRODUCT_ID_ELITE_6MO'),
  ('elite_999', '12mo', 12, 959900, null, 'DODO_PRODUCT_ID_ELITE_12MO');
-- pro_299 has no terms yet: its Dodo product doesn't exist. Add it from
-- /admin/pricing, then make pro_299 the default there.

-- ── 2. Per-gym lock ──────────────────────────────────────────────────────────

alter table public.gyms
  add column price_plan text references public.pricing_plans (code);

-- Lock everyone who has ever paid one of the two existing Pro prices.
update public.gyms set price_plan = 'pro_249'
where legacy_pricing;

update public.gyms set price_plan = 'pro_499'
where not legacy_pricing
  and plan = 'pro'
  and plan_price = 499;

-- Manual grants at other prices (₹300–383) stay unlocked: they follow the
-- default, so they're offered ₹299 once that becomes the default. Their
-- displayed plan_price is unchanged.

-- Owners must not be able to unlock themselves.
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
      or new.status is distinct from old.status) then
    raise exception 'billing fields are server-managed';
  end if;
  return new;
end;
$f$;

-- ── 3. Offers ────────────────────────────────────────────────────────────────

create table public.offers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  -- The Dodo discount code, created in the Dodo dashboard. Dodo enforces the
  -- actual discount; percent_off and cycles here only drive what the paywall
  -- shows, so keep them in step with the Dodo discount.
  code        text not null unique check (code = upper(code) and length(code) >= 3),
  percent_off integer not null check (percent_off between 1 and 100),
  cycles      integer check (cycles is null or cycles > 0),  -- null = every renewal
  -- everyone: auto-applied for every gym
  -- selected: auto-applied for gyms listed in offer_gyms
  -- coupon:   applied only when the owner types the code
  audience    text not null check (audience in ('everyone', 'selected', 'coupon')),
  plan_codes  text[],  -- null = any plan
  starts_at   timestamptz not null default now(),
  ends_at     timestamptz,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table public.offer_gyms (
  offer_id uuid not null references public.offers (id) on delete cascade,
  gym_id   uuid not null references public.gyms (id) on delete cascade,
  primary key (offer_id, gym_id)
);

-- Service role only. Clients read pricing through get_paywall_pricing().
alter table public.pricing_plans enable row level security;
alter table public.pricing_plan_terms enable row level security;
alter table public.offers enable row level security;
alter table public.offer_gyms enable row level security;

-- ── 4. Resolution (shared by the paywall RPC and the checkout routes) ────────

-- Which plan code a gym is offered for a plan type: its lock if the lock is
-- for that type, else the default.
create or replace function public.resolve_price_plan(p_gym_id uuid, p_plan text)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    (select pp.code
       from public.gyms g
       join public.pricing_plans pp on pp.code = g.price_plan
      where g.id = p_gym_id and pp.plan = p_plan),
    (select code from public.pricing_plans where plan = p_plan and is_default)
  );
$$;

-- Best live offer for a gym + plan code. A typed coupon only matches a coupon
-- offer; auto offers apply without one.
create or replace function public.resolve_offer(p_gym_id uuid, p_plan_code text, p_coupon text)
returns public.offers
language sql
stable
security definer
set search_path to ''
as $$
  select o.*
  from public.offers o
  where o.active
    and o.starts_at <= now()
    and (o.ends_at is null or o.ends_at > now())
    and (o.plan_codes is null or p_plan_code = any (o.plan_codes))
    and (
      o.audience = 'everyone'
      or (o.audience = 'selected'
          and exists (select 1 from public.offer_gyms og
                      where og.offer_id = o.id and og.gym_id = p_gym_id))
      or (o.audience = 'coupon' and o.code = upper(trim(coalesce(p_coupon, ''))))
    )
  order by o.percent_off desc
  limit 1;
$$;

revoke all on function public.resolve_price_plan(uuid, text) from public, anon, authenticated;
revoke all on function public.resolve_offer(uuid, text, text) from public, anon, authenticated;
grant execute on function public.resolve_price_plan(uuid, text) to service_role;
grant execute on function public.resolve_offer(uuid, text, text) to service_role;

-- ── 5. Paywall ───────────────────────────────────────────────────────────────

-- Scoped to the caller's primary gym (profiles.gym_id), the same gym the
-- checkout route bills. Never returns the code of an auto-applied offer, so it
-- can't be copied out of the app and shared.
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
        'is_coupon', v_offer.audience = 'coupon') end
    ));
  end loop;

  -- Did the typed coupon match anything, for any plan? Lets the paywall say
  -- "invalid code" instead of silently showing no discount.
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

revoke all on function public.get_paywall_pricing(text) from public, anon;
grant execute on function public.get_paywall_pricing(text) to authenticated;
