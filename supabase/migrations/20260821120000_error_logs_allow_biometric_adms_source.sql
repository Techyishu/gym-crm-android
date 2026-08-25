-- error_logs.source was scoped to client platforms only (web/android/ios).
-- The biometric-adms edge function now writes failures here too, so a
-- device-side error is visible without digging through function logs.
alter table public.error_logs drop constraint error_logs_source_check;
alter table public.error_logs
  add constraint error_logs_source_check
  check (source = any (array['web', 'android', 'ios', 'biometric-adms']));
