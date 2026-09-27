-- Expiry deletes a member from the device, which frees their biometric ID there;
-- the owner can then enrol someone else on it. The app used to keep the ID on the
-- expired member, so two people shared one ID (Bajrang: Mohit/Mohan, 2026-09-24).
--
-- Now, when expiry queues the device delete, the ID is "parked": members.biometric_id
-- is cleared (the ID is free for anyone) and the old value is kept in
-- biometric_id_parked, and the fingerprint backup is re-keyed to 'parked:<member id>'
-- so a new enrolment on that ID cannot overwrite it. On renewal the backup is
-- restored under the parked ID if still free, otherwise under the next free ID.

alter table public.members add column if not exists biometric_id_parked text;

create or replace function private.sync_biometric_on_status_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_pin    text;
  v_key    text := 'parked:' || new.id;
  v_target text;
  v_pat    text := 'PIN=[^' || chr(9) || ']*';
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if not exists (
    select 1 from public.biometric_devices d where d.gym_id = new.gym_id and d.auto_sync
  ) then
    return new;
  end if;

  -- Expiry: delete from device, park the ID and the backup.
  if new.status <> 'active' and old.status = 'active' then
    if new.biometric_id is null then
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

    update public.device_commands
       set status = 'cancelled'
     where gym_id = new.gym_id and pin = v_pin and status = 'pending'
       and kind in ('delete_user', 'restore_user', 'restore_template');

    insert into public.device_commands (gym_id, device_id, kind, pin, command)
    select new.gym_id, d.id, 'delete_user', v_pin, 'DATA DELETE USERINFO PIN=' || v_pin
      from public.biometric_devices d
     where d.gym_id = new.gym_id and d.auto_sync;

    -- Frozen/blocked can be set by staff without members:edit, and the member-update
    -- guard would reject the extra column change, so those keep their ID as before.
    if new.status not in ('frozen', 'blocked') then
      delete from public.biometric_templates where gym_id = new.gym_id and pin = v_key;
      delete from public.biometric_users     where gym_id = new.gym_id and pin = v_key;
      update public.biometric_templates set pin = v_key where gym_id = new.gym_id and pin = v_pin;
      update public.biometric_users     set pin = v_key where gym_id = new.gym_id and pin = v_pin;

      update public.members
         set biometric_id = null, biometric_id_parked = new.biometric_id
       where id = new.id;
    end if;

    return new;
  end if;

  -- Renewal.
  if new.status = 'active' and old.status <> 'active' then
    if exists (
      select 1 from public.biometric_users u where u.gym_id = new.gym_id and u.pin = v_key
    ) then
      -- Parked backup: keep the old ID if nobody took it, else use the next free one.
      v_target := new.biometric_id_parked;
      if v_target is null
         or exists (
           select 1 from public.members m
            where m.gym_id = new.gym_id and m.id <> new.id
              and private.norm_pin(m.biometric_id) = private.norm_pin(v_target)
         )
         or exists (
           select 1 from public.biometric_users u
            where u.gym_id = new.gym_id
              and private.norm_pin(u.pin) = private.norm_pin(v_target)
         ) then
        select (greatest(
                 coalesce((select max(case when m.biometric_id ~ '^\d{1,9}$' then m.biometric_id::bigint end)
                             from public.members m where m.gym_id = new.gym_id), 0),
                 coalesce((select max(case when u.pin ~ '^\d{1,9}$' then u.pin::bigint end)
                             from public.biometric_users u where u.gym_id = new.gym_id), 0)
               ) + 1)::text
          into v_target;
      end if;

      update public.device_commands
         set status = 'cancelled'
       where gym_id = new.gym_id and status = 'pending'
         and pin = coalesce(new.biometric_id_parked, v_target)
         and kind in ('delete_user', 'restore_user', 'restore_template');

      update public.biometric_users
         set pin = v_target, raw = regexp_replace(raw, v_pat, 'PIN=' || v_target)
       where gym_id = new.gym_id and pin = v_key;
      update public.biometric_templates set pin = v_target
       where gym_id = new.gym_id and pin = v_key;

      update public.members
         set biometric_id = v_target, biometric_id_parked = null
       where id = new.id;
      v_pin := v_target;
    elsif new.biometric_id is not null then
      -- Legacy: expired before parking existed; backup is still under the member's ID.
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
      update public.device_commands
         set status = 'cancelled'
       where gym_id = new.gym_id and pin = v_pin and status = 'pending'
         and kind in ('delete_user', 'restore_user', 'restore_template');
    else
      return new;
    end if;

    insert into public.device_commands (gym_id, device_id, kind, pin, command)
    select new.gym_id, d.id, 'restore_user', u.pin,
           'DATA UPDATE USERINFO ' || regexp_replace(u.raw, '^USER ', '')
      from public.biometric_devices d
      join public.biometric_users u on u.gym_id = d.gym_id and u.pin = v_pin
     where d.gym_id = new.gym_id and d.auto_sync;

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
$function$;
