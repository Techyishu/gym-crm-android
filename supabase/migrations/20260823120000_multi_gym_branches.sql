-- Multi-gym branch support. Purely additive: no existing table/column/policy is altered.
-- profiles.gym_id remains the staff member's PRIMARY gym (unchanged behaviour for all
-- existing single-gym users). staff_gym_access adds the ability for an owner to also
-- be linked to additional gym branches.

create table if not exists public.staff_gym_access (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  unique (profile_id, gym_id)
);

alter table public.staff_gym_access enable row level security;

create policy "staff_read_own_access" on public.staff_gym_access
  for select using (profile_id = auth.uid());

-- Backfill: every existing profile's current gym becomes a staff_gym_access row.
insert into public.staff_gym_access (profile_id, gym_id, role)
select id, gym_id, role from public.profiles where gym_id is not null
on conflict (profile_id, gym_id) do nothing;

-- Keep staff_gym_access in sync whenever profiles.gym_id/role changes
-- (setup_gym's INSERT, or any future service_role UPDATE).
create or replace function public.sync_staff_gym_access()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.gym_id is not null then
    insert into public.staff_gym_access (profile_id, gym_id, role)
    values (new.id, new.gym_id, new.role)
    on conflict (profile_id, gym_id) do update set role = excluded.role;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_gym_access on public.profiles;
create trigger profiles_sync_gym_access
after insert or update of gym_id, role on public.profiles
for each row execute function public.sync_staff_gym_access();

-- All gym_ids a staff member can access (their primary gym + any linked branches).
create or replace function public.auth_gym_ids()
returns uuid[]
language sql
stable security definer
set search_path to 'public'
as $$
  select coalesce(array_agg(gym_id), '{}'::uuid[])
  from public.staff_gym_access where profile_id = auth.uid();
$$;

-- Creates a new gym branch under the same owner. Does NOT touch profiles.gym_id
-- (that column is server-managed by the profiles_role_guard trigger) - the owner's
-- primary gym stays the same, the new branch is only added to staff_gym_access.
create or replace function public.create_gym_branch(
  p_gym_name text,
  p_city text default null,
  p_phone text default null,
  p_gym_type text default null,
  p_member_count text default null,
  p_goals text[] default '{}'::text[]
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_slug text;
  v_gym_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.profiles where id = v_uid;
  if v_role is distinct from 'owner' then
    raise exception 'Only an owner can add a gym branch';
  end if;

  if p_gym_name is null or length(trim(p_gym_name)) = 0 then
    raise exception 'Gym name is required.';
  end if;

  v_slug := regexp_replace(lower(p_gym_name), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug) || '-' || substr(md5(random()::text), 1, 6);

  insert into public.gyms (name, slug, owner_id, trial_ends_at, settings)
  values (
    p_gym_name, v_slug, v_uid, now() + interval '1 day',
    jsonb_build_object(
      'city', p_city, 'gym_type', p_gym_type,
      'member_count', p_member_count, 'goals', to_jsonb(p_goals)
    )
  )
  returning id into v_gym_id;

  insert into public.staff_gym_access (profile_id, gym_id, role)
  values (v_uid, v_gym_id, 'owner');

  return v_gym_id;
end;
$$;
