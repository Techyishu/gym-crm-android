-- New biometric devices should get auto_sync on by default, matching the
-- decision to enable it fleet-wide rather than per-device manually.
alter table public.biometric_devices alter column auto_sync set default true;
