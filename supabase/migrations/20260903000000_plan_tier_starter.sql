-- ₹299 Starter tier.
--
-- 'starter' used to be the DEFAULT for every new gym, i.e. it meant "signed up,
-- never paid" (241 rows, 0 of them with a dodo_subscription_id). That name is
-- now the paid ₹299 tier, so the unpaid default moves to 'free'.
--
-- Consequence worth knowing: after this migration no *existing* gym is on
-- 'starter', so every limit scoped to plan = 'starter' below applies to new
-- signups only, with no created_at cutoff needed. Existing gyms keep the
-- behaviour they have today.
--
-- No explicit begin/commit: `supabase db push` (and apply_migration) already run
-- each migration inside one transaction, and a nested commit here would close it
-- early, leaving the rest of the file outside any rollback.

-- ── 1. Free the 'starter' name ───────────────────────────────────────────────

-- Guard: only gyms with no live entitlement should be carrying 'starter'.
--
-- Checked at authoring time: of the 241 rows, 0 had a subscription id and 0 had
-- a future plan_expires_at. Four (Fitness Hub Gym, Karnal Gym, Mangat health
-- club, City Fitness) are *lapsed* paying customers — legacy_pricing /
-- plan_price / price_locked_at set, all expired. Those columns are not touched
-- here, so their locked-in rate survives if they return.
--
-- The guard covers an active grant appearing between authoring and running this,
-- since plans are assigned manually as well as by the Dodo webhook. Abort rather
-- than silently relabel a paying customer.
do $$
declare
  v_blocking integer;
begin
  select count(*) into v_blocking
  from public.gyms
  where plan = 'starter'
    and (dodo_subscription_id is not null
         or apple_subscription_id is not null
         or plan_expires_at > now());

  if v_blocking > 0 then
    raise exception
      '% gym(s) on plan=starter have live paid access — move them to pro before migrating',
      v_blocking;
  end if;
end $$;

update public.gyms set plan = 'free' where plan = 'starter';

alter table public.gyms alter column plan set default 'free';

-- handle_new_user hardcoded 'starter' for owner signups. Same body, new default.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  new_gym_id uuid;
  v_gym_name text;
  v_slug     text;
  v_first    text;
  v_last     text;
begin
  v_first    := coalesce(new.raw_user_meta_data->>'first_name', '');
  v_last     := coalesce(new.raw_user_meta_data->>'last_name', '');
  v_gym_name := coalesce(new.raw_user_meta_data->>'gym_name', v_first || '''s Gym');

  -- Case 1: invited staff — gym_id already provided in metadata
  if new.raw_user_meta_data->>'gym_id' is not null then
    insert into public.profiles (id, gym_id, role, first_name, last_name)
    values (
      new.id,
      (new.raw_user_meta_data->>'gym_id')::uuid,
      coalesce(new.raw_user_meta_data->>'role', 'staff'),
      v_first,
      v_last
    )
    on conflict (id) do nothing;

  -- Case 2: new owner signup — create gym then profile
  elsif new.raw_user_meta_data->>'gym_name' is not null then
    v_slug := lower(regexp_replace(v_gym_name, '[^a-zA-Z0-9]+', '-', 'g'));
    v_slug := trim(both '-' from v_slug);
    v_slug := substr(v_slug, 1, 50);

    if exists (select 1 from public.gyms where slug = v_slug) then
      v_slug := v_slug || '-' || substr(new.id::text, 1, 6);
    end if;

    insert into public.gyms (name, slug, owner_id, plan)
    values (v_gym_name, v_slug, new.id, 'free')
    returning id into new_gym_id;

    insert into public.profiles (id, gym_id, role, first_name, last_name)
    values (new.id, new_gym_id, 'owner', v_first, v_last)
    on conflict (id) do nothing;
  end if;

  return new;
end;
$function$;

-- ── 2. Plan limits — single source of truth ──────────────────────────────────

-- null = unlimited. Kept as functions rather than a table: four rows that change
-- when pricing changes, and a migration is already how pricing changes ship.
create or replace function public.plan_member_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan when 'starter' then 100 else null end;
$$;

create or replace function public.plan_staff_limit(p_plan text)
returns integer
language sql
immutable
as $$
  select case p_plan when 'starter' then 1 else null end;
$$;

-- Mirrors planQuota() in the whatsapp-reminders / send-whatsapp-invoice edge
-- functions. 0 = feature unavailable on this plan.
create or replace function public.plan_whatsapp_quota(p_plan text, p_legacy boolean)
returns integer
language sql
immutable
as $$
  select case
    when coalesce(p_legacy, false) then 100
    when p_plan = 'starter' then 100
    when p_plan = 'pro'     then 300
    when p_plan = 'elite'   then 1500
    else 0
  end;
$$;

-- ── 3. Enforce the caps ──────────────────────────────────────────────────────

-- Enforced in the DB, not the app: members are inserted from the add-member
-- sheet, the CSV importer and the web app. One trigger covers all three; three
-- client-side checks would leave whichever caller we forget wide open.
--
-- Demo rows are excluded so a seeded demo gym can't consume a real customer's
-- allowance. Counts only on INSERT — an existing over-limit gym that downgrades
-- keeps its data and simply cannot add more.
create or replace function public.enforce_member_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_limit integer;
  v_count integer;
begin
  if coalesce(new.is_demo_data, false) then
    return new;
  end if;

  select plan_member_limit(plan) into v_limit from gyms where id = new.gym_id;
  if v_limit is null then
    return new;
  end if;

  select count(*) into v_count
  from members
  where gym_id = new.gym_id and coalesce(is_demo_data, false) = false;

  if v_count >= v_limit then
    raise exception 'member_limit_reached: % members on the Starter plan', v_limit
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_member_limit on public.members;
create trigger trg_enforce_member_limit
  before insert on public.members
  for each row execute function public.enforce_member_limit();

create or replace function public.enforce_staff_limit()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_limit integer;
  v_count integer;
begin
  select plan_staff_limit(plan) into v_limit from gyms where id = new.gym_id;
  if v_limit is null then
    return new;
  end if;

  select count(*) into v_count from staff_gym_access where gym_id = new.gym_id;

  if v_count >= v_limit then
    raise exception 'staff_limit_reached: % staff login on the Starter plan', v_limit
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_staff_limit on public.staff_gym_access;
create trigger trg_enforce_staff_limit
  before insert on public.staff_gym_access
  for each row execute function public.enforce_staff_limit();

