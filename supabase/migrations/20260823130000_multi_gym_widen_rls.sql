-- Widen RLS + RPC authorization so a staff member can access ANY gym branch
-- they are linked to via staff_gym_access, not only their primary
-- profiles.gym_id. Every change below is a widening (gym_id = X becomes
-- gym_id = ANY(my_gyms)) - nobody who couldn't see a row before loses
-- access, and nobody gains access to a gym they aren't linked to.

-- ===== biometric_devices =====
alter policy "biometric_devices_staff_manage" on public.biometric_devices
  using ((gym_id = any (auth_gym_ids())) and exists (select 1 from profiles where profiles.id = auth.uid() and profiles.role = any (array['owner','manager'])))
  with check ((gym_id = any (auth_gym_ids())) and exists (select 1 from profiles where profiles.id = auth.uid() and profiles.role = any (array['owner','manager'])));

-- ===== bookings =====
alter policy "bookings_delete" on public.bookings
  using ((member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))) or (member_id = auth_member_id()));
alter policy "bookings_insert" on public.bookings
  with check ((member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))) or (member_id = auth_member_id()));
alter policy "bookings_select" on public.bookings
  using ((member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))) or (member_id = auth_member_id()));
alter policy "bookings_staff_update" on public.bookings
  using (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())))
  with check (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())));

-- ===== check_ins =====
alter policy "check_ins_delete" on public.check_ins using (gym_id = any (auth_gym_ids()));
alter policy "check_ins_insert" on public.check_ins with check (gym_id = any (auth_gym_ids()));
alter policy "check_ins_select" on public.check_ins using ((gym_id = any (auth_gym_ids())) or (member_id = auth_member_id()));
alter policy "check_ins_update" on public.check_ins using (gym_id = any (auth_gym_ids())) with check (gym_id = any (auth_gym_ids()));

-- ===== class_sessions =====
alter policy "class_sessions_staff_delete" on public.class_sessions
  using (class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids())));
alter policy "class_sessions_staff_insert" on public.class_sessions
  with check (class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids())));
alter policy "class_sessions_select" on public.class_sessions
  using ((class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids()))) or (id in (select bookings.session_id from bookings where bookings.member_id = auth_member_id())));
alter policy "class_sessions_staff_update" on public.class_sessions
  using (class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids())))
  with check (class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids())));

-- ===== classes =====
alter policy "classes_staff_delete" on public.classes using (gym_id = any (auth_gym_ids()));
alter policy "classes_staff_insert" on public.classes with check (gym_id = any (auth_gym_ids()));
alter policy "classes_select" on public.classes using ((gym_id = any (auth_gym_ids())) or (id in (select member_enrolled_class_ids())));
alter policy "classes_staff_update" on public.classes using (gym_id = any (auth_gym_ids())) with check (gym_id = any (auth_gym_ids()));

-- ===== class_enrollments (was inline profiles.gym_id subquery) =====
alter policy "gym_isolation_class_enrollments" on public.class_enrollments
  using (class_id in (select classes.id from classes where classes.gym_id = any (auth_gym_ids())));

-- ===== diet_plans (was inline profiles.gym_id subquery) =====
alter policy "staff_manage_diet_plans" on public.diet_plans
  using (gym_id = any (auth_gym_ids()));

-- ===== documents =====
alter policy "gym_isolation_documents" on public.documents using (gym_id = any (auth_gym_ids()));

-- ===== expenses =====
alter policy "owner_delete_expenses" on public.expenses
  using ((gym_id = any (auth_gym_ids())) and exists (select 1 from profiles where profiles.id = auth.uid() and profiles.role = 'owner'));
alter policy "staff_add_expenses" on public.expenses with check (gym_id = any (auth_gym_ids()));
alter policy "staff_view_expenses" on public.expenses using (gym_id = any (auth_gym_ids()));

