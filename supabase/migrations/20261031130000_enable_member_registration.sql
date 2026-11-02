-- One-tap "turn on member self-registration" from Home. Turns the link on and
-- gives it a token with NO expiry, so a QR printed and stuck on the desk keeps
-- working. (The old flow expired every link after 24 hours, which would kill a
-- printed poster overnight.) An existing, unexpired token is kept; a missing or
-- expired one is replaced. Owners can still switch it off or regenerate it.
create or replace function public.enable_member_registration(p_gym_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  g record;
  v_token text;
begin
  if not (select private.has_gym_permission(p_gym_id, 'members', 'edit')) then
    raise exception 'not allowed';
  end if;

  select registration_token, registration_token_expires_at
    into g
    from gyms
   where id = p_gym_id;
  if not found then
    raise exception 'not found';
  end if;

  v_token := g.registration_token;
  if v_token is null
     or v_token = ''
     or (g.registration_token_expires_at is not null
         and g.registration_token_expires_at <= now()) then
    v_token := gen_random_uuid()::text;
  end if;

  update gyms
     set registration_enabled = true,
         registration_token = v_token,
         registration_token_expires_at = null
   where id = p_gym_id;

  return v_token;
end;
$$;

revoke all on function public.enable_member_registration(uuid) from public;
grant execute on function public.enable_member_registration(uuid) to authenticated;
