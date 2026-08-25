-- change_member_plan was missed by the multi-gym-branch audit pass: it still
-- hard-checked the caller's PRIMARY gym (profiles.gym_id) instead of any gym
-- the caller has access to (auth_gym_ids()), so assigning/changing a plan for
-- a member at a non-primary branch failed with member_not_in_gym /
-- plan_not_in_gym. Widen it to match checkout_member / save_razorpay_keys.
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
  v_member_gym_id uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized: not staff';
  end if;

  select gym_id into v_member_gym_id from members where id = p_member_id;

  if v_member_gym_id is null or not (v_member_gym_id = any (auth_gym_ids())) then
    raise exception 'member_not_in_gym';
  end if;

  if not exists (
    select 1 from membership_plans where id = p_plan_id and gym_id = v_member_gym_id
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
