-- members_update RLS was scoped only by gym_id = auth_gym_id(), with no role
-- check — unlike members_insert/members_delete, which both already require
-- role IN (owner, manager). Any staff/trainer account could UPDATE any member
-- in their gym at the DB level (PII: phone, email, notes, custom_id,
-- biometric_id, avatar_url), even though the app UI only exposes member
-- editing to manager-or-above (RoleAccess.canEditMembers in
-- lib/core/access/role_access.dart).
--
-- Verified before this change that no legitimate staff/trainer flow relies on
-- direct members-table writes: the only direct UPDATE call sites are the
-- manager-gated full-edit screen and CSV import (both behind
-- RoleAccess.canEditMembers), and the payment-recording flows in
-- dashboard/billing/upcoming_payments screens — which only ever touch
-- status/next_payment_date/billing_interval_months, already restricted to
-- owner/manager by the members_billing_guard trigger regardless of this
-- policy. So this closes the gap without narrowing anything staff/trainer
-- could actually do before.
drop policy if exists members_update on public.members;

create policy members_update on public.members for update
using (
  gym_id = auth_gym_id()
  and (select role from public.profiles where id = auth.uid()) = any (array['owner', 'manager'])
)
with check (
  gym_id = auth_gym_id()
  and (select role from public.profiles where id = auth.uid()) = any (array['owner', 'manager'])
);
