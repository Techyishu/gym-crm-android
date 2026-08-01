-- Backfill members.next_payment_date for members who have an active
-- membership plan + joined_at but were never given a next_payment_date
-- (plan assigned without ever setting/collecting a payment date). Without
-- this they never appear in upcoming-payments or the WhatsApp/push
-- reminder jobs, which both key off next_payment_date only.
--
-- Formula mirrors the app-side advancePaymentDate() helper: joined_at +
-- the plan's billing_interval_months. Postgres date + interval already
-- clamps day-of-month overflow (31 Jan + 1 month -> 28/29 Feb), same as
-- the Dart implementation.
update members m
set next_payment_date = (m.joined_at::date + (ms.billing_interval_months || ' months')::interval)::date,
    billing_interval_months = ms.billing_interval_months
from (
  select distinct on (memberships.member_id)
    memberships.member_id,
    coalesce(membership_plans.billing_interval_months, 1) as billing_interval_months
  from memberships
  join membership_plans on membership_plans.id = memberships.plan_id
  where memberships.status = 'active'
  order by memberships.member_id, memberships.starts_at desc
) ms
where m.id = ms.member_id
  and m.next_payment_date is null
  and m.joined_at is not null
  and m.status <> 'cancelled';
