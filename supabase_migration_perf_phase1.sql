-- Performance Phase 1 — safe, semantics-preserving, reversible.
-- Fixes Supabase performance advisors WITHOUT changing who can access what.
-- RLS stays fully enforced. No service-role bypass, no widened access.
--
-- What this does:
--   1. Adds 13 missing foreign-key indexes (purely additive).
--   2. Wraps raw auth.uid() as (select auth.uid()) so Postgres evaluates it
--      ONCE per query instead of once PER ROW. Identical check, faster plan.
--   3. Marks member_booked_class_ids() STABLE (stops per-row re-execution).
--   4. Drops two leads policies that are exact duplicates of the ALL policy.
--
-- Copy this into the web repo as supabase/migrations/<ts>_perf_phase1.sql too,
-- so app + website stay in sync (they share this database).

begin;

-- ── 1. Missing foreign-key indexes ─────────────────────────────────────────
create index if not exists idx_check_ins_session_id        on public.check_ins(session_id);
create index if not exists idx_check_ins_staff_id          on public.check_ins(staff_id);
create index if not exists idx_class_enrollments_member_id on public.class_enrollments(member_id);
create index if not exists idx_classes_instructor_id       on public.classes(instructor_id);
create index if not exists idx_documents_gym_id            on public.documents(gym_id);
create index if not exists idx_documents_member_id         on public.documents(member_id);
create index if not exists idx_gyms_owner_id               on public.gyms(owner_id);
create index if not exists idx_members_user_id             on public.members(user_id);
create index if not exists idx_membership_plans_gym_id     on public.membership_plans(gym_id);
create index if not exists idx_memberships_plan_id         on public.memberships(plan_id);
create index if not exists idx_payments_invoice_id         on public.payments(invoice_id);
create index if not exists idx_payments_recorded_by        on public.payments(recorded_by);
create index if not exists idx_workout_plans_member_id     on public.workout_plans(member_id);

-- ── 2. Wrap auth.uid() so it runs once per query, not per row ───────────────
-- Each ALTER POLICY below keeps the EXACT same condition; only auth.uid() is
-- wrapped in a scalar subquery. Verified against current policy definitions.

alter policy "owners_manage_gym" on public.gyms
  using (owner_id = (select auth.uid()));

alter policy "members_portal_read_own_uid" on public.members
  using (user_id = (select auth.uid()));

alter policy "gym_isolation_leads" on public.leads
  using (gym_id in (
    select profiles.gym_id from public.profiles
    where profiles.id = (select auth.uid())
  ));

alter policy "gym_isolation_class_enrollments" on public.class_enrollments
  using (class_id in (
    select classes.id from public.classes
    where classes.gym_id = (
      select profiles.gym_id from public.profiles
      where profiles.id = (select auth.uid())
    )
  ));

alter policy "members can update own invoices" on public.invoices
  using (member_id in (
    select members.id from public.members
    where members.user_id = (select auth.uid())
  ))
  with check (member_id in (
    select members.id from public.members
    where members.user_id = (select auth.uid())
  ));

alter policy "members can insert payment for own invoice" on public.payments
  with check (invoice_id in (
    select i.id from public.invoices i
    join public.members m on m.id = i.member_id
    where m.user_id = (select auth.uid())
  ));

alter policy "Users manage own push subscriptions" on public.push_subscriptions
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "members manage own workout plans" on public.workout_plans
  using (member_id = (
    select members.id from public.members
    where members.user_id = (select auth.uid())
  ))
  with check (member_id = (
    select members.id from public.members
    where members.user_id = (select auth.uid())
  ));

-- ── 3. STABLE function — stop per-row re-execution on the member portal ─────
alter function public.member_booked_class_ids() stable;

-- ── 4. Drop redundant duplicate policies on leads ──────────────────────────
-- gym_isolation_leads (cmd=ALL) already covers UPDATE and DELETE with the
-- identical USING expression, so these two add nothing but extra per-query
-- policy evaluation. Dropping them does not change access at all.
drop policy if exists "gym_isolation_leads_update" on public.leads;
drop policy if exists "gym_isolation_leads_delete" on public.leads;

commit;
