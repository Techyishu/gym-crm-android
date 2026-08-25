-- push_notifications.admin_id is a FK to platform_admins (admin-scheduled
-- broadcasts only) and was NOT NULL. notify_owner_expired_checkin() is a
-- system-generated notification with no platform admin involved — allow null.
alter table public.push_notifications alter column admin_id drop not null;

create or replace function public.notify_owner_expired_checkin(
  p_gym_id uuid,
  p_member_name text,
  p_member_status text,
  p_method text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
begin
  select id into v_owner_id
  from profiles
  where gym_id = p_gym_id and role = 'owner'
  limit 1;

  if v_owner_id is null then
    return;
  end if;

  insert into push_notifications (admin_id, target_user_id, title, body, segment, status, scheduled_at)
  values (
    null,
    v_owner_id,
    'Blocked check-in attempt',
    p_member_name || ' tried to check in via ' || p_method || ' but their membership is ' || p_member_status || '.',
    'all',
    'scheduled',
    now()
  );
end;
$$;
