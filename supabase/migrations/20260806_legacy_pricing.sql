-- Grandfather pricing for gyms that were paying Pro before the price change.
-- legacy_pricing gates paywall display + checkout routing; legacy_dodo_product_id
-- lets the checkout endpoint resubscribe against the old ₹249/mo product directly
-- (no need to reconstruct "which product was ₹249" from a price number), even
-- after the gym cancels and dodo_subscription_id goes null.
alter table gyms add column legacy_pricing boolean not null default false;
alter table gyms add column legacy_dodo_product_id text;
alter table gyms add column price_locked_at timestamptz;

-- Backfill is a separate, owner-reviewed step — NOT run automatically here.
-- Dry-run first:
--
-- select id, name, plan, plan_price, dodo_subscription_id, apple_subscription_id,
--        plan_expires_at, trial_ends_at, status, is_demo, created_at
-- from gyms
-- where not coalesce(is_demo, false)
--   and plan = 'pro'
--   and (dodo_subscription_id is not null or apple_subscription_id is not null or plan_expires_at is not null)
-- order by created_at;
--
-- Review the output, cross off freebies/trials-marked-pro and internal test gyms,
-- then run against the final reviewed id list:
--
-- update gyms
-- set legacy_pricing = true,
--     legacy_dodo_product_id = '<old Pro ₹249/mo product id from Dodo dashboard>',
--     price_locked_at = now(),
--     plan_price = 249
-- where id in (/* paste reviewed ids here */);
--
-- insert into activity_events (gym_id, action, metadata)
-- select id, 'pricing_grandfathered', jsonb_build_object('price', 249, 'granted_by', 'manual_backfill_20260806')
-- from gyms
-- where id in (/* same reviewed ids */);
