-- Keep background/service-role events for internal audit integrity, but expose
-- only actions attributable to a signed-in human in the owner-facing timeline.
drop policy if exists activity_log_owner_manager_read
  on public.activity_log_entries;
create policy activity_log_owner_manager_read
on public.activity_log_entries for select to authenticated
using (
  actor_id is not null
  and (select private.has_gym_permission(gym_id, 'reports', 'view'))
  and exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = (select auth.uid())
      and sga.gym_id = activity_log_entries.gym_id
      and sga.role in ('owner', 'manager')
  )
);

-- The existing staff invite/remove HTTP endpoint uses service-role credentials,
-- so its table triggers cannot recover the initiating owner's auth.uid().
-- The authenticated Flutter client records the successful human action through
-- this narrow, permission-checked RPC. No email address or token is stored.
create or replace function public.record_staff_activity(
  p_gym_id uuid,
  p_action_type text,
  p_profile_id uuid default null,
  p_display_name text default null,
  p_role text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_action text;
  v_log_id uuid;
begin
  v_required_action := case p_action_type
    when 'staff_invited' then 'add'
    when 'staff_removed' then 'delete'
    when 'staff_role_changed' then 'edit'
    else null
  end;
  if v_required_action is null then
    raise exception 'unsupported_staff_activity';
  end if;

  if p_role is not null
     and p_role not in ('owner', 'manager', 'trainer', 'staff') then
    raise exception 'invalid_staff_role';
  end if;

  if not private.has_gym_permission(
    p_gym_id, 'staff', v_required_action
  ) then
    raise exception 'permission_denied';
  end if;

  select private.write_activity_log(
    p_gym_id,
    'staff',
    p_action_type,
    'staff',
    p_profile_id,
    nullif(trim(coalesce(p_display_name, '')), ''),
    null,
    jsonb_strip_nulls(jsonb_build_object('role', p_role))
  ) into v_log_id;

  return v_log_id;
end;
$$;

revoke all on function public.record_staff_activity(
  uuid, text, uuid, text, text
) from public, anon;
grant execute on function public.record_staff_activity(
  uuid, text, uuid, text, text
) to authenticated;

create or replace function public.get_activity_log(
  p_gym_ids uuid[],
  p_from timestamptz,
  p_to timestamptz,
  p_search text default null,
  p_actor_id uuid default null,
  p_module text default null,
  p_action_type text default null,
  p_limit integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gym_ids uuid[];
  v_items jsonb;
  v_total integer;
begin
  select coalesce(array_agg(sga.gym_id), '{}'::uuid[]) into v_gym_ids
  from public.staff_gym_access sga
  where sga.profile_id = auth.uid()
    and sga.role in ('owner', 'manager')
    and private.has_gym_permission(sga.gym_id, 'reports', 'view')
    and (p_gym_ids is null or sga.gym_id = any(p_gym_ids));

  if cardinality(v_gym_ids) = 0 then raise exception 'permission_denied'; end if;
  if p_gym_ids is not null and exists (
    select requested from unnest(p_gym_ids) requested
    where not (requested = any(v_gym_ids))
  ) then raise exception 'permission_denied'; end if;

  select count(*)::integer into v_total
  from public.activity_log_entries a
  where a.gym_id = any(v_gym_ids)
    and a.actor_id is not null
    and a.created_at >= coalesce(p_from, now() - interval '30 days')
    and a.created_at < coalesce(p_to, now() + interval '1 second')
    and (p_actor_id is null or a.actor_id = p_actor_id)
    and (nullif(p_module, '') is null or a.module = p_module)
    and (nullif(p_action_type, '') is null or a.action_type = p_action_type)
    and (
      nullif(trim(p_search), '') is null
      or a.actor_name ilike '%' || trim(p_search) || '%'
      or coalesce(a.entity_label, '') ilike '%' || trim(p_search) || '%'
      or a.action_type ilike '%' || trim(p_search) || '%'
    );

  select coalesce(jsonb_agg(item order by item_created_at desc), '[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'id', a.id,
      'gym_id', a.gym_id,
      'branch_id', a.branch_id,
      'branch_name', g.name,
      'actor_id', a.actor_id,
      'actor_name', a.actor_name,
      'module', a.module,
      'action_type', a.action_type,
      'entity_type', a.entity_type,
      'entity_id', a.entity_id,
      'entity_label', a.entity_label,
      'amount', a.amount,
      'metadata', a.metadata,
      'created_at', a.created_at
    ) as item,
    a.created_at as item_created_at
    from public.activity_log_entries a
    join public.gyms g on g.id = a.branch_id
    where a.gym_id = any(v_gym_ids)
    and a.actor_id is not null
      and a.created_at >= coalesce(p_from, now() - interval '30 days')
      and a.created_at < coalesce(p_to, now() + interval '1 second')
      and (p_actor_id is null or a.actor_id = p_actor_id)
      and (nullif(p_module, '') is null or a.module = p_module)
      and (nullif(p_action_type, '') is null or a.action_type = p_action_type)
      and (
        nullif(trim(p_search), '') is null
        or a.actor_name ilike '%' || trim(p_search) || '%'
        or coalesce(a.entity_label, '') ilike '%' || trim(p_search) || '%'
        or a.action_type ilike '%' || trim(p_search) || '%'
      )
    order by a.created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200)
    offset greatest(coalesce(p_offset, 0), 0)
  ) page;

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;

revoke all on function public.get_activity_log(uuid[], timestamptz, timestamptz, text, uuid, text, text, integer, integer)
  from public, anon;
grant execute on function public.get_activity_log(uuid[], timestamptz, timestamptz, text, uuid, text, text, integer, integer)
  to authenticated;

create or replace function public.get_activity_log_entry(p_entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_entry jsonb;
begin
  select jsonb_build_object(
    'id', a.id, 'gym_id', a.gym_id, 'branch_id', a.branch_id,
    'branch_name', g.name, 'actor_id', a.actor_id, 'actor_name', a.actor_name,
    'module', a.module, 'action_type', a.action_type,
    'entity_type', a.entity_type, 'entity_id', a.entity_id,
    'entity_label', a.entity_label, 'amount', a.amount,
    'metadata', a.metadata, 'created_at', a.created_at
  ) into v_entry
  from public.activity_log_entries a
  join public.gyms g on g.id = a.branch_id
  where a.id = p_entry_id
    and a.actor_id is not null
    and exists (
      select 1 from public.staff_gym_access sga
      where sga.profile_id = auth.uid() and sga.gym_id = a.gym_id
        and sga.role in ('owner', 'manager')
        and private.has_gym_permission(a.gym_id, 'reports', 'view')
    );
  if v_entry is null then raise exception 'activity_not_found_or_denied'; end if;
  return v_entry;
end;
$$;

revoke all on function public.get_activity_log_entry(uuid) from public, anon;
grant execute on function public.get_activity_log_entry(uuid) to authenticated;

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
      and a.actor_id is not null
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
