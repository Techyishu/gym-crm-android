-- Maps a verified phone number to a Supabase auth user, so mobile OTP login
-- (verify-phone-otp edge function) can find-or-create the right account
-- instead of creating a duplicate auth user on every login. Written only by
-- the edge function via the service-role key, never by client code, so RLS
-- is enabled with no policies (deny-all to anon/authenticated).
create table if not exists public.phone_identities (
  phone text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists phone_identities_user_id_idx on public.phone_identities(user_id);

alter table public.phone_identities enable row level security;
