-- Look up an auth account by email, for the verify-phone-otp edge function.
--
-- Needed to heal orphaned member accounts: if an auth user was created on the
-- member-signup path but the `members.user_id` link never landed, a retry
-- cannot call auth.admin.createUser() again — the synthetic email already
-- exists, so creation fails and the member is permanently stuck. The function
-- adopts the existing account instead, which needs a way to find it by email.
--
-- The admin listUsers() API is paginated with no email filter, so this does
-- the lookup in one indexed query.
--
-- service_role only: this maps an email to a user id, so it must never be
-- reachable by anon or by a signed-in user.

create or replace function public.auth_user_id_for_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$$;

revoke all on function public.auth_user_id_for_email(text) from public;
revoke all on function public.auth_user_id_for_email(text) from anon;
revoke all on function public.auth_user_id_for_email(text) from authenticated;
grant execute on function public.auth_user_id_for_email(text) to service_role;
