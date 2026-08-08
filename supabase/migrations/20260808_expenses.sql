create table expenses (
  id           uuid primary key default gen_random_uuid(),
  gym_id       uuid not null references gyms(id) on delete cascade,
  category     text not null,
  amount       numeric not null check (amount > 0),
  expense_date date not null,
  note         text,
  created_by   uuid references profiles(id),
  created_at   timestamptz not null default now()
);

alter table expenses enable row level security;

create policy "staff_view_expenses" on expenses
  for select to authenticated
  using (gym_id = auth_gym_id());

create policy "staff_add_expenses" on expenses
  for insert to authenticated
  with check (gym_id = auth_gym_id());

-- Delete restricted to owners — checked via profiles.role, not just gym match,
-- since auth_gym_id() alone can't express "and only if owner".
create policy "owner_delete_expenses" on expenses
  for delete to authenticated
  using (
    gym_id = auth_gym_id()
    and exists (select 1 from profiles where id = auth.uid() and role = 'owner')
  );

create index expenses_gym_id_idx on expenses(gym_id);
create index expenses_gym_date_idx on expenses(gym_id, expense_date desc);
