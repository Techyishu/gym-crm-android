-- Member self-registration, approval-first. A member scans the gym's QR, fills
-- their own details on /register/<token> (Flutter web) and picks a plan. Nothing
-- is added to the gym until staff review the request, set paid / unpaid and
-- accept — accepting just opens the normal Add member form prefilled.
--
-- No email or password: members have no login out of this. They are never
-- created here; staff create the member through the existing add-member path.
--
-- The photo rides along as a small (<= ~400 KB) bytea. Member photos live on a
-- Cloudflare Worker that needs a signed-in user, which an anonymous visitor is
-- not, so the staff app uploads it to the Worker on accept and the bytes are
-- dropped the moment the request is decided or expires.

create table if not exists public.member_registration_requests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  first_name text not null,
  last_name text,
  phone text not null,
  email text,
  dob date,
  blood_group text,
  emergency_contact_name text,
  emergency_contact_phone text,
  plan_id uuid references public.membership_plans(id) on delete set null,
  photo bytea,
  has_photo boolean generated always as (photo is not null) stored,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  member_id uuid references public.members(id) on delete set null
);

-- Asking again with the same number replaces the open request.
create unique index if not exists member_registration_requests_one_pending
  on public.member_registration_requests (gym_id, phone) where status = 'pending';
create index if not exists member_registration_requests_gym_pending
  on public.member_registration_requests (gym_id, created_at) where status = 'pending';
create index if not exists member_registration_requests_gym_created
  on public.member_registration_requests (gym_id, created_at);
create index if not exists member_registration_requests_plan_id
  on public.member_registration_requests (plan_id);
create index if not exists member_registration_requests_decided_by
  on public.member_registration_requests (decided_by);
create index if not exists member_registration_requests_member_id
  on public.member_registration_requests (member_id);

alter table public.member_registration_requests enable row level security;

create policy member_registration_requests_select on public.member_registration_requests
  for select to authenticated
  using ((select private.has_gym_permission(gym_id, 'members', 'edit')));

-- Staff read the list from the table, never the photo bytes (those come from
-- get_registration_photo, one request at a time). Writes only via the RPCs.
revoke all on public.member_registration_requests from anon, authenticated;
grant select (
  id, gym_id, first_name, last_name, phone, email, dob, blood_group,
  emergency_contact_name, emergency_contact_phone, plan_id, has_photo,
  status, created_at, expires_at, decided_at, member_id
) on public.member_registration_requests to authenticated;

-- ── Public: what the form needs to render ──────────────────────────────────
create or replace function public.get_registration_form(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  g record;
  v_show_prices boolean;
begin
  select id, name, settings, registration_enabled, registration_token_expires_at
    into g
    from gyms
   where registration_token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if not coalesce(g.registration_enabled, false) then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if g.registration_token_expires_at is not null
     and g.registration_token_expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  v_show_prices := coalesce((g.settings->>'registration_show_prices')::boolean, true);

  return jsonb_build_object(
    'ok', true,
    'gym', jsonb_build_object(
      'name', g.name,
      'country', g.settings->>'country',
      'currency', g.settings->>'currency'
    ),
    'show_prices', v_show_prices,
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'price', case when v_show_prices then p.price end,
        'billing_interval', p.billing_interval,
        'billing_interval_months', p.billing_interval_months,
        'billing_interval_days', p.billing_interval_days
      ) order by p.price)
      from membership_plans p
      where p.gym_id = g.id
        and p.is_active
        and not coalesce(p.is_demo_data, false)
    ), '[]'::jsonb)
  );
end;
$$;

