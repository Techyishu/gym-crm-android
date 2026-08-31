-- collect_membership_renewal_atomic used to hard-fail with "No active
-- membership plan found" whenever a member had no linked membership row —
-- a state ~800 legacy members across ~40 gyms are in (created before Add
-- Member required picking a plan). That left staff stuck mid-collection
-- with no way to record the payment.
--
-- Now: when no active plan is found, fall back to the amount the staff
-- typed in (p_amount) as the invoice total instead of erroring — same
-- graceful behavior the other Collect screen already has when a member
-- has no plan. Renewal still advances using the member's own
-- billing_interval_months (or 1 month if that's also missing).
create or replace function public.collect_membership_renewal_atomic(
  p_member_id uuid,
  p_expected_next_payment_date date,
  p_amount numeric,
  p_method text,
  p_reference_no text default null,
  p_notes text default null,
  p_invoice_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member public.members%rowtype;
  v_invoice public.invoices%rowtype;
  v_plan_name text;
  v_plan_price numeric;
  v_discount numeric;
  v_interval_months integer;
  v_invoice_amount numeric;
  v_paid numeric;
  v_remaining numeric;
  v_fully_paid boolean;
  v_next_date date;
  v_has_plan boolean;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('owner', 'manager', 'staff')
      and gym_id = any (public.auth_gym_ids())
  ) then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  if p_expected_next_payment_date is null then
    return jsonb_build_object('ok', false, 'error', 'The renewal date is missing. Refresh and try again.');
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Payment amount must be greater than zero');
  end if;

  select * into v_member
  from public.members
  where id = p_member_id
  for update;

  if not found or not (v_member.gym_id = any (public.auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Member not found');
  end if;

  if v_member.next_payment_date is distinct from p_expected_next_payment_date then
    return jsonb_build_object(
      'ok', false,
      'stale', true,
      'error', 'This renewal was already collected or changed. Refreshing the list.'
    );
  end if;

  select mp.name,
         mp.price,
         coalesce(ms.discount_amount, 0),
         coalesce(
           mp.billing_interval_months,
           case lower(mp.billing_interval)
             when 'monthly' then 1
             when 'quarterly' then 3
             when 'biannual' then 6
             when 'annual' then 12
           end,
           v_member.billing_interval_months,
           1
         )
    into v_plan_name, v_plan_price, v_discount, v_interval_months
  from public.memberships ms
  join public.membership_plans mp on mp.id = ms.plan_id
  where ms.member_id = v_member.id
    and ms.status = 'active'
    and mp.gym_id = v_member.gym_id
  order by ms.starts_at desc nulls last
  limit 1;

  v_has_plan := found;
  if not v_has_plan then
    -- No linked plan (legacy member) — bill exactly what staff entered.
    v_plan_name := 'Membership fee';
    v_plan_price := p_amount;
    v_discount := 0;
    v_interval_months := coalesce(v_member.billing_interval_months, 1);
  end if;

  v_invoice_amount := greatest(v_plan_price - v_discount, 0);
  if v_invoice_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'The membership plan has no collectible balance');
  end if;

  select * into v_invoice
  from public.invoices
  where member_id = v_member.id
    and gym_id = v_member.gym_id
    and status in ('open', 'partial')
    and (p_invoice_id is null or id = p_invoice_id)
  order by created_at asc
  limit 1
  for update;

  if not found and p_invoice_id is not null then
    return jsonb_build_object('ok', false, 'stale', true, 'error', 'This invoice is already paid or changed. Refreshing the list.');
  elsif not found then
    insert into public.invoices (
      gym_id, member_id, amount, original_amount, discount_amount,
      description, due_at, status
    ) values (
      v_member.gym_id, v_member.id, v_invoice_amount, v_plan_price, v_discount,
      v_plan_name || ' — membership fee', p_expected_next_payment_date, 'open'
    )
    returning * into v_invoice;
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where invoice_id = v_invoice.id
    and status = 'succeeded';

  v_remaining := v_invoice.amount - v_paid;
  if v_remaining <= 0 then
    return jsonb_build_object('ok', false, 'stale', true, 'error', 'This invoice is already paid. Refreshing the list.');
  end if;
  if p_amount > v_remaining then
    return jsonb_build_object('ok', false, 'error', 'Payment exceeds the remaining invoice balance');
  end if;

  insert into public.payments (
    invoice_id, amount, method, status, reference_no, notes, recorded_by
  ) values (
    v_invoice.id, p_amount, p_method, 'succeeded', p_reference_no, p_notes, auth.uid()
  );

  v_fully_paid := p_amount = v_remaining;
  update public.invoices
  set status = case when v_fully_paid then 'paid' else 'partial' end,
      paid_at = case when v_fully_paid then now() else paid_at end
  where id = v_invoice.id;

  if v_fully_paid then
    v_next_date := (p_expected_next_payment_date + make_interval(months => v_interval_months))::date;
    update public.members
    set next_payment_date = v_next_date,
        billing_interval_months = v_interval_months,
        status = case when status in ('frozen', 'expired') then 'active' else status end
    where id = v_member.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'is_fully_paid', v_fully_paid,
    'invoice_id', v_invoice.id,
    'next_payment_date', case when v_fully_paid then v_next_date else p_expected_next_payment_date end
  );
end;
$$;

revoke all on function public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid) from public;
revoke all on function public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid) from anon;
grant execute on function public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid) to authenticated;
