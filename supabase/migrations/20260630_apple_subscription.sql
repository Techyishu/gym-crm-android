-- Stores the RevenueCat app_user_id (= Supabase user ID) for the iOS subscriber.
-- Used to correlate RC webhook events back to a gym row.
alter table gyms
  add column if not exists apple_subscription_id text;
