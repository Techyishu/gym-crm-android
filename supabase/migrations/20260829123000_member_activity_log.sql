-- Per-member activity feed for the member detail screen's Activity tab.
-- Matches rows where the member is the entity itself (member created/edited/
-- deleted/restored) as well as rows where the member only shows up in
-- metadata (payments, invoices, memberships, attendance, all recorded
-- against the member but entity_type'd as their own table).
create or replace function public.get_member_activity_log(
  p_member_id uuid,
  p_limit integer default 30,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gym_id uuid;
  v_items jsonb;
  v_total integer;
begin
  select m.gym_id into v_gym_id from public.members m where m.id = p_member_id;
  if v_gym_id is null then raise exception 'member_not_found'; end if;

  if not exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = auth.uid() and sga.gym_id = v_gym_id
      and sga.role in ('owner', 'manager')
      and private.has_gym_permission(v_gym_id, 'reports', 'view')
  ) then
    raise exception 'permission_denied';
  end if;

  select count(*)::integer into v_total
  from public.activity_log_entries a
  where a.gym_id = v_gym_id
    and a.actor_id is not null
    and (
      (a.entity_type = 'member' and a.entity_id = p_member_id)
      or a.metadata ->> 'member_id' = p_member_id::text
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
    where a.gym_id = v_gym_id
      and a.actor_id is not null
      and (
        (a.entity_type = 'member' and a.entity_id = p_member_id)
        or a.metadata ->> 'member_id' = p_member_id::text
      )
    order by a.created_at desc
    limit least(greatest(coalesce(p_limit, 30), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  ) page;

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;

revoke all on function public.get_member_activity_log(uuid, integer, integer) from public, anon;
grant execute on function public.get_member_activity_log(uuid, integer, integer) to authenticated;
