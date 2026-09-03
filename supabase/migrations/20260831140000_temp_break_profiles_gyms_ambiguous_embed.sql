-- TEMPORARY workaround, backend-only, no app code change.
--
-- PostgREST refuses `profiles?select=...,gyms(...)` (embed) with a 300
-- "more than one relationship was found" error, because
-- staff_permission_overrides has FKs to BOTH profiles(profile_id) and
-- gyms(gym_id), which PostgREST auto-detects as a second (many-to-many)
-- path between profiles and gyms, alongside the real
-- profiles.gym_id -> gyms.id relationship.
--
-- The current app code already avoids embedding (two separate queries
-- instead), so this only affects users stuck on an older build — right
-- now specifically iOS, whose updated build is still pending App Store
-- review and can't be shipped to fix this client-side yet.
--
-- Fix: drop the gym_id FK (the smaller, less central of the two links —
-- profile_id stays intact so the feature keeps its real relationship) and
-- replace its two jobs (referential-integrity check, ON DELETE CASCADE)
-- with a trigger. This removes the second relationship path PostgREST
-- sees, without losing data integrity. Table is empty (0 rows) at the
-- time of this migration, so nothing to backfill.
--
-- REVERT once the iOS build clears App Store review and old clients have
-- aged out:
--   drop trigger staff_permission_overrides_validate_gym on public.staff_permission_overrides;
--   drop trigger gyms_cascade_staff_permission_overrides on public.gyms;
--   drop function private.validate_staff_permission_override_gym();
--   drop function private.cascade_delete_staff_permission_overrides();
--   alter table public.staff_permission_overrides
--     add constraint staff_permission_overrides_gym_id_fkey
--     foreign key (gym_id) references public.gyms(id) on delete cascade;
--   notify pgrst, 'reload schema';

alter table public.staff_permission_overrides
  drop constraint staff_permission_overrides_gym_id_fkey;

create or replace function private.validate_staff_permission_override_gym()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (select 1 from public.gyms where id = new.gym_id) then
    raise exception 'gym_id % does not exist', new.gym_id;
  end if;
  return new;
end;
$$;

create trigger staff_permission_overrides_validate_gym
before insert or update of gym_id on public.staff_permission_overrides
for each row execute function private.validate_staff_permission_override_gym();

create or replace function private.cascade_delete_staff_permission_overrides()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.staff_permission_overrides where gym_id = old.id;
  return old;
end;
$$;

create trigger gyms_cascade_staff_permission_overrides
after delete on public.gyms
for each row execute function private.cascade_delete_staff_permission_overrides();

notify pgrst, 'reload schema';
