-- Same overload trap, found while auditing for it after change_member_plan /
-- record_invoice_payment: 20260823140000_multi_gym_audit_fixes.sql added
-- save_razorpay_keys(text, text, uuid default null) instead of replacing the
-- original save_razorpay_keys(text, text), leaving two overloads. The app
-- only ever calls with 2 args, which became ambiguous (PGRST203). Drop the
-- stray 2-arg original; the 3-arg version (already gym-widened) remains.
drop function if exists public.save_razorpay_keys(text, text);
