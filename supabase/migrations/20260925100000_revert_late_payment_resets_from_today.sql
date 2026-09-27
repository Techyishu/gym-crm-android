-- Revert 20260922130000_late_payment_resets_from_today.
--
-- That change based a late renewal's next due date on today instead of the
-- member's existing due date. Gyms reported problems with it, so go back to
-- advancing from the existing next_payment_date (the pre-22-Sep behaviour).
--
-- Edits the LIVE definitions in place and swaps only the two next-date
-- expressions, so any later change to these functions is kept. Each
-- expression was verified to appear exactly once before this ran.
-- CREATE OR REPLACE keeps existing grants.

do $$
declare
  v_def text;
begin
  v_def := pg_get_functiondef(
    'public.record_invoice_payment(uuid,text,text,text,boolean)'::regprocedure
  );
  if position('greatest(v_member.next_payment_date, current_date)' in v_def) = 0 then
    raise exception 'record_invoice_payment: expected expression not found';
  end if;
  execute replace(
    v_def,
    'greatest(v_member.next_payment_date, current_date)',
    'v_member.next_payment_date'
  );

  v_def := pg_get_functiondef(
    'public.collect_membership_renewal_atomic(uuid,date,numeric,text,text,text,uuid)'::regprocedure
  );
  if position('greatest(p_expected_next_payment_date, current_date)' in v_def) = 0 then
    raise exception 'collect_membership_renewal_atomic: expected expression not found';
  end if;
  execute replace(
    v_def,
    'greatest(p_expected_next_payment_date, current_date)',
    'p_expected_next_payment_date'
  );
end $$;
