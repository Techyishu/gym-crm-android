-- Atomic plan-change RPC. Replaces the old client-side
-- cancel-then-insert-then-update-member sequence, which could partially fail
-- (old plan cancelled but new plan never inserted) if the app was
-- interrupted mid-flow.
create or replace function public.change_member_plan(
  p_member_id uuid,
  p_plan_id uuid,
  p_starts_at timestamptz,
  p_discount_amount numeric,
  p_next_payment_date date,
  p_billing_interval_months int
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_staff_gym_id uuid;
begin
  select gym_id into v_staff_gym_id from profiles where id = auth.uid();

  if v_staff_gym_id is null then
    raise exception 'unauthorized: not staff';
  end if;

  if not exists (
    select 1 from members where id = p_member_id and gym_id = v_staff_gym_id
  ) then
    raise exception 'member_not_in_gym';
  end if;

  if not exists (
    select 1 from membership_plans where id = p_plan_id and gym_id = v_staff_gym_id
  ) then
    raise exception 'plan_not_in_gym';
  end if;

  update memberships
     set status = 'cancelled', cancelled_at = now()
   where member_id = p_member_id and status = 'active';

  insert into memberships (member_id, plan_id, status, starts_at, ends_at, discount_amount)
  values (p_member_id, p_plan_id, 'active', p_starts_at, null, coalesce(p_discount_amount, 0));

  update members
     set next_payment_date = p_next_payment_date,
         billing_interval_months = p_billing_interval_months,
         status = case when status in ('expired', 'cancelled') then 'active' else status end
   where id = p_member_id;
end;
$$;

grant execute on function public.change_member_plan(uuid, uuid, timestamptz, numeric, date, int) to authenticated;
