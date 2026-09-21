-- Command queue for biometric devices + automatic removal on expiry / re-add on
-- renewal. The bridge serves pending commands when a device polls and records
-- the device's result. Automation is OFF for every device until auto_sync is set.

alter table public.biometric_devices
  add column auto_sync boolean not null default false;

comment on column public.biometric_devices.auto_sync is
  'When true, members with a stored fingerprint backup are removed from this device on expiry and re-added on renewal.';

create table public.device_commands (
  id         bigint generated always as identity primary key,
  gym_id     uuid not null references public.gyms(id) on delete cascade,
  device_id  uuid not null references public.biometric_devices(id) on delete cascade,
  kind       text not null check (kind in ('delete_user', 'restore_user', 'restore_template', 'probe', 'query')),
  pin        text,
  command    text not null,
  status     text not null default 'pending'
             check (status in ('pending', 'sent', 'done', 'failed', 'cancelled')),
  attempts   integer not null default 0,
  sent_at    timestamptz,
  done_at    timestamptz,
  result     text,
  created_at timestamptz not null default now()
);

create index device_commands_queue_idx
  on public.device_commands (device_id, id)
  where status in ('pending', 'sent');

alter table public.device_commands enable row level security;
revoke all on public.device_commands from anon, authenticated;

create or replace function private.norm_pin(p text)
returns text
language sql
immutable
set search_path = ''
as $$ select regexp_replace(p, '^0+(?=\d)', '') $$;

-- Only ever touches a device for a member whose user record AND fingerprint
-- backup are stored: without a backup we could not put them back, so we do nothing.
create or replace function private.sync_biometric_on_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pin text;
begin
  if new.biometric_id is null or new.status is not distinct from old.status then
    return new;
  end if;

  if not exists (
    select 1 from public.biometric_devices d where d.gym_id = new.gym_id and d.auto_sync
  ) then
    return new;
  end if;

  select u.pin into v_pin
    from public.biometric_users u
   where u.gym_id = new.gym_id
     and private.norm_pin(u.pin) = private.norm_pin(new.biometric_id)
     and exists (
       select 1 from public.biometric_templates t where t.gym_id = u.gym_id and t.pin = u.pin
     )
   limit 1;

  if v_pin is null then
    return new;
  end if;

  if (new.status <> 'active' and old.status = 'active')
     or (new.status = 'active' and old.status <> 'active') then
    -- A pending command for the opposite direction is now stale.
    update public.device_commands
       set status = 'cancelled'
     where gym_id = new.gym_id and pin = v_pin and status = 'pending'
       and kind in ('delete_user', 'restore_user', 'restore_template');
  end if;

  if new.status <> 'active' and old.status = 'active' then
    insert into public.device_commands (gym_id, device_id, kind, pin, command)
    select new.gym_id, d.id, 'delete_user', v_pin, 'DATA DELETE USERINFO PIN=' || v_pin
      from public.biometric_devices d
     where d.gym_id = new.gym_id and d.auto_sync;

  elsif new.status = 'active' and old.status <> 'active' then
    insert into public.device_commands (gym_id, device_id, kind, pin, command)
    select new.gym_id, d.id, 'restore_user', u.pin,
           'DATA UPDATE USERINFO ' || regexp_replace(u.raw, '^USER ', '')
      from public.biometric_devices d
      join public.biometric_users u on u.gym_id = d.gym_id and u.pin = v_pin
     where d.gym_id = new.gym_id and d.auto_sync;

    -- Inserted after the user rows, so each device receives the user first.
    insert into public.device_commands (gym_id, device_id, kind, pin, command)
    select new.gym_id, d.id, 'restore_template', t.pin,
           'DATA UPDATE FINGERTMP PIN=' || t.pin
           || E'\tFID=' || t.fid
           || E'\tSize=' || coalesce(t.size::text, '')
           || E'\tValid=' || coalesce(t.valid::text, '1')
           || E'\tTMP=' || t.template
      from public.biometric_devices d
      join public.biometric_templates t on t.gym_id = d.gym_id and t.pin = v_pin
     where d.gym_id = new.gym_id and d.auto_sync
     order by t.fid;
  end if;

  return new;
end;
$$;

create trigger biometric_sync_on_status_change
  after update of status on public.members
  for each row
  when (old.status is distinct from new.status)
  execute function private.sync_biometric_on_status_change();
