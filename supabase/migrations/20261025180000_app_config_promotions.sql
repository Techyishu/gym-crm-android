-- Growth controls that change without an app release:
--   app_config   — key/value settings the app and backend read
--   promotions   — the big offer popup on Home
--   gyms.firebase_app_instance_id — lets the Dodo webhook send the purchase
--                  event to Google Analytics server-side (for Google Ads)
--   NEW50 / NEW500 offers (₹50 off monthly, ₹500 off yearly on ₹299 Pro),
--   created inactive until the matching Dodo discount codes exist.

-- ── app_config ───────────────────────────────────────────────────────────────
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);
alter table public.app_config enable row level security;
-- Not secret: anyone signed in (and the signup flow) may read it.
drop policy if exists app_config_read on public.app_config;
create policy app_config_read on public.app_config for select using (true);

insert into public.app_config (key, value, description) values
  ('trial_days', '3', 'Free trial length for new gyms, in days (setup_gym / create_gym_branch).'),
  ('paywall_default_term', '"1mo"', 'Plan length pre-selected on the paywall: 1mo, 3mo, 6mo or 12mo.'),
  ('support_whatsapp', '"917541004076"', 'WhatsApp number (country code + number) for "Talk to us" links.'),
  ('whatsapp_low_warning', '20', 'Push "running low" when this many WhatsApp reminders are left.')
on conflict (key) do nothing;

create or replace function public.app_trial_days()
returns int
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select (value #>> '{}')::int from public.app_config where key = 'trial_days'),
    3);
$$;

-- New gyms (signup and new branches) get the configured trial instead of a
-- hardcoded 3 days. Rewrites only that expression in the live definitions.
do $$
declare
  f text;
  d text;
begin
  foreach f in array array[
    'public.setup_gym(text,text,text,text,text,text[])',
    'public.create_gym_branch(text,text,text,text,text,text[])'
  ] loop
    d := pg_get_functiondef(f::regprocedure);
    if position('now() + interval ''3 days''' in d) > 0 then
      execute replace(d, 'now() + interval ''3 days''',
                      'now() + make_interval(days => public.app_trial_days())');
    end if;
  end loop;
end $$;

-- ── promotions ───────────────────────────────────────────────────────────────
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  image_url text,
  cta_label text not null default 'See plans',
  -- 'paywall' opens the subscription screen, 'route' pushes cta_value as an
  -- in-app route (e.g. /staff/reminders), 'url' opens cta_value externally.
  cta_action text not null default 'paywall' check (cta_action in ('paywall', 'route', 'url')),
  cta_value text,
  -- Who sees it: everyone, gyms on trial, gyms whose trial/plan ended, or
  -- paying gyms.
  audience text not null default 'all' check (audience in ('all', 'trial', 'expired', 'paying')),
  -- 'once' = once per device, 'daily' = at most once a day, 'always' = every Home open.
  frequency text not null default 'daily' check (frequency in ('once', 'daily', 'always')),
  priority int not null default 0,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.promotions enable row level security;
drop policy if exists promotions_read on public.promotions;
create policy promotions_read on public.promotions for select to authenticated
  using (active and starts_at <= now() and (ends_at is null or ends_at > now()));

-- ── server-side purchase analytics ───────────────────────────────────────────
alter table public.gyms add column if not exists firebase_app_instance_id text;

-- The owner's app reports its Firebase app_instance_id; the Dodo webhook uses
-- it to send `purchase` through the GA4 Measurement Protocol.
create or replace function public.set_analytics_instance(p_instance_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.gyms g
     set firebase_app_instance_id = nullif(trim(p_instance_id), '')
    from public.profiles p
   where p.id = auth.uid() and p.role = 'owner' and g.id = p.gym_id
     and g.firebase_app_instance_id is distinct from nullif(trim(p_instance_id), '');
$$;
revoke all on function public.set_analytics_instance(text) from public, anon;
grant execute on function public.set_analytics_instance(text) to authenticated;

-- ── new-customer offers on ₹299 Pro (inactive until Dodo codes exist) ────────
insert into public.offers (name, code, amount_off, cycles, audience, plan_codes, terms, active) values
  ('New customer offer', 'NEW50',  50,  1, 'everyone', array['pro_299'], array['1mo'],  false),
  ('New customer offer', 'NEW500', 500, 1, 'everyone', array['pro_299'], array['12mo'], false)
on conflict (code) do nothing;
