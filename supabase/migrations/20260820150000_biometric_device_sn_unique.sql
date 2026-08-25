-- Serial-number pairing: one physical device can only be claimed by one gym.
create unique index if not exists biometric_devices_device_sn_unique
  on public.biometric_devices (device_sn)
  where device_sn is not null;
