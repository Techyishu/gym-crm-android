-- Expire members at IST midnight instead of UTC midnight.
-- Due date is the last valid day in IST: a member due 2026-07-03 stays active
-- through July 3 (IST) and is expired at 00:00 IST on July 4.

create or replace function public.expire_overdue_members()
returns integer
language plpgsql
security definer
as $$
declare
  updated_count integer;
begin
  update members
  set status = 'expired'
  where status = 'active'
    and next_payment_date is not null
    and next_payment_date < (now() at time zone 'Asia/Kolkata')::date;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

-- Reschedule the cron job from 00:00 UTC to 18:30 UTC (00:00 IST).
select cron.alter_job(
  job_id := (select jobid from cron.job where jobname = 'expire-overdue-members'),
  schedule := '30 18 * * *'
);
