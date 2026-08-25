create or replace function public.self_checkin(p_token text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid          uuid := auth.uid();
  v_gym          record;
  v_member       record;
  v_open         record;
  v_checked_in   timestamptz;
  v_checked_out  timestamptz;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Not authenticated');
  end if;

  select id, name into v_gym
  from gyms
  where checkin_token::text = p_token
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Invalid check-in QR code');
  end if;

  select id, first_name, last_name, status into v_member
  from members
  where user_id = v_uid and gym_id = v_gym.id
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'You are not a member of this gym');
  end if;

  if v_member.status = 'expired' then
    perform notify_owner_expired_checkin(v_gym.id, trim(v_member.first_name || ' ' || coalesce(v_member.last_name, '')), v_member.status, 'self-checkin');
    return jsonb_build_object(
      'ok', false,
      'error', 'Membership expired',
      'reason', 'Your membership has expired. Please contact your gym to renew.',
      'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status)
    );
  end if;

  if v_member.status = 'cancelled' then
    perform notify_owner_expired_checkin(v_gym.id, trim(v_member.first_name || ' ' || coalesce(v_member.last_name, '')), v_member.status, 'self-checkin');
    return jsonb_build_object(
      'ok', false,
      'error', 'Membership cancelled',
      'reason', 'Your membership has been cancelled. Please contact your gym.',
      'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status)
    );
  end if;

  -- Check for an open session (no checkout yet).
  select id, checked_in_at into v_open
  from check_ins
  where member_id = v_member.id
    and gym_id    = v_gym.id
    and checked_out_at is null
  limit 1;

  if found then
    -- Open session exists → toggle to checkout
    update check_ins
    set checked_out_at = now()
    where id = v_open.id
    returning checked_out_at into v_checked_out;

    return jsonb_build_object(
      'ok',            true,
      'action',        'checkout',
      'member',        jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status),
      'checked_in_at', v_open.checked_in_at,
      'checked_out_at', v_checked_out,
      'gym_name',      v_gym.name
    );
  end if;

  -- No open session → fresh check-in
  insert into check_ins (member_id, gym_id, method)
  values (v_member.id, v_gym.id, 'qr')
  returning checked_in_at into v_checked_in;

  return jsonb_build_object(
    'ok',           true,
    'action',       'checkin',
    'member',       jsonb_build_object(
      'first_name', v_member.first_name,
      'last_name',  v_member.last_name,
      'status',     v_member.status
    ),
    'checked_in_at', v_checked_in,
    'gym_name',      v_gym.name
  );
end;
$function$
