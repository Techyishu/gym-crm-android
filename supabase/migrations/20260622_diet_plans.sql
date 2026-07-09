create table diet_plans (
  id          uuid primary key default gen_random_uuid(),
  gym_id      uuid not null references gyms(id) on delete cascade,
  member_id   uuid not null references members(id) on delete cascade,
  name        text not null,
  goal        text not null default 'general',
  calories    int,
  meals       jsonb not null default '[]',
  is_active   boolean not null default true,
  created_by  uuid references profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);

-- Auto-populate gym_id from the member row so Flutter doesn't need to pass it.
create or replace function _set_diet_plan_gym_id()
returns trigger language plpgsql security definer as $$
begin
  new.gym_id := (select gym_id from members where id = new.member_id);
  return new;
end;
$$;

create trigger diet_plans_set_gym_id
  before insert on diet_plans
  for each row execute function _set_diet_plan_gym_id();

alter table diet_plans enable row level security;

-- Staff in the same gym can do everything.
create policy "staff_manage_diet_plans" on diet_plans
  for all using (
    gym_id in (select gym_id from profiles where id = auth.uid())
  );

-- Members can only read their own plans.
create policy "member_read_diet_plans" on diet_plans
  for select using (
    member_id in (select id from members where user_id = auth.uid())
  );

create index diet_plans_member_id_idx on diet_plans(member_id);
create index diet_plans_gym_id_idx    on diet_plans(gym_id);
