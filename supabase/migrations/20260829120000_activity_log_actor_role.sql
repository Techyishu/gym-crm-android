-- Surface the actor's current role (owner/manager/trainer/staff) in the
-- activity log so "who did this" reads as more than just a name. Looked up
-- live against staff_gym_access rather than stored on the row — a role
-- change should relabel past entries too, not freeze them at insert time.

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
      'actor_role', sga.role,
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
    left join public.staff_gym_access sga
      on sga.profile_id = a.actor_id and sga.gym_id = a.gym_id
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
    'actor_role', sga.role,
    'module', a.module, 'action_type', a.action_type,
    'entity_type', a.entity_type, 'entity_id', a.entity_id,
    'entity_label', a.entity_label, 'amount', a.amount,
    'metadata', a.metadata, 'created_at', a.created_at
  ) into v_entry
  from public.activity_log_entries a
  join public.gyms g on g.id = a.branch_id
  left join public.staff_gym_access sga
    on sga.profile_id = a.actor_id and sga.gym_id = a.gym_id
  where a.id = p_entry_id
    and a.actor_id is not null
    and exists (
      select 1 from public.staff_gym_access sga2
      where sga2.profile_id = auth.uid() and sga2.gym_id = a.gym_id
        and sga2.role in ('owner', 'manager')
        and private.has_gym_permission(a.gym_id, 'reports', 'view')
    );
  if v_entry is null then raise exception 'activity_not_found_or_denied'; end if;
  return v_entry;
end;
$$;

revoke all on function public.get_activity_log_entry(uuid) from public, anon;
grant execute on function public.get_activity_log_entry(uuid) to authenticated;
