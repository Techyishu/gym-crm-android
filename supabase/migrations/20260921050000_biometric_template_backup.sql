-- Backup of what biometric devices send on enrollment, so a member can later be
-- removed from a device (expiry) and re-added (renewal) without re-scanning.
-- Fingerprint templates are biometric personal data: RLS is on with no policies
-- and all client grants are revoked, so only the service role (the bridge) can
-- read or write these tables.

create table public.biometric_users (
  gym_id     uuid not null references public.gyms(id) on delete cascade,
  pin        text not null,
  name       text,
  raw        text not null,
  updated_at timestamptz not null default now(),
  primary key (gym_id, pin)
);

create table public.biometric_templates (
  gym_id     uuid not null references public.gyms(id) on delete cascade,
  pin        text not null,
  fid        text not null,
  size       integer,
  valid      integer,
  template   text not null,
  updated_at timestamptz not null default now(),
  primary key (gym_id, pin, fid)
);

alter table public.biometric_users enable row level security;
alter table public.biometric_templates enable row level security;
revoke all on public.biometric_users from anon, authenticated;
revoke all on public.biometric_templates from anon, authenticated;

comment on table public.biometric_users is
  'Raw USER record each device pushed on enrollment (pin, name, full line to replay). Service role only.';
comment on table public.biometric_templates is
  'Fingerprint templates (base64) each device pushed on enrollment. Biometric data - service role only.';
