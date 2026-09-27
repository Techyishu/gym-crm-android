-- The suggested next ID follows GymCRM's own numbering (highest member/parked ID + 1)
-- and only steps over IDs already used by a member or a stored device user. Using the
-- highest device PIN instead would jump to values like 110034 at gyms whose old software
-- enrolled odd IDs (Fit Wolf has 110033, 12121, ...).

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
                       from public.members x where x.gym_id = v_agent.gym_id), 0)
         ) + 1
    into v_next;

  while v_next < 999999999
        and (exists (select 1 from public.biometric_users u
                      where u.gym_id = v_agent.gym_id and private.norm_pin(u.pin) = v_next::text)
             or exists (select 1 from public.members x
                         where x.gym_id = v_agent.gym_id
                           and (private.norm_pin(x.biometric_id) = v_next::text
                                or private.norm_pin(x.biometric_id_parked) = v_next::text)))
  loop
    v_next := v_next + 1;
  end loop;

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
