-- Why gyms cancel, and whether the save offer worked.
--
-- One row per decision in the in-app cancel flow (gym-crm
-- app/api/billing/mobile/subscription/route.ts):
--   outcome 'cancelled'   — scheduled to cancel at the end of the period
--   outcome 'free_month'  — accepted the free month instead (once per gym)
--   outcome 'undone'      — took back a scheduled cancellation
-- Written by the server with the service role only; no client access.

create table public.cancellation_feedback (
  id         uuid primary key default gen_random_uuid(),
  gym_id     uuid not null references public.gyms (id) on delete cascade,
  reason     text check (reason in ('too_expensive', 'not_using', 'missing_feature', 'switching', 'closing_gym', 'other')),
  note       text check (length(note) <= 500),
  outcome    text not null check (outcome in ('cancelled', 'free_month', 'undone')),
  created_at timestamptz not null default now()
);

create index cancellation_feedback_gym_idx on public.cancellation_feedback (gym_id, created_at desc);

alter table public.cancellation_feedback enable row level security;
