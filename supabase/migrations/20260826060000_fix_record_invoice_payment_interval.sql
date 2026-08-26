-- record_invoice_payment (the pre-atomic RPC, kept alive only for app
-- installs that haven't updated yet — see collect_membership_renewal_atomic
-- for the current path) always advanced next_payment_date by a hardcoded
-- +1 month, regardless of the member's actual billing interval. Correct for
-- monthly plans, wrong for quarterly/biannual/annual: those members kept
-- getting rebilled every month instead of every 3/6/12. Same interval
-- derivation as collect_membership_renewal_atomic, so both paths agree.
create or replace function public.record_invoice_payment(
  p_invoice_id uuid,
  p_method text,
  p_reference_no text default null,
  p_notes text default null,
  p_advance_date boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid       uuid := auth.uid();
  v_invoice   record;
  v_member    record;
  v_interval_months integer;
  v_next_date date;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  select id, amount, status, member_id, gym_id into v_invoice
  from invoices
  where id = p_invoice_id;

  if not found or v_invoice.gym_id is null or not (v_invoice.gym_id = any (auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Invoice not found');
  end if;
  if v_invoice.status = 'paid' then
    return jsonb_build_object('ok', false, 'error', 'Invoice already paid');
  end if;

  insert into payments (invoice_id, amount, method, status, reference_no, notes, recorded_by)
  values (v_invoice.id, v_invoice.amount, p_method, 'succeeded', p_reference_no, p_notes, v_uid);

  update invoices set status = 'paid', paid_at = now() where id = v_invoice.id;

  select next_payment_date, status, billing_interval_months into v_member
  from members where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  select coalesce(
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
    into v_interval_months
  from memberships ms
  join membership_plans mp on mp.id = ms.plan_id
  where ms.member_id = v_invoice.member_id
    and ms.status = 'active'
    and mp.gym_id = v_invoice.gym_id
  order by ms.starts_at desc nulls last
  limit 1;

  v_interval_months := coalesce(v_interval_months, v_member.billing_interval_months, 1);

  if p_advance_date and v_member.next_payment_date is not null then
    v_next_date := (v_member.next_payment_date + make_interval(months => v_interval_months))::date;
  end if;

  update members
  set next_payment_date = coalesce(v_next_date, next_payment_date),
      billing_interval_months = v_interval_months,
      status = case when status in ('frozen', 'expired') then 'active' else status end
  where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice.id);
end;
$$;
