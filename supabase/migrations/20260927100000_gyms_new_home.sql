-- Per-gym switch between the old staff design and the new one
-- (3-tab nav + card Home + money Dashboard).
--
-- Existing gyms get false (nothing changes for them); gyms created from now on
-- get true. A new branch copies the owner's existing gyms so one owner never
-- sees two designs across branches. The owner flips it in Settings; support can
-- flip it with one UPDATE, and `update gyms set new_home = false` is the
-- emergency rollback — no app release needed.
--
-- Apply BEFORE shipping the app patch that selects this column: the staff
-- profile query names it explicitly (the app retries without it, but don't
-- rely on that).

alter table public.gyms
  add column if not exists new_home boolean not null default false;

alter table public.gyms
  alter column new_home set default true;

-- Branches follow the owner's existing gyms instead of the column default.
create or replace function public.gyms_inherit_new_home()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_existing boolean;
begin
  select g.new_home into v_existing
  from public.gyms g
  where g.owner_id = new.owner_id
  order by g.created_at
  limit 1;

  if v_existing is not null then
    new.new_home := v_existing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_gyms_inherit_new_home on public.gyms;
create trigger trg_gyms_inherit_new_home
  before insert on public.gyms
  for each row
  execute function public.gyms_inherit_new_home();
