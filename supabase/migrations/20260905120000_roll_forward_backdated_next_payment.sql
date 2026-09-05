-- Backdated joining date no longer lands a brand-new member on "expired".
--
-- The apps compute next_payment_date as joined_at + one billing interval and
-- send that in the insert. Backdate the joining date by more than one cycle
-- (a member who actually joined in April, added to the CRM in September) and
-- that date is already in the past, so the member is saved expired and staff
-- have to record a catch-up payment per cycle to crawl forward.
--
-- Fixed here rather than in the clients so mobile (Android + iOS), web and CSV
-- import are all corrected at once, with no app release. The client-side
-- calculation stays as-is; this only corrects it on the way in.
--
-- INSERT only. An existing member whose date has genuinely lapsed is really
-- overdue and must keep showing as such, so updates are untouched.

create or replace function public.roll_forward_backdated_next_payment()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_interval int := greatest(coalesce(new.billing_interval_months, 1), 1);
  v_guard    int := 0;
begin
  if new.next_payment_date is null or new.next_payment_date >= current_date then
    return new;
  end if;

  -- Advance whole cycles until the date is in the future, so the day-of-month
  -- the gym bills on is preserved (Apr 1 -> May 1 -> ... -> Oct 1).
  -- Guard caps the loop at 1200 cycles (100 years monthly) — a junk date from
  -- a bad CSV must not spin here.
  while new.next_payment_date < current_date and v_guard < 1200 loop
    new.next_payment_date := new.next_payment_date + (v_interval || ' months')::interval;
    v_guard := v_guard + 1;
  end loop;

  -- Only lift the status the past date caused. A member deliberately added as
  -- frozen / blocked / cancelled keeps that status.
  if new.status = 'expired' then
    new.status := 'active';
  end if;

  return new;
end;
$$;

drop trigger if exists members_roll_forward_next_payment on public.members;

create trigger members_roll_forward_next_payment
  before insert on public.members
  for each row
  execute function public.roll_forward_backdated_next_payment();
