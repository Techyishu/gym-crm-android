-- Secure export preparation/finalization and manual back-dated attendance.
-- QR/self-check-in/offline RPC signatures and their 24-hour queue behavior are
-- intentionally unchanged.

alter table public.check_ins
  add column manual_reason text,
  add column is_manual_adjustment boolean not null default false,
  add column modified_by uuid references public.profiles(id) on delete set null,
  add column modified_at timestamptz;

create index check_ins_member_local_day_idx
  on public.check_ins (member_id, ((checked_in_at at time zone 'Asia/Kolkata')::date));

create or replace function public.get_attendance_calendar(
  p_gym_id uuid,
  p_month date,
  p_member_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start date := date_trunc('month', coalesce(p_month, current_date))::date;
  v_end date := (date_trunc('month', coalesce(p_month, current_date)) + interval '1 month')::date;
  v_rows jsonb;
begin
  if not private.has_gym_permission(p_gym_id, 'attendance', 'view') then
    raise exception 'permission_denied';
  end if;
  if p_member_id is not null and not exists (
    select 1 from public.members m where m.id = p_member_id and m.gym_id = p_gym_id
  ) then raise exception 'member_not_in_gym'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'member_id', c.member_id,
    'member_name', trim(m.first_name || ' ' || coalesce(m.last_name, '')),
    'member_status', m.status,
    'date', (c.checked_in_at at time zone 'Asia/Kolkata')::date,
    'checked_in_at', c.checked_in_at,
    'checked_out_at', c.checked_out_at,
    'method', c.method,
    'is_manual_adjustment', c.is_manual_adjustment,
    'manual_reason', c.manual_reason,
    'modified_by', c.modified_by,
    'modified_at', c.modified_at
  ) order by c.checked_in_at), '[]'::jsonb)
  into v_rows
  from public.check_ins c
  join public.members m on m.id = c.member_id
  where c.gym_id = p_gym_id
    and (c.checked_in_at at time zone 'Asia/Kolkata')::date >= v_start
    and (c.checked_in_at at time zone 'Asia/Kolkata')::date < v_end
    and (p_member_id is null or c.member_id = p_member_id);

  return jsonb_build_object(
    'month', v_start,
    'records', v_rows,
    'permissions', jsonb_build_object(
      'add', private.has_gym_permission(p_gym_id, 'attendance', 'add'),
      'edit', private.has_gym_permission(p_gym_id, 'attendance', 'edit'),
      'delete', private.has_gym_permission(p_gym_id, 'attendance', 'delete')
    )
  );
end;
$$;

revoke all on function public.get_attendance_calendar(uuid, date, uuid) from public, anon;
grant execute on function public.get_attendance_calendar(uuid, date, uuid) to authenticated;

create or replace function public.upsert_manual_attendance(
  p_gym_id uuid,
  p_member_id uuid,
  p_attendance_date date,
  p_check_in_time time default '06:00',
  p_check_out_time time default null,
  p_reason text default null,
  p_check_in_id uuid default null
) returns public.check_ins
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_checked_in_at timestamptz;
  v_checked_out_at timestamptz;
  v_row public.check_ins%rowtype;
  v_action text := case when p_check_in_id is null then 'add' else 'edit' end;
begin
  if not private.has_gym_permission(p_gym_id, 'attendance', v_action) then
    raise exception 'permission_denied';
  end if;
  if not exists (
    select 1 from public.members m where m.id = p_member_id and m.gym_id = p_gym_id
  ) then raise exception 'member_not_in_gym'; end if;
  if p_attendance_date is null or p_attendance_date > v_today then
    raise exception 'attendance_date_cannot_be_in_future';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'attendance_reason_required';
  end if;

  v_checked_in_at := (p_attendance_date + coalesce(p_check_in_time, time '06:00')) at time zone 'Asia/Kolkata';
  if p_check_out_time is not null then
    v_checked_out_at := (p_attendance_date + p_check_out_time) at time zone 'Asia/Kolkata';
  elsif p_attendance_date < v_today then
    -- A historical presence record must not remain an open live session.
    v_checked_out_at := v_checked_in_at;
  end if;
  if v_checked_out_at is not null and v_checked_out_at < v_checked_in_at then
    raise exception 'checkout_before_checkin';
  end if;

  if exists (
    select 1 from public.check_ins c
    where c.gym_id = p_gym_id
      and c.member_id = p_member_id
      and (c.checked_in_at at time zone 'Asia/Kolkata')::date = p_attendance_date
      and (p_check_in_id is null or c.id <> p_check_in_id)
  ) then raise exception 'attendance_already_exists_for_date'; end if;

  perform set_config('gymcrm.audit_reason', trim(p_reason), true);
  if p_check_in_id is null then
    insert into public.check_ins (
      member_id, gym_id, checked_in_at, checked_out_at, method, staff_id,
      manual_reason, is_manual_adjustment, modified_by, modified_at
    ) values (
      p_member_id, p_gym_id, v_checked_in_at, v_checked_out_at,
      'manual_backdated', auth.uid(), trim(p_reason), true, auth.uid(), now()
    ) returning * into v_row;
  else
    update public.check_ins c set
      member_id = p_member_id,
      checked_in_at = v_checked_in_at,
      checked_out_at = v_checked_out_at,
      manual_reason = trim(p_reason),
      is_manual_adjustment = true,
      modified_by = auth.uid(),
      modified_at = now()
    where c.id = p_check_in_id and c.gym_id = p_gym_id
    returning * into v_row;
    if not found then raise exception 'attendance_not_found'; end if;
  end if;
  return v_row;
