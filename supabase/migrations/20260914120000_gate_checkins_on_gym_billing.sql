-- Gate check-ins on the gym's own billing status.
--
-- Before this, a gym whose plan lapsed kept checking members in forever —
-- nothing in the DB tied check-in to an active plan, so the core daily
-- feature stayed free and owners had no reason to renew.
--
-- Three parts:
--   1. gym_billing_active() — the single DB-side source of truth, mirroring
--      hasActiveBillingAccess() in lib/core/billing/billing_access.dart and
--      lib/billing/access.ts on the web.
--   2. A BEFORE INSERT trigger on check_ins. check_ins is written from six
--      places (Flutter staff screen and offline sync, member QR RPC, web
--      staff route, web public /c route, demo seeder) and two of those use
--      the service role, which bypasses RLS. A trigger is the only layer all
--      six must pass through.
--   3. Correct gates inside self_checkin / insert_checkin_secure so members
--      and staff get a readable message instead of a raw trigger exception.
--
-- Also reverts the `plan = 'pro'` gate added to those two RPCs earlier: it
-- wrongly blocked gyms on a live trial and gyms on the ₹299 Starter plan
-- (32 real gyms at the time of writing).

-- ---------------------------------------------------------------------------
-- 1. Single source of truth
-- ---------------------------------------------------------------------------

create or replace function public.gym_billing_active(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    g.status not in ('suspended', 'cancelled')
    and (
      -- grandfathered pro: admin-assigned permanent access, no expiry
      (g.plan = 'pro' and g.plan_expires_at is null)
      -- any plan with a future expiry (pro, starter, one-time, admin-granted)
      or coalesce(g.plan_expires_at > now(), false)
      -- still inside the free trial
      or coalesce(g.trial_ends_at > now(), false)
    ),
    false
  )
  from gyms g
  where g.id = p_gym_id;
$$;

comment on function public.gym_billing_active(uuid) is
  'True when this gym may use paid features. Mirrors hasActiveBillingAccess() '
  'in the Flutter app and the web app — change all three together.';

-- ---------------------------------------------------------------------------
-- 2. The backstop: nothing inserts a check-in for a lapsed gym
-- ---------------------------------------------------------------------------

create or replace function public.enforce_gym_billing_on_checkin()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if public.gym_billing_active(new.gym_id) then
    return new;
  end if;

  -- Callers match on this exact prefix to show a renewal message, so keep it
  -- stable: lib/core/services/{check_in_service,offline_checkin_queue}.dart
  -- and gym-crm/app/api/{check-in,public/checkin}/route.ts.
  raise exception 'subscription_expired: this gym''s subscription is not active';
end;
$$;

drop trigger if exists trg_checkins_billing_gate on public.check_ins;

-- BEFORE INSERT only. Check-OUT is an UPDATE and stays allowed on purpose:
-- a member already inside when the plan lapsed must still be able to leave
-- without stranding an open session.
create trigger trg_checkins_billing_gate
before insert on public.check_ins
for each row
execute function public.enforce_gym_billing_on_checkin();

-- ---------------------------------------------------------------------------
-- 3. Readable messages at the two RPC entry points
-- ---------------------------------------------------------------------------

-- Member QR self check-in. Returns {ok:false, error, reason}; the Flutter
-- member screen renders both fields (lib/features/member/qr/qr_screen.dart).
create or replace function public.self_checkin(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid(); v_gym record; v_member record; v_open record;
  v_checked_in timestamptz; v_checked_out timestamptz;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'Not authenticated'); end if;

  select id, name into v_gym from public.gyms where checkin_token::text = p_token limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'Invalid check-in QR code'); end if;

  if not public.gym_billing_active(v_gym.id) then
    return jsonb_build_object(
      'ok', false,
      'error', 'Check-in unavailable',
      'reason', 'This gym''s subscription is not active. Please ask your gym to renew.'
    );
  end if;

  select id, first_name, last_name, status into v_member
    from public.members where user_id = v_uid and gym_id = v_gym.id limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'You are not a member of this gym'); end if;

  if v_member.status <> 'active' then
    perform public.notify_owner_expired_checkin(
      v_gym.id,
      trim(v_member.first_name || ' ' || coalesce(v_member.last_name, '')),
      v_member.status,
      'self-checkin'
    );
    return jsonb_build_object(
      'ok', false,
      'error', 'Membership not active',
      'reason', 'Your membership is ' || v_member.status || '. Please contact your gym.'
    );
  end if;

  select id, checked_in_at into v_open
    from public.check_ins
    where member_id = v_member.id and gym_id = v_gym.id and checked_out_at is null
    limit 1;

  if found then
    update public.check_ins set checked_out_at = now()
      where id = v_open.id
      returning checked_out_at into v_checked_out;
    return jsonb_build_object(
      'ok', true, 'action', 'checkout',
      'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status),
      'checked_in_at', v_open.checked_in_at, 'checked_out_at', v_checked_out, 'gym_name', v_gym.name
    );
  end if;

  insert into public.check_ins (member_id, gym_id, method)
    values (v_member.id, v_gym.id, 'qr')
    returning checked_in_at into v_checked_in;

  return jsonb_build_object(
    'ok', true, 'action', 'checkin',
    'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status),
    'checked_in_at', v_checked_in, 'gym_name', v_gym.name
  );
end;
$$;

-- Staff-assisted check-in (used by the Flutter offline sync flush).
create or replace function public.insert_checkin_secure(
  p_member_id uuid,
  p_gym_id uuid,
  p_method text default 'qr',
  p_checked_in_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_checked_in_at < now() - interval '24 hours' then
    raise exception 'checkin_too_old: timestamp must be within the last 24 hours';
  end if;
  if p_checked_in_at > now() + interval '5 minutes' then
    raise exception 'checkin_in_future: timestamp cannot be in the future';
  end if;

  if not (p_gym_id = any (auth_gym_ids())) then
    raise exception 'unauthorized: gym mismatch';
  end if;

  if not public.gym_billing_active(p_gym_id) then
    raise exception 'subscription_expired: please renew your subscription to continue checking in members';
  end if;

  if not exists (select 1 from members where id = p_member_id and gym_id = p_gym_id) then
    raise exception 'member_not_in_gym';
  end if;

  insert into check_ins (member_id, gym_id, staff_id, method, checked_in_at)
  values (p_member_id, p_gym_id, auth.uid(), p_method, p_checked_in_at);
end;
$$;

revoke execute on function public.gym_billing_active(uuid) from anon;
grant  execute on function public.gym_billing_active(uuid) to authenticated;
