-- Coach marks (guided tour tooltips): DB-controlled, one-time-per-user spotlight tour.
create table coachmark_config (
  key text primary key,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table user_coachmarks_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  coachmark_key text not null,
  seen_at timestamptz not null default now(),
  primary key (user_id, coachmark_key)
);

alter table coachmark_config enable row level security;
alter table user_coachmarks_seen enable row level security;

create policy "coachmark_config readable by authenticated" on coachmark_config
  for select to authenticated using (true);

create policy "users manage own seen rows" on user_coachmarks_seen
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

insert into coachmark_config (key) values
  ('staff_nav_members'), ('staff_nav_checkin'), ('staff_nav_more');

-- Backfill: existing staff already know the app, don't show them the new tour.
insert into user_coachmarks_seen (user_id, coachmark_key)
select p.id, k.key
from profiles p
cross join (values ('staff_nav_members'), ('staff_nav_checkin'), ('staff_nav_more')) as k(key)
on conflict do nothing;
