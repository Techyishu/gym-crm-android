-- Guards members.status / next_payment_date / billing_interval_months / gym_id / user_id
-- from self-service edits. members_update RLS currently has no column or role
-- restriction; it's only safe today because auth_gym_id() resolves to NULL for
-- non-staff sessions. Once members get their own login, that accident goes away.
-- Mirrors gyms_billing_guard's pattern but stays role-aware (owner/manager),
-- since staff legitimately write these columns directly today.

create or replace function block_member_self_billing_edit()
returns trigger
language plpgsql
as $$
begin
  if auth.role() <> 'service_role'
     and (new.status is distinct from old.status
          or new.next_payment_date is distinct from old.next_payment_date
          or new.billing_interval_months is distinct from old.billing_interval_months
          or new.gym_id is distinct from old.gym_id
          or new.user_id is distinct from old.user_id)
     and not exists (
       select 1 from public.profiles
       where id = auth.uid()
         and gym_id = old.gym_id
         and role in ('owner', 'manager')
     ) then
    raise exception 'membership status/billing fields are staff-managed';
  end if;
  return new;
end;
$$;

create trigger members_billing_guard
before update on public.members
for each row execute function block_member_self_billing_edit();
