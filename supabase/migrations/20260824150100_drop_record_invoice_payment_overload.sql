-- Same overload trap as change_member_plan: 20260823130000_multi_gym_widen_rls.sql
-- added a trailing p_gym_id param to record_invoice_payment via create or
-- replace instead of matching the original 5-arg signature, leaving two
-- overloads. Any 5-arg call (all real app callers) became ambiguous —
-- PGRST203 / HTTP 300 — surfaced in the app as "Failed to add member" even
-- though the member/membership/invoice inserts before it had already
-- succeeded. Drop the stray 6-arg overload; the surviving 5-arg one is
-- fixed for multi-gym in 20260824150000.
drop function if exists public.record_invoice_payment(
  uuid, text, text, text, boolean, uuid
);
