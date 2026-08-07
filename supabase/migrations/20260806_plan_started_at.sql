-- Track when a gym's plan became 'pro', so "started today" is queryable.
-- Pure trigger, no application code touches this — fires under dodo webhook,
-- revenuecat webhook, and manual admin plan assignment alike.

alter table public.gyms add column if not exists plan_started_at timestamptz;

create or replace function public.set_plan_started_at()
returns trigger
language plpgsql
as $$
begin
  if new.plan = 'pro' and (old.plan is distinct from 'pro') then
    new.plan_started_at := now();
  elsif new.plan is distinct from 'pro' and old.plan = 'pro' then
    new.plan_started_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_plan_started_at on public.gyms;
create trigger trg_set_plan_started_at
  before update of plan on public.gyms
  for each row
  execute function public.set_plan_started_at();
