-- Local device agent: lets the tool on a gym computer see which active members are
-- still waiting for a fingerprint, and lets the bridge link the device ID back to the
-- right member once the fingerprint arrives.
--
-- * The agent authenticates with a per-gym token (only its SHA-256 hash is stored) and
--   can call exactly one function, which is read-only for members.
-- * Each waiting member gets a one-time 9-digit enrol code. The agent writes it into the
--   device's card field (a 32-bit number); the device reports it back to the bridge with
--   the new user, and link_enrolled_member (service role only) sets biometric_id.
-- * Nothing here touches existing tables except the biometric_id write in the link function.

create table public.biometric_agents (
  id           uuid primary key default gen_random_uuid(),
  gym_id       uuid not null references public.gyms(id) on delete cascade,
  name         text not null default 'Gym computer',
  token_hash   text not null unique,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at   timestamptz
);

create table public.biometric_enrol_codes (
  member_id  uuid primary key references public.members(id) on delete cascade,
  gym_id     uuid not null references public.gyms(id) on delete cascade,
  code       text not null check (code ~ '^[0-9]{9}$'),
  created_at timestamptz not null default now(),
  unique (gym_id, code)
);

alter table public.biometric_agents enable row level security;
alter table public.biometric_enrol_codes enable row level security;
revoke all on public.biometric_agents from anon, authenticated;
revoke all on public.biometric_enrol_codes from anon, authenticated;

comment on table public.biometric_agents is
  'Tokens for the local device tool on a gym computer. Only the SHA-256 hash is stored. Service role only.';
comment on table public.biometric_enrol_codes is
  'One-time codes written to the device card field so the bridge can link a new fingerprint to its member.';

-- Run from the SQL editor / service role only. Returns the token once; it cannot be read back.
create or replace function private.create_biometric_agent(p_gym_id uuid, p_name text default 'Gym computer')
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  insert into public.biometric_agents (gym_id, name, token_hash)
  values (p_gym_id, p_name, encode(sha256(convert_to(v_token, 'utf8')), 'hex'));
  return v_token;
end;
$$;

revoke all on function private.create_biometric_agent(uuid, text) from public, anon, authenticated;

-- What the local tool calls. Returns the active members with no biometric ID yet
-- (newest first) with only the name, last 4 phone digits and an enrol code, plus the
-- lowest ID no one in the gym is using or has parked.
create or replace function public.agent_waiting_members(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_agent public.biometric_agents%rowtype;
  v_next  bigint;
  m       record;
  i       int;
begin
  select * into v_agent
    from public.biometric_agents a
   where a.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'utf8')), 'hex')
     and a.revoked_at is null;
  if not found then
    raise exception 'invalid_token' using errcode = '28000';
  end if;

  update public.biometric_agents set last_seen_at = now() where id = v_agent.id;

  for m in
    select mm.id from public.members mm
     where mm.gym_id = v_agent.gym_id and mm.status = 'active' and mm.biometric_id is null
       and not exists (select 1 from public.biometric_enrol_codes c where c.member_id = mm.id)
     order by mm.created_at desc
     limit 100
  loop
    for i in 1..10 loop
      begin
        insert into public.biometric_enrol_codes (member_id, gym_id, code)
        values (m.id, v_agent.gym_id, (100000000 + floor(random() * 899999999))::bigint::text);
        exit;
      exception when unique_violation then
        null;
      end;
    end loop;
  end loop;

  select greatest(
           coalesce((select max(case when x.biometric_id ~ '^[0-9]{1,9}$' then x.biometric_id::bigint end)
                       from public.members x where x.gym_id = v_agent.gym_id), 0),
           coalesce((select max(case when x.biometric_id_parked ~ '^[0-9]{1,9}$' then x.biometric_id_parked::bigint end)
                       from public.members x where x.gym_id = v_agent.gym_id), 0),
           coalesce((select max(case when u.pin ~ '^[0-9]{1,9}$' then u.pin::bigint end)
                       from public.biometric_users u where u.gym_id = v_agent.gym_id), 0)
         ) + 1
    into v_next;

  return jsonb_build_object(
    'next_id', v_next::text,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
               'member_id', w.id,
               'name', w.name,
               'phone_last4', w.last4,
               'code', w.code) order by w.created_at desc)
        from (
          select mm.id, mm.created_at, c.code,
                 btrim(mm.first_name || ' ' || coalesce(mm.last_name, '')) as name,
                 right(regexp_replace(coalesce(mm.phone, ''), '[^0-9]', '', 'g'), 4) as last4
            from public.members mm
            join public.biometric_enrol_codes c on c.member_id = mm.id
           where mm.gym_id = v_agent.gym_id and mm.status = 'active' and mm.biometric_id is null
           order by mm.created_at desc
           limit 100
        ) w
    ), '[]'::jsonb));
end;
$$;

revoke all on function public.agent_waiting_members(text) from public;
grant execute on function public.agent_waiting_members(text) to anon, authenticated;

-- Called by the bridge (service role) when a fingerprint arrives for a user whose card
-- field holds an enrol code. Links only if the member still has no ID and nobody else
-- already uses that PIN in the gym. Returns the member id, or null when nothing linked.
create or replace function public.link_enrolled_member(p_gym_id uuid, p_pin text, p_code text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_member uuid;
begin
  if p_pin !~ '^[0-9]{1,9}$' or p_code !~ '^[0-9]{9}$' then
    return null;
  end if;

  select c.member_id into v_member
    from public.biometric_enrol_codes c
    join public.members m on m.id = c.member_id
   where c.gym_id = p_gym_id and c.code = p_code
     and m.gym_id = p_gym_id and m.biometric_id is null
   for update of m;
  if not found then
    return null;
  end if;

  if exists (
    select 1 from public.members x
     where x.gym_id = p_gym_id and private.norm_pin(x.biometric_id) = private.norm_pin(p_pin)
  ) then
    return null;
  end if;

  update public.members set biometric_id = p_pin where id = v_member;
  delete from public.biometric_enrol_codes where member_id = v_member;
  return v_member;
end;
$$;

revoke all on function public.link_enrolled_member(uuid, text, text) from public, anon, authenticated;
grant execute on function public.link_enrolled_member(uuid, text, text) to service_role;
