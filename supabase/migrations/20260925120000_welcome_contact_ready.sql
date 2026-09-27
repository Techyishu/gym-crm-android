-- Can "Send welcome message" work for this member's gym?
--
-- send-whatsapp-welcome fills the template's "Call us" number from the gym
-- owner's profiles.phone and fails without it (111 of 503 gyms on
-- 2026-09-25). The app asks this first and hides the button — with the reason
-- — instead of letting staff tap a send that can only fail.
--
-- SECURITY DEFINER because trainers/front desk can't read the owner's profile
-- under RLS; it returns only a yes/no, never the number. Same owner-phone rule
-- as the edge function. Caller must belong to the member's gym.

create function public.welcome_contact_ready(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1
    from public.members m
    join public.profiles p
      on p.gym_id = m.gym_id and p.role = 'owner'
    where m.id = p_member_id
      and m.gym_id = any (public.auth_gym_ids())
      and coalesce(btrim(p.phone), '') <> ''
  );
$$;

revoke all on function public.welcome_contact_ready(uuid) from public, anon;
grant execute on function public.welcome_contact_ready(uuid) to authenticated, service_role;