end;
$$;

revoke all on function public.upsert_manual_attendance(uuid, uuid, date, time, time, text, uuid)
  from public, anon;
grant execute on function public.upsert_manual_attendance(uuid, uuid, date, time, time, text, uuid)
  to authenticated;

create or replace function public.delete_manual_attendance(
  p_gym_id uuid,
  p_check_in_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.has_gym_permission(p_gym_id, 'attendance', 'delete') then
    raise exception 'permission_denied';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'attendance_reason_required';
  end if;
  perform set_config('gymcrm.audit_reason', trim(p_reason), true);
  delete from public.check_ins c where c.id = p_check_in_id and c.gym_id = p_gym_id;
  if not found then raise exception 'attendance_not_found'; end if;
end;
$$;

revoke all on function public.delete_manual_attendance(uuid, uuid, text) from public, anon;
grant execute on function public.delete_manual_attendance(uuid, uuid, text) to authenticated;

-- Export jobs bind a server-computed result shape/filter/count to the actor.
-- The completion call can therefore not forge what was exported.
create table private.data_export_jobs (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  actor_id uuid not null,
  export_type text not null check (export_type in (
    'members', 'payments', 'dues', 'attendance', 'leads', 'expenses', 'activity_logs'
  )),
  filters jsonb not null,
  row_count integer not null check (row_count >= 0),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
revoke all on table private.data_export_jobs from public, anon, authenticated;
create index data_export_jobs_actor_created_idx
  on private.data_export_jobs (actor_id, created_at desc);

create or replace function private.export_module(p_export_type text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case p_export_type
    when 'members' then 'members'
    when 'payments' then 'payments'
    when 'dues' then 'payments'
    when 'attendance' then 'attendance'
    when 'leads' then 'leads'
    when 'expenses' then 'expenses'
    when 'activity_logs' then 'reports'
  end;
$$;
revoke all on function private.export_module(text) from public, anon, authenticated;

create or replace function public.prepare_data_export(
  p_gym_id uuid,
  p_export_type text,
  p_from date,
  p_to date,
  p_filters jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_module text := private.export_module(p_export_type);
  v_from date := coalesce(p_from, current_date - 30);
  v_to date := coalesce(p_to, current_date);
  v_rows jsonb := '[]'::jsonb;
  v_columns jsonb := '[]'::jsonb;
  v_job_id uuid;
  v_role text;
  v_can_pii boolean;
  v_search text := lower(trim(coalesce(p_filters ->> 'search', '')));
begin
  if v_module is null then raise exception 'unsupported_export_type'; end if;
  if v_from > v_to then raise exception 'invalid_date_range'; end if;
  if v_to - v_from > 1826 then raise exception 'date_range_too_large'; end if;
  if not private.has_gym_permission(p_gym_id, 'reports', 'export')
     or not private.has_gym_permission(p_gym_id, v_module, 'view')
     or not private.has_gym_permission(p_gym_id, v_module, 'export') then
    raise exception 'permission_denied';
  end if;

  select sga.role into v_role from public.staff_gym_access sga
  where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id;
  v_can_pii := v_role in ('owner', 'manager');

  if p_export_type = 'members' then
    v_columns := '["Membership ID","First name","Last name","Email","Phone","Status","Joined date","Next payment date"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Membership ID', coalesce(m.custom_id, m.id::text),
      'First name', m.first_name,
      'Last name', coalesce(m.last_name, ''),
      'Email', case when v_can_pii then coalesce(m.email, '') else '' end,
      'Phone', case when v_can_pii then coalesce(m.phone, '') else '' end,
      'Status', m.status,
      'Joined date', (m.joined_at at time zone 'Asia/Kolkata')::date,
      'Next payment date', m.next_payment_date
    ) order by m.joined_at desc), '[]'::jsonb) into v_rows
    from public.members m
    where m.gym_id = p_gym_id
      and (m.joined_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and (coalesce(p_filters ->> 'status', '') = '' or m.status = p_filters ->> 'status')
      and (v_search = '' or lower(m.first_name || ' ' || coalesce(m.last_name, '')) like '%' || v_search || '%');

  elsif p_export_type = 'payments' then
    v_columns := '["Payment date","Invoice number","Member","Membership ID","Amount","Method","Status","Reference"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Payment date', (p.created_at at time zone 'Asia/Kolkata')::date,
      'Invoice number', i.invoice_number,
      'Member', trim(m.first_name || ' ' || coalesce(m.last_name, '')),
      'Membership ID', coalesce(m.custom_id, m.id::text),
      'Amount', p.amount,
      'Method', coalesce(p.method, ''),
      'Status', p.status,
      'Reference', coalesce(p.reference_no, '')
    ) order by p.created_at desc), '[]'::jsonb) into v_rows
    from public.payments p
    join public.invoices i on i.id = p.invoice_id
    join public.members m on m.id = i.member_id
    where i.gym_id = p_gym_id
      and (p.created_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and (coalesce(p_filters ->> 'method', '') = '' or p.method = p_filters ->> 'method')
      and (coalesce(p_filters ->> 'status', '') = '' or p.status = p_filters ->> 'status')
      and (v_search = '' or lower(m.first_name || ' ' || coalesce(m.last_name, '')) like '%' || v_search || '%');

  elsif p_export_type = 'dues' then
    v_columns := '["Due date","Invoice number","Member","Membership ID","Invoice amount","Paid","Outstanding","Status"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Due date', (i.due_at at time zone 'Asia/Kolkata')::date,
      'Invoice number', i.invoice_number,
      'Member', trim(m.first_name || ' ' || coalesce(m.last_name, '')),
      'Membership ID', coalesce(m.custom_id, m.id::text),
      'Invoice amount', i.amount,
      'Paid', paid.total,
      'Outstanding', greatest(i.amount - paid.total, 0),
      'Status', i.status
    ) order by i.due_at), '[]'::jsonb) into v_rows
    from public.invoices i
    join public.members m on m.id = i.member_id
    cross join lateral (
      select coalesce(sum(p.amount) filter (where p.status = 'succeeded'), 0) as total
      from public.payments p where p.invoice_id = i.id
    ) paid
    where i.gym_id = p_gym_id
      and i.status in ('open', 'partial')
      and (i.due_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and greatest(i.amount - paid.total, 0) > 0
      and (v_search = '' or lower(m.first_name || ' ' || coalesce(m.last_name, '')) like '%' || v_search || '%');

  elsif p_export_type = 'attendance' then
    v_columns := '["Date","Member","Membership ID","Check in","Check out","Method","Correction reason"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Date', (c.checked_in_at at time zone 'Asia/Kolkata')::date,
      'Member', trim(m.first_name || ' ' || coalesce(m.last_name, '')),
      'Membership ID', coalesce(m.custom_id, m.id::text),
      'Check in', to_char(c.checked_in_at at time zone 'Asia/Kolkata', 'HH12:MI AM'),
      'Check out', case when c.checked_out_at is null then '' else to_char(c.checked_out_at at time zone 'Asia/Kolkata', 'HH12:MI AM') end,
      'Method', c.method,
      'Correction reason', coalesce(c.manual_reason, '')
    ) order by c.checked_in_at desc), '[]'::jsonb) into v_rows
    from public.check_ins c
    join public.members m on m.id = c.member_id
    where c.gym_id = p_gym_id
      and (c.checked_in_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and (coalesce(p_filters ->> 'method', '') = '' or c.method = p_filters ->> 'method')
      and (v_search = '' or lower(m.first_name || ' ' || coalesce(m.last_name, '')) like '%' || v_search || '%');

  elsif p_export_type = 'leads' then
    v_columns := '["Created date","First name","Last name","Email","Phone","Source","Status","Follow-up date"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Created date', (l.created_at at time zone 'Asia/Kolkata')::date,
      'First name', l.first_name,
      'Last name', l.last_name,
      'Email', case when v_can_pii then coalesce(l.email, '') else '' end,
      'Phone', case when v_can_pii then coalesce(l.phone, '') else '' end,
      'Source', l.source,
      'Status', l.status,
      'Follow-up date', case when l.follow_up_at is null then null else (l.follow_up_at at time zone 'Asia/Kolkata')::date end
    ) order by l.created_at desc), '[]'::jsonb) into v_rows
    from public.leads l
    where l.gym_id = p_gym_id
      and (l.created_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and (coalesce(p_filters ->> 'status', '') = '' or l.status = p_filters ->> 'status')
      and (coalesce(p_filters ->> 'source', '') = '' or l.source = p_filters ->> 'source')
      and (v_search = '' or lower(l.first_name || ' ' || l.last_name) like '%' || v_search || '%');

  elsif p_export_type = 'expenses' then
    v_columns := '["Expense date","Category","Amount","Note","Created date"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Expense date', e.expense_date,
      'Category', e.category,
      'Amount', e.amount,
      'Note', coalesce(e.note, ''),
      'Created date', (e.created_at at time zone 'Asia/Kolkata')::date
    ) order by e.expense_date desc), '[]'::jsonb) into v_rows
    from public.expenses e
    where e.gym_id = p_gym_id
      and e.expense_date between v_from and v_to
      and (coalesce(p_filters ->> 'category', '') = '' or e.category = p_filters ->> 'category')
      and (v_search = '' or lower(e.category || ' ' || coalesce(e.note, '')) like '%' || v_search || '%');

  elsif p_export_type = 'activity_logs' then
    if v_role not in ('owner', 'manager') then raise exception 'permission_denied'; end if;
    v_columns := '["Timestamp","Actor","Module","Action","Entity","Amount","Branch","Metadata"]'::jsonb;
    select coalesce(jsonb_agg(jsonb_build_object(
      'Timestamp', a.created_at,
      'Actor', a.actor_name,
      'Module', a.module,
      'Action', a.action_type,
      'Entity', coalesce(a.entity_label, a.entity_type),
      'Amount', a.amount,
      'Branch', g.name,
      'Metadata', a.metadata
    ) order by a.created_at desc), '[]'::jsonb) into v_rows
    from public.activity_log_entries a
    join public.gyms g on g.id = a.branch_id
    where a.gym_id = p_gym_id
      and (a.created_at at time zone 'Asia/Kolkata')::date between v_from and v_to
      and (coalesce(p_filters ->> 'actor_id', '') = '' or a.actor_id::text = p_filters ->> 'actor_id')
      and (coalesce(p_filters ->> 'module', '') = '' or a.module = p_filters ->> 'module')
      and (coalesce(p_filters ->> 'action_type', '') = '' or a.action_type = p_filters ->> 'action_type')
      and (v_search = '' or lower(a.actor_name || ' ' || coalesce(a.entity_label, '') || ' ' || a.action_type) like '%' || v_search || '%');
  end if;

  insert into private.data_export_jobs (
    gym_id, actor_id, export_type, filters, row_count
  ) values (
    p_gym_id, auth.uid(), p_export_type,
    jsonb_build_object('from', v_from, 'to', v_to, 'filters', coalesce(p_filters, '{}'::jsonb)),
    jsonb_array_length(v_rows)
  ) returning id into v_job_id;

  return jsonb_build_object(
    'export_id', v_job_id,
    'type', p_export_type,
    'columns', v_columns,
    'rows', v_rows,
    'row_count', jsonb_array_length(v_rows),
    'pii_included', v_can_pii,
    'filters', jsonb_build_object('from', v_from, 'to', v_to, 'filters', coalesce(p_filters, '{}'::jsonb))
  );
end;
$$;

revoke all on function public.prepare_data_export(uuid, text, date, date, jsonb) from public, anon;
grant execute on function public.prepare_data_export(uuid, text, date, date, jsonb) to authenticated;

create or replace function public.complete_data_export(p_export_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_job private.data_export_jobs%rowtype;
begin
  select * into v_job from private.data_export_jobs j
  where j.id = p_export_id and j.actor_id = auth.uid()
  for update;
  if not found then raise exception 'export_not_found'; end if;
  if v_job.completed_at is not null then return; end if;
  if v_job.created_at < now() - interval '30 minutes' then raise exception 'export_expired'; end if;

  update private.data_export_jobs set completed_at = now() where id = v_job.id;
  perform private.write_activity_log(
    v_job.gym_id, 'reports', 'data_export_completed', 'export', v_job.id,
    v_job.export_type, null,
    jsonb_build_object(
      'export_type', v_job.export_type,
      'filters', v_job.filters,
      'row_count', v_job.row_count
    )
  );
end;
$$;

revoke all on function public.complete_data_export(uuid) from public, anon;
grant execute on function public.complete_data_export(uuid) to authenticated;
