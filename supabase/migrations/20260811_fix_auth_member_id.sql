-- auth_member_id() matched members by email = auth.email(), which only
-- worked by coincidence for the old real-email invite flow (auth account's
-- email happened to equal members.email). Phone-based synthetic-email
-- accounts (member self-serve signup) never match members.email, so every
-- table gated by this function (invoices, payments, memberships,
-- membership_plans, check_ins) silently returned zero rows for them.
-- user_id is the actual link column members_select and memberRecordProvider
-- already use — match on that instead.

create or replace function auth_member_id()
returns uuid
language sql
stable security definer
set search_path to 'public'
as $$
  select id from public.members where user_id = auth.uid() limit 1;
$$;
