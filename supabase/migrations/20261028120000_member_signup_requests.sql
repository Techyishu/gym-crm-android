-- Member portal signup for non-Indian numbers. Indian numbers keep the MSG91
-- SMS OTP; international SMS is too costly, so instead the member asks and
-- gym staff approve (the `approve-member-signup` edge function creates the
-- account). The member's chosen password is held only as a bcrypt hash until
-- then, and cleared once the request is decided.

create table if not exists public.member_signup_requests (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  phone text not null,
  password_hash text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null
);

-- One open request per member; asking again replaces it.
create unique index if not exists member_signup_requests_one_pending
  on public.member_signup_requests (member_id) where status = 'pending';
create index if not exists member_signup_requests_gym_pending
  on public.member_signup_requests (gym_id) where status = 'pending';
create index if not exists member_signup_requests_member_id
  on public.member_signup_requests (member_id);
create index if not exists member_signup_requests_decided_by
  on public.member_signup_requests (decided_by);

alter table public.member_signup_requests enable row level security;

create policy member_signup_requests_select on public.member_signup_requests
  for select to authenticated
  using ((select private.has_gym_permission(gym_id, 'members', 'edit')));

-- Staff read the list straight from the table, but never the hash. All writes
-- go through the RPC below or the service-role edge function.
revoke all on public.member_signup_requests from anon, authenticated;
grant select (id, gym_id, member_id, phone, status, created_at)
  on public.member_signup_requests to authenticated;

-- Called by the signup screen before any session exists. Returns a status
-- word the app turns into a message:
--   requested | use_otp | invalid_phone | weak_password | no_gym | no_member | ambiguous
create or replace function public.request_member_signup(
  p_code text,
  p_phone text,
  p_password text
)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_gym uuid;
  v_member uuid;
  v_matches int;
begin
  if length(v_digits) < 8 or length(v_digits) > 15 then
    return 'invalid_phone';
  end if;
  -- Dial codes are prefix-free, so a full number starting 91 is Indian.
  if v_digits like '91%' then
    return 'use_otp';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    return 'weak_password';
  end if;

  select id into v_gym from gyms where member_code = p_code;
  if v_gym is null then
    return 'no_gym';
  end if;

  -- Last 9 digits: tolerates a stored number missing its country code or
  -- carrying a trunk 0. Staff still eyeball the request before approving.
  select count(*), min(id::text)::uuid
    into v_matches, v_member
    from members
   where gym_id = v_gym
     and phone is not null
     and right(regexp_replace(phone, '\D', '', 'g'), 9) = right(v_digits, 9);

  if v_matches = 0 then
    return 'no_member';
  end if;
  if v_matches > 1 then
    return 'ambiguous';
  end if;

  insert into member_signup_requests (gym_id, member_id, phone, password_hash)
  values (v_gym, v_member, '+' || v_digits, crypt(p_password, gen_salt('bf')))
  on conflict (member_id) where status = 'pending'
  do update set phone = excluded.phone,
                password_hash = excluded.password_hash,
                created_at = now();

  return 'requested';
end;
$$;

revoke execute on function public.request_member_signup(text, text, text) from public;
grant execute on function public.request_member_signup(text, text, text) to anon, authenticated;

-- The edge function asks this with the caller's own JWT, so the permission
-- check runs as the staff member, not as service role.
create or replace function public.can_decide_member_signup(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from member_signup_requests r
     where r.id = p_request_id
       and r.status = 'pending'
       and private.has_gym_permission(r.gym_id, 'members', 'edit')
  );
$$;

revoke execute on function public.can_decide_member_signup(uuid) from public;
grant execute on function public.can_decide_member_signup(uuid) to authenticated;

-- The signup screen defaults its country picker to the gym's country.
-- Adding a column changes the return type, so drop and recreate (same
-- argument list — no overload left behind).
drop function if exists public.resolve_gym_by_member_code(text);
create function public.resolve_gym_by_member_code(code text)
returns table(id uuid, name text, country text)
language sql
security definer
set search_path = public
as $$
  select id, name, coalesce(settings->>'country', 'IN')
    from public.gyms where member_code = code;
$$;

grant execute on function public.resolve_gym_by_member_code(text) to anon, authenticated;
