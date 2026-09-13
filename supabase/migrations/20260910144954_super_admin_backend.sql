-- Additive backend for the Flutter super-admin app. The existing
-- platform_admins table remains the source of truth: its id is auth.users.id.

alter table public.platform_admins
  add column if not exists is_active boolean not null default true,
  add column if not exists require_mfa boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table public.platform_admins enable row level security;
revoke all on table public.platform_admins from public, anon, authenticated;
grant all on table public.platform_admins to service_role;

create table if not exists public.platform_admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.platform_admins(id),
  gym_id uuid references public.gyms(id) on delete set null,
  action text not null,
  reason text,
  before_state jsonb,
  after_state jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists platform_admin_audit_created_idx
  on public.platform_admin_audit_log (created_at desc);
create index if not exists platform_admin_audit_gym_idx
  on public.platform_admin_audit_log (gym_id, created_at desc);

alter table public.platform_admin_audit_log enable row level security;
revoke all on table public.platform_admin_audit_log from public, anon, authenticated;
grant all on table public.platform_admin_audit_log to service_role;

create or replace function public.platform_admin_gym_directory()
returns table (
  id uuid,
  name text,
  code text,
  owner_name text,
  city text,
  plan text,
  status text,
  expiry timestamptz,
  members bigint,
  branches bigint,
  last_active timestamptz,
  provider text,
  price numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    g.id,
    g.name,
    g.member_code as code,
    trim(concat_ws(' ', p.first_name, p.last_name)) as owner_name,
    coalesce(g.settings ->> 'city', '') as city,
    coalesce(g.plan, 'starter') as plan,
    case
      when g.status in ('suspended', 'cancelled') then g.status
      when coalesce(g.plan_expires_at, g.trial_ends_at) < now() then 'expired'
      when g.plan_expires_at between now() and now() + interval '14 days' then 'expiring'
      when g.trial_ends_at > now() and g.plan <> 'pro' then 'trial'
      else coalesce(g.status, 'active')
    end as status,
    coalesce(g.plan_expires_at, g.trial_ends_at) as expiry,
    (select count(*)
      from public.members m
      where m.gym_id = g.id)::bigint as members,
    1::bigint as branches,
    (select max(a.created_at)
      from public.activity_events a
      where a.gym_id = g.id) as last_active,
    case
      when g.dodo_subscription_id is not null then 'Dodo'
      when g.apple_subscription_id is not null then 'RevenueCat'
      else 'Manual'
    end as provider,
    coalesce(g.plan_price, 0)::numeric as price,
    g.created_at
  from public.gyms g
  left join public.profiles p on p.id = g.owner_id;
$$;

revoke all on function public.platform_admin_gym_directory()
  from public, anon, authenticated;
grant execute on function public.platform_admin_gym_directory()
  to service_role;

create or replace function public.create_platform_gym(
  p_owner_id uuid,
  p_gym_name text,
  p_owner_first_name text,
  p_owner_last_name text,
  p_city text,
  p_plan text default 'starter'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gym_id uuid;
  v_slug text;
begin
  if p_owner_id is null or not exists (
    select 1 from auth.users where id = p_owner_id
  ) then
    raise exception 'A valid invited owner is required';
  end if;
  if length(trim(coalesce(p_gym_name, ''))) < 2 then
    raise exception 'Gym name is required';
  end if;
  if p_plan not in ('starter', 'pro') then
    raise exception 'Invalid platform plan';
  end if;

  v_slug := trim(both '-' from regexp_replace(
    lower(trim(p_gym_name)), '[^a-z0-9]+', '-', 'g'
  )) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  insert into public.gyms (
    name, slug, owner_id, plan, trial_ends_at, settings
  ) values (
    trim(p_gym_name), v_slug, p_owner_id, p_plan,
    now() + interval '7 days',
    jsonb_build_object('city', nullif(trim(coalesce(p_city, '')), ''))
  ) returning id into v_gym_id;

  insert into public.profiles (
    id, gym_id, role, first_name, last_name
  ) values (
    p_owner_id, v_gym_id, 'owner', trim(p_owner_first_name),
    trim(coalesce(p_owner_last_name, ''))
  );

  return v_gym_id;
end;
$$;

revoke all on function public.create_platform_gym(
  uuid, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_platform_gym(
  uuid, text, text, text, text, text
) to service_role;
