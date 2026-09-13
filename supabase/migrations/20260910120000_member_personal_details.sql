-- Personal details gyms ask for at the desk: date of birth (drives the
-- dashboard's birthday list), blood group and an emergency contact for
-- injuries on the floor, and a second number for members whose primary is a
-- parent's or spouse's phone.
--
-- Deliberately NOT stored: father's/mother's name. It is a KYC-style identity
-- answer with no gym use, and next to name + DOB + phone it turns this table
-- into an identity-theft bundle. Emergency contact serves the real need.
alter table public.members
  add column if not exists dob date,
  add column if not exists blood_group text,
  add column if not exists emergency_contact_name text,
  add column if not exists emergency_contact_phone text,
  add column if not exists phone_alt text;

comment on column public.members.dob is 'Date of birth. Year is stored but the dashboard birthday list matches on month+day only.';
comment on column public.members.blood_group is 'Health data under DPDP: collected for emergencies, optional, never required.';
comment on column public.members.emergency_contact_phone is 'Stored with country code, same normalisation as members.phone.';
comment on column public.members.phone_alt is 'Secondary contact. May belong to a relative who has not consented to marketing — reminders and emergencies only.';

-- Birthday lookups scan one gym at a time and compare month+day, so the plain
-- (gym_id, dob) index is enough at gym scale; an expression index on
-- extract(month/day) would only pay off across gyms.
create index if not exists members_gym_dob_idx
  on public.members (gym_id, dob)
  where dob is not null;
