-- record_invoice_payment had the same two bugs as change_member_plan:
-- 1) 20260823130000_multi_gym_widen_rls.sql added a trailing p_gym_id param
--    via create or replace instead of replacing the original 5-arg function,
--    leaving two overloads and making any 5-arg call ambiguous (PGRST203 /
--    HTTP 300) — dropped separately in this pass.
-- 2) The surviving 5-arg body still derived gym from the caller's PRIMARY gym
--    (profiles.gym_id) rather than the invoice's actual gym, so recording a
--    payment for a member at a non-primary branch failed with "Invoice not
--    found". Fixed here to derive gym from the invoice row itself and check
--    it via auth_gym_ids(), matching checkout_member / change_member_plan.
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

  select next_payment_date, status into v_member
  from members where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  if p_advance_date and v_member.next_payment_date is not null then
    v_next_date := (v_member.next_payment_date + interval '1 month')::date;
  end if;

  update members
  set next_payment_date = coalesce(v_next_date, next_payment_date),
      status = case when status in ('frozen', 'expired') then 'active' else status end
  where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice.id);
end;
$$;
