-- 20260823130000_multi_gym_widen_rls.sql added a SECOND change_member_plan
-- overload (7 args, trailing p_gym_id uuid default null) instead of
-- replacing the original 6-arg one. With both present, PostgREST can't pick
-- an overload for a 6-arg call (ambiguous — p_gym_id has a default) and
-- returns PGRST203 (HTTP 300), which the app surfaces as "Failed to assign
-- plan". The app only ever calls the 6-arg form. Drop the 7-arg overload so
-- only the single, already-fixed (20260824120000) function remains.
drop function if exists public.change_member_plan(
  uuid, uuid, timestamptz, numeric, date, int, uuid
);
