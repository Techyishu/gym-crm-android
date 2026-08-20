-- Short, typeable code for member self-serve signup (gym code + phone + OTP).
-- gyms.slug ("badyal-gym-e320d8") is a URL slug, not something a member can
-- type on a phone keyboard or a staff member can read aloud at the desk.

alter table public.gyms add column if not exists member_code text unique;

create or replace function generate_gym_member_code()
returns text
language plpgsql
as $$
declare
  code text;
  exists_already boolean;
begin
  loop
    code := lpad(floor(random() * 1000000)::text, 6, '0');
    select exists(select 1 from public.gyms where member_code = code) into exists_already;
    exit when not exists_already;
  end loop;
  return code;
end;
$$;

update public.gyms set member_code = generate_gym_member_code() where member_code is null;

alter table public.gyms alter column member_code set default generate_gym_member_code();
alter table public.gyms alter column member_code set not null;

-- Public lookup: resolve a gym by its member code without needing an
-- authenticated session (member hasn't signed up yet). SECURITY DEFINER
-- bypasses gyms' normal RLS (which requires an existing staff session);
-- only id/name are exposed, nothing sensitive.
create or replace function resolve_gym_by_member_code(code text)
returns table(id uuid, name text)
language sql
security definer
set search_path = public
as $$
  select id, name from public.gyms where member_code = code;
$$;

grant execute on function resolve_gym_by_member_code(text) to anon, authenticated;