-- ── Public: submit ─────────────────────────────────────────────────────────
-- Returns {ok:true} or {ok:false, reason}. reason is a code the page turns
-- into a message: invalid | disabled | expired | rate_limited | too_many |
-- invalid_name | invalid_phone | invalid_email | invalid_dob | invalid_blood |
-- invalid_plan | invalid_photo | photo_too_large
create or replace function public.submit_member_registration(
  p_token text,
  p_data jsonb,
  p_photo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  g record;
  v_first text;
  v_last text;
  v_digits text;
  v_phone text;
  v_email text;
  v_dob date;
  v_blood text;
  v_ename text;
  v_edigits text;
  v_ephone text;
  v_plan uuid;
  v_bytes bytea;
  v_id uuid;
begin
  select id, registration_enabled, registration_token_expires_at
    into g
    from gyms
   where registration_token = p_token;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  if not coalesce(g.registration_enabled, false) then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if g.registration_token_expires_at is not null
     and g.registration_token_expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;

  -- Anonymous caller: cap what one link can take in. 60 submissions in 10
  -- minutes is a busy gym on opening day; more than that is a script.
  if (select count(*) from member_registration_requests
       where gym_id = g.id and created_at > now() - interval '10 minutes') >= 60 then
    return jsonb_build_object('ok', false, 'reason', 'rate_limited');
  end if;
  if (select count(*) from member_registration_requests
       where gym_id = g.id and status = 'pending') >= 200 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;

  v_first := left(btrim(coalesce(p_data->>'first_name', '')), 60);
  if v_first = '' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_name');
  end if;
  v_last := nullif(left(btrim(coalesce(p_data->>'last_name', '')), 60), '');

  v_digits := regexp_replace(coalesce(p_data->>'phone', ''), '\D', '', 'g');
  if length(v_digits) < 8 or length(v_digits) > 15 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_phone');
  end if;
  v_phone := '+' || v_digits;

  v_email := nullif(lower(btrim(coalesce(p_data->>'email', ''))), '');
  if v_email is not null
     and (length(v_email) > 120 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_email');
  end if;

  begin
    v_dob := nullif(p_data->>'dob', '')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'reason', 'invalid_dob');
  end;
  if v_dob is not null and (v_dob > current_date or v_dob < date '1900-01-01') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_dob');
  end if;

  v_blood := nullif(btrim(coalesce(p_data->>'blood_group', '')), '');
  if v_blood is not null
     and v_blood not in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') then
    return jsonb_build_object('ok', false, 'reason', 'invalid_blood');
  end if;

  v_ename := nullif(left(btrim(coalesce(p_data->>'emergency_contact_name', '')), 80), '');
  v_edigits := regexp_replace(coalesce(p_data->>'emergency_contact_phone', ''), '\D', '', 'g');
  if v_edigits <> '' then
    if length(v_edigits) < 8 or length(v_edigits) > 15 then
      return jsonb_build_object('ok', false, 'reason', 'invalid_phone');
    end if;
    v_ephone := '+' || v_edigits;
  end if;

  if nullif(p_data->>'plan_id', '') is not null then
    begin
      select id into v_plan
        from membership_plans
       where id = (p_data->>'plan_id')::uuid
         and gym_id = g.id
         and is_active;
    exception when others then
      v_plan := null;
    end;
    if v_plan is null then
      return jsonb_build_object('ok', false, 'reason', 'invalid_plan');
    end if;
  end if;

  if p_photo is not null and p_photo <> '' then
    if length(p_photo) > 600000 then
      return jsonb_build_object('ok', false, 'reason', 'photo_too_large');
    end if;
    begin
      v_bytes := decode(p_photo, 'base64');
    exception when others then
      return jsonb_build_object('ok', false, 'reason', 'invalid_photo');
    end;
    -- JPEG, PNG or WebP only, judged by the first bytes, not the filename.
    if not (
      substring(v_bytes from 1 for 3) = '\xffd8ff'
      or substring(v_bytes from 1 for 4) = '\x89504e47'
      or (substring(v_bytes from 1 for 4) = '\x52494646'
          and substring(v_bytes from 9 for 4) = '\x57454250')
    ) then
      return jsonb_build_object('ok', false, 'reason', 'invalid_photo');
    end if;
  end if;

  select id into v_id
    from member_registration_requests
   where gym_id = g.id and phone = v_phone and status = 'pending';

  if v_id is not null then
    update member_registration_requests
       set first_name = v_first,
           last_name = v_last,
           email = v_email,
           dob = v_dob,
           blood_group = v_blood,
           emergency_contact_name = v_ename,
           emergency_contact_phone = v_ephone,
           plan_id = v_plan,
           photo = coalesce(v_bytes, photo),
           created_at = now(),
           expires_at = now() + interval '14 days'
     where id = v_id;
  else
    insert into member_registration_requests (
      gym_id, first_name, last_name, phone, email, dob, blood_group,
      emergency_contact_name, emergency_contact_phone, plan_id, photo
    ) values (
      g.id, v_first, v_last, v_phone, v_email, v_dob, v_blood,
      v_ename, v_ephone, v_plan, v_bytes
    );
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- ── Staff ──────────────────────────────────────────────────────────────────
create or replace function public.get_registration_photo(p_request_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  select gym_id, photo into r from member_registration_requests where id = p_request_id;
  if not found then
    return null;
  end if;
  if not (select private.has_gym_permission(r.gym_id, 'members', 'edit')) then
    raise exception 'not allowed';
  end if;
  if r.photo is null then
    return null;
  end if;
  return regexp_replace(encode(r.photo, 'base64'), '\s', '', 'g');
end;
$$;

-- Marks a pending request approved (with the member staff created) or
-- rejected, and drops the photo bytes either way.
create or replace function public.decide_member_registration(
  p_id uuid,
  p_approve boolean,
  p_member_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gym uuid;
begin
  select gym_id into v_gym from member_registration_requests where id = p_id;
  if v_gym is null then
    raise exception 'not found';
  end if;
  if not (select private.has_gym_permission(v_gym, 'members', 'edit')) then
    raise exception 'not allowed';
  end if;
  update member_registration_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_at = now(),
         decided_by = auth.uid(),
         member_id = case when p_approve then p_member_id end,
         photo = null
   where id = p_id and status = 'pending';
end;
$$;

-- ── Housekeeping ───────────────────────────────────────────────────────────
-- Open requests lapse after 14 days; decided/expired rows go after 30.
create or replace function public.expire_member_registrations()
returns void
language sql
security definer
set search_path = public
as $$
  update member_registration_requests
     set status = 'expired', photo = null
   where status = 'pending' and expires_at <= now();
  delete from member_registration_requests
   where status <> 'pending'
     and coalesce(decided_at, expires_at) < now() - interval '30 days';
$$;

revoke all on function public.get_registration_form(text) from public;
revoke all on function public.submit_member_registration(text, jsonb, text) from public;
revoke all on function public.get_registration_photo(uuid) from public;
revoke all on function public.decide_member_registration(uuid, boolean, uuid) from public;
revoke all on function public.expire_member_registrations() from public;

grant execute on function public.get_registration_form(text) to anon, authenticated;
grant execute on function public.submit_member_registration(text, jsonb, text) to anon, authenticated;
grant execute on function public.get_registration_photo(uuid) to authenticated;
grant execute on function public.decide_member_registration(uuid, boolean, uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'expire-member-registrations',
      '20 3 * * *',
      'select public.expire_member_registrations()'
    );
  end if;
end;
$$;
