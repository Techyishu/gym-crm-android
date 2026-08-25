-- One device row per gym (matches the settings sheet's single-row assumption).
-- Prevents a race in the app's pairing flow from creating a duplicate row,
-- which would break `.maybeSingle()` on every future load for that gym.
alter table public.biometric_devices
  add constraint biometric_devices_gym_id_unique unique (gym_id);