-- ===== gyms (lets an owner list/see all their branches) =====
alter policy "gyms_select" on public.gyms using (id = any (auth_gym_ids()));

-- ===== invoices =====
alter policy "invoices_staff_delete" on public.invoices using (gym_id = any (auth_gym_ids()));
alter policy "invoices_staff_insert" on public.invoices with check (gym_id = any (auth_gym_ids()));
alter policy "invoices_select" on public.invoices using ((gym_id = any (auth_gym_ids())) or (member_id = auth_member_id()));
alter policy "invoices_update" on public.invoices
  using ((gym_id = any (auth_gym_ids())) or (member_id = auth_member_id()))
  with check ((gym_id = any (auth_gym_ids())) or (member_id = auth_member_id()));

-- ===== leads (was inline profiles.gym_id subquery) =====
alter policy "gym_isolation_leads" on public.leads using (gym_id = any (auth_gym_ids()));

-- ===== members =====
alter policy "members_delete" on public.members
  using ((gym_id = any (auth_gym_ids())) and ((select profiles.role from profiles where profiles.id = auth.uid()) = any (array['owner','manager'])));
alter policy "members_insert" on public.members
  with check ((gym_id = any (auth_gym_ids())) and ((select profiles.role from profiles where profiles.id = auth.uid()) = any (array['owner','manager'])));
alter policy "members_select" on public.members
  using ((gym_id = any (auth_gym_ids())) or (user_id = auth.uid()));
alter policy "members_update" on public.members
  using ((gym_id = any (auth_gym_ids())) and ((select profiles.role from profiles where profiles.id = auth.uid()) = any (array['owner','manager'])))
  with check ((gym_id = any (auth_gym_ids())) and ((select profiles.role from profiles where profiles.id = auth.uid()) = any (array['owner','manager'])));

-- ===== membership_plans =====
alter policy "membership_plans_staff_delete" on public.membership_plans using (gym_id = any (auth_gym_ids()));
alter policy "membership_plans_staff_insert" on public.membership_plans with check (gym_id = any (auth_gym_ids()));
alter policy "membership_plans_select" on public.membership_plans
  using ((gym_id = any (auth_gym_ids())) or (id in (select memberships.plan_id from memberships where memberships.member_id = auth_member_id())));
alter policy "membership_plans_staff_update" on public.membership_plans using (gym_id = any (auth_gym_ids())) with check (gym_id = any (auth_gym_ids()));

-- ===== memberships =====
alter policy "memberships_staff_delete" on public.memberships
  using (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())));
alter policy "memberships_staff_insert" on public.memberships
  with check (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())));
alter policy "memberships_select" on public.memberships
  using ((member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))) or (member_id = auth_member_id()));
alter policy "memberships_staff_update" on public.memberships
  using (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())))
  with check (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids())));

-- ===== notifications_log =====
alter policy "gym_isolation_notifications" on public.notifications_log using (gym_id = any (auth_gym_ids()));

-- ===== payments =====
alter policy "payments_staff_delete" on public.payments
  using (invoice_id in (select invoices.id from invoices where invoices.gym_id = any (auth_gym_ids())));
alter policy "payments_insert" on public.payments
  with check ((invoice_id in (select invoices.id from invoices where invoices.gym_id = any (auth_gym_ids()))) or (invoice_id in (select i.id from invoices i join members m on m.id = i.member_id where m.user_id = auth.uid())));
alter policy "payments_select" on public.payments
  using ((invoice_id in (select invoices.id from invoices where invoices.gym_id = any (auth_gym_ids()))) or (invoice_id in (select i.id from invoices i where i.member_id = auth_member_id())));
alter policy "payments_staff_update" on public.payments
  using (invoice_id in (select invoices.id from invoices where invoices.gym_id = any (auth_gym_ids())))
  with check (invoice_id in (select invoices.id from invoices where invoices.gym_id = any (auth_gym_ids())));

