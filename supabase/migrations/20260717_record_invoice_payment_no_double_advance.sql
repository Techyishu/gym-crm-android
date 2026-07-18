-- record_invoice_payment always advanced members.next_payment_date by +1 month,
-- correct for renewals (due date is today/overdue) but wrong for the add-member
-- "paid today" flow, where next_payment_date is already the staff-chosen future
-- due date and shouldn't be advanced again. Add an opt-out flag, default true
-- to preserve existing renewal behavior.
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
as $function$
declare
  v_uid       uuid := auth.uid();
  v_gym_id    uuid;
  v_invoice   record;
  v_member    record;
  v_next_date date;
begin
  select gym_id into v_gym_id from profiles where id = v_uid;
  if v_gym_id is null then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  select id, amount, status, member_id, gym_id into v_invoice
  from invoices
  where id = p_invoice_id and gym_id = v_gym_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Invoice not found');
  end if;
  if v_invoice.status = 'paid' then
    return jsonb_build_object('ok', false, 'error', 'Invoice already paid');
  end if;

  insert into payments (invoice_id, amount, method, status, reference_no, notes, recorded_by)
  values (v_invoice.id, v_invoice.amount, p_method, 'succeeded', p_reference_no, p_notes, v_uid);

  update invoices set status = 'paid', paid_at = now() where id = v_invoice.id;

  select next_payment_date, status into v_member
  from members
  where id = v_invoice.member_id and gym_id = v_gym_id;

  if p_advance_date and v_member.next_payment_date is not null then
    -- Advance by one calendar month, clamped to the month's last day.
    -- Matches the existing web record-payment behavior.
    v_next_date := (v_member.next_payment_date + interval '1 month')::date;
  end if;

  update members
  set next_payment_date = coalesce(v_next_date, next_payment_date),
      status = case when status in ('frozen', 'expired') then 'active' else status end
  where id = v_invoice.member_id and gym_id = v_gym_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice.id);
end;
$function$;
