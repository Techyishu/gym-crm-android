-- profiles.role / profiles.gym_id can currently be updated by any authenticated
-- staff member on any profile in their gym (profiles_own_gym is an ALL-command
-- RLS policy scoped only by gym_id = auth_gym_id(), with no restriction that
-- id = auth.uid() and no column guard). Verified live (rolled-back transaction):
-- a plain 'staff' account can PATCH its own row to role = 'owner'.
--
-- Every legitimate write to role/gym_id already goes through service-role paths:
--   - setup_gym() RPC does an INSERT (not UPDATE) for the initial owner profile
--   - /api/staff (invite + delete) in the web repo uses the service-role client
-- so this trigger has no legitimate authenticated-role caller to accommodate.
create or replace function block_profile_role_edit()
returns trigger
language plpgsql
as $f$
begin
  if auth.role() <> 'service_role'
     and (new.role is distinct from old.role
          or new.gym_id is distinct from old.gym_id) then
    raise exception 'role and gym_id are server-managed';
  end if;
  return new;
end;
$f$;

create or replace trigger profiles_role_guard
before update on public.profiles
for each row execute function block_profile_role_edit();

-- gyms.status gates app access in lib/core/billing/billing_access.dart
-- (suspended/cancelled blocks the whole app) but was missing from the
-- existing gyms_billing_guard column list, so a suspended/cancelled gym's
-- owner could self-reinstate via a plain client update. Verified live
-- (rolled-back transaction) against a real cancelled gym.
--
-- All legitimate writers (revenuecat-webhook, dodo webhook route) already
-- use the service-role client, so this is additive with no legitimate
-- authenticated-role caller to accommodate.
--
-- create or replace here also (re)establishes gyms_billing_guard itself for
-- environments where it only exists via a prior out-of-repo hotfix.
create or replace function block_owner_billing_edit()
returns trigger
language plpgsql
as $f$
begin
  if auth.role() <> 'service_role' and
     (new.plan is distinct from old.plan
      or new.plan_expires_at is distinct from old.plan_expires_at
      or new.trial_ends_at is distinct from old.trial_ends_at
      or new.dodo_subscription_id is distinct from old.dodo_subscription_id
      or new.dodo_customer_id is distinct from old.dodo_customer_id
      or new.apple_subscription_id is distinct from old.apple_subscription_id
      or new.plan_price is distinct from old.plan_price
      or new.status is distinct from old.status) then
    raise exception 'billing fields are server-managed';
  end if;
  return new;
end;
$f$;

create or replace trigger gyms_billing_guard
before update on public.gyms
for each row execute function block_owner_billing_edit();