-- ===== profiles (owner/staff can see profiles across their linked branches) =====
alter policy "profiles_own_gym" on public.profiles using (gym_id = any (auth_gym_ids()));

-- ===== support_tickets =====
alter policy "Staff can create tickets for their own gym" on public.support_tickets with check (gym_id = any (auth_gym_ids()));
alter policy "Staff can view their own gym's tickets" on public.support_tickets using (gym_id = any (auth_gym_ids()));

-- ===== workout_plans =====
alter policy "workout_plans_delete" on public.workout_plans
  using ((member_id = auth_member_id()) or (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))));
alter policy "workout_plans_insert" on public.workout_plans
  with check ((member_id = auth_member_id()) or (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))));
alter policy "workout_plans_select" on public.workout_plans
  using ((member_id = auth_member_id()) or (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))));
alter policy "workout_plans_update" on public.workout_plans
  using ((member_id = auth_member_id()) or (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))))
  with check ((member_id = auth_member_id()) or (member_id in (select members.id from members where members.gym_id = any (auth_gym_ids()))));

-- ===== activity_events / error_logs (INSERT only, was inline profiles.gym_id) =====
alter policy "authenticated_insert_own_activity" on public.activity_events
  with check ((user_id = auth.uid()) or (gym_id = any (auth_gym_ids())));
alter policy "authenticated_insert_own_error" on public.error_logs
  with check ((user_id = auth.uid()) or (gym_id = any (auth_gym_ids())));

-- ===== RPCs: widen the target-gym check from "== my primary gym" to
-- "any gym I'm linked to" so check-in / reports / billing / plan-change
-- work on a secondary branch too. =====

