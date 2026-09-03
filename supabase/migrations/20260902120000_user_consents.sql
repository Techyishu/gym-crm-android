-- DPDP Act 2023: consent has to survive the device it was given on.
--
-- Before this, consent lived only in SharedPreferences. Two consequences,
-- both wrong:
--   1. A reinstall or a second device re-prompted someone who had already
--      consented.
--   2. On a shared front-desk device, the first person's consent silently
--      covered every user who logged in after them — which is not consent.
--
-- Keyed by auth user id, so it follows the person, not the hardware. Covers
-- staff and members alike; both are auth.users.
create table if not exists public.user_consents (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- Matches kConsentVersion in lib/features/legal/consent_screen.dart. Bump
  -- both together after a material change to what we collect; the mismatch is
  -- what re-prompts everyone.
  version text not null,
  analytics boolean not null default false,
  marketing boolean not null default false,
  ads boolean not null default false,
  -- First time this user ever consented, kept across later edits.
  granted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ponytail: one row per user, last-write-wins. Enough to prove current
-- consent and its timestamp. If a regulator ever asks for the full history of
-- changes, add an append-only user_consent_events table alongside this — do
-- not try to reconstruct it from updated_at.

alter table public.user_consents enable row level security;

-- (select auth.uid()) rather than a bare call: it lets Postgres hoist this to
-- an initplan instead of re-evaluating per row, same as the rest of our RLS.
create policy "own consent read" on public.user_consents
  for select using ((select auth.uid()) = user_id);

create policy "own consent insert" on public.user_consents
  for insert with check ((select auth.uid()) = user_id);

create policy "own consent update" on public.user_consents
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