create or replace function public.insert_checkin_secure(
  p_member_id uuid, p_gym_id uuid, p_method text default 'qr'::text,
  p_checked_in_at timestamp with time zone default now()
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_checked_in_at < now() - interval '24 hours' then
    raise exception 'checkin_too_old: timestamp must be within the last 24 hours';
  end if;
  if p_checked_in_at > now() + interval '5 minutes' then
    raise exception 'checkin_in_future: timestamp cannot be in the future';
  end if;

  if not (p_gym_id = any (auth_gym_ids())) then
    raise exception 'unauthorized: gym mismatch';
  end if;

  if not exists (select 1 from members where id = p_member_id and gym_id = p_gym_id) then
    raise exception 'member_not_in_gym';
  end if;

  insert into check_ins (member_id, gym_id, staff_id, method, checked_in_at)
  values (p_member_id, p_gym_id, auth.uid(), p_method, p_checked_in_at);
end;
$$;

create or replace function public.get_member_stats(p_gym_id uuid, p_lead_days integer default 30)
returns json
language plpgsql
stable security definer
set search_path to 'public'
as $$
declare
  v_result json;
begin
  if not (p_gym_id = any (auth_gym_ids())) then
    raise exception 'unauthorized: gym mismatch';
  end if;

  with mem as (
    select status, joined_at, billing_interval_months from public.members where gym_id = p_gym_id
  ),
  monthly as (
    select to_char(date_trunc('month', joined_at::timestamptz), 'YYYY-MM') as month_key, count(*) as cnt
    from mem where joined_at is not null and joined_at::timestamptz >= now() - interval '365 days'
    group by 1
  ),
  plan_agg as (
    select billing_interval_months, count(*) as cnt from mem
    where status = 'active' and billing_interval_months is not null
    group by billing_interval_months
  ),
  leads_window as (
    select status from public.leads where gym_id = p_gym_id and created_at >= now() - make_interval(days => p_lead_days)
  )
  select json_build_object(
    'total', (select count(*) from mem),
    'active', (select count(*) from mem where status = 'active'),
    'frozen', (select count(*) from mem where status = 'frozen'),
    'expired', (select count(*) from mem where status = 'expired'),
    'cancelled', (select count(*) from mem where status = 'cancelled'),
    'new_last_30d', (select count(*) from mem where joined_at is not null and joined_at::timestamptz >= now() - interval '30 days'),
    'avg_tenure_days', (select avg(extract(epoch from (now() - joined_at)) / 86400.0) from mem where status = 'active' and joined_at is not null),
    'growth_data', coalesce((select json_agg(json_build_object('key', month_key, 'count', cnt) order by month_key) from monthly), '[]'::json),
    'plan_mix', coalesce((select json_agg(json_build_object('months', billing_interval_months, 'count', cnt) order by cnt desc) from plan_agg), '[]'::json),
    'leads_total', (select count(*) from leads_window),
    'leads_trial', (select count(*) from leads_window where status = 'trial'),
    'leads_converted', (select count(*) from leads_window where status = 'converted')
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.change_member_plan(
  p_member_id uuid, p_plan_id uuid, p_starts_at timestamp with time zone,
  p_discount_amount numeric, p_next_payment_date date, p_billing_interval_months integer,
  p_gym_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_gym_id uuid;
begin
  -- p_gym_id omitted (old callers): fall back to the caller's primary gym, unchanged behaviour.
  v_gym_id := coalesce(p_gym_id, (select gym_id from profiles where id = auth.uid()));

  if v_gym_id is null or not (v_gym_id = any (auth_gym_ids())) then
    raise exception 'unauthorized: not staff';
  end if;

  if not exists (select 1 from members where id = p_member_id and gym_id = v_gym_id) then
    raise exception 'member_not_in_gym';
  end if;
  if not exists (select 1 from membership_plans where id = p_plan_id and gym_id = v_gym_id) then
    raise exception 'plan_not_in_gym';
  end if;

  update memberships set status = 'cancelled', cancelled_at = now()
  where member_id = p_member_id and status = 'active';

  insert into memberships (member_id, plan_id, status, starts_at, ends_at, discount_amount)
  values (p_member_id, p_plan_id, 'active', p_starts_at, null, coalesce(p_discount_amount, 0));

  update members
     set next_payment_date = p_next_payment_date,
         billing_interval_months = p_billing_interval_months,
         status = case when status in ('expired', 'cancelled') then 'active' else status end
   where id = p_member_id;
end;
$$;

create or replace function public.record_invoice_payment(
  p_invoice_id uuid, p_method text, p_reference_no text default null::text,
  p_notes text default null::text, p_advance_date boolean default true,
  p_gym_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid       uuid := auth.uid();
  v_gym_id    uuid;
  v_invoice   record;
  v_member    record;
  v_next_date date;
begin
  -- p_gym_id omitted (old callers): fall back to the caller's primary gym, unchanged behaviour.
  v_gym_id := coalesce(p_gym_id, (select gym_id from profiles where id = v_uid));

  if v_gym_id is null or not (v_gym_id = any (auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  select id, amount, status, member_id, gym_id into v_invoice
  from invoices where id = p_invoice_id and gym_id = v_gym_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Invoice not found');
  end if;
  if v_invoice.status = 'paid' then
    return jsonb_build_object('ok', false, 'error', 'Invoice already paid');
  end if;

  insert into payments (invoice_id, amount, method, status, reference_no, notes, recorded_by)
  values (v_invoice.id, v_invoice.amount, p_method, 'succeeded', p_reference_no, p_notes, v_uid);

  update invoices set status = 'paid', paid_at = now() where id = v_invoice.id;

  select next_payment_date, status into v_member
  from members where id = v_invoice.member_id and gym_id = v_gym_id;

  if p_advance_date and v_member.next_payment_date is not null then
    v_next_date := (v_member.next_payment_date + interval '1 month')::date;
  end if;

  update members
  set next_payment_date = coalesce(v_next_date, next_payment_date),
      status = case when status in ('frozen', 'expired') then 'active' else status end
  where id = v_invoice.member_id and gym_id = v_gym_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice.id);
end;
$$;
