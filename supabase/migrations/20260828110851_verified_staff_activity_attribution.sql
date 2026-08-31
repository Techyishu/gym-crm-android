-- Replace the client-asserted activity writer with attribution of a real,
-- recent server-side staff access event. The underlying event must already
-- exist, so a modified client cannot invent invitations or removals.
drop function if exists public.record_staff_activity(
  uuid, text, uuid, text, text
);

create or replace function public.attribute_recent_staff_activity(
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
  v_source_action text;
  v_entry_id uuid;
  v_actor_name text;
begin
  select required_action, source_action
  into v_required_action, v_source_action
  from (values
    ('staff_invited', 'add', 'staff_access_added'),
    ('staff_removed', 'delete', 'staff_access_removed'),
    ('staff_role_changed', 'edit', 'staff_role_changed')
  ) allowed(action_type, required_action, source_action)
  where allowed.action_type = p_action_type;

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

  select nullif(trim(
    coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')
  ), '')
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();
  if v_actor_name is null then
    raise exception 'permission_denied';
  end if;

  select a.id into v_entry_id
  from public.activity_log_entries a
  where a.gym_id = p_gym_id
    and a.actor_id is null
    and a.module = 'staff'
    and a.action_type = v_source_action
    and a.created_at >= now() - interval '15 minutes'
    and (p_profile_id is null or a.entity_id = p_profile_id)
    and (
      nullif(trim(p_display_name), '') is null
      or lower(trim(coalesce(a.entity_label, '')))
        = lower(trim(p_display_name))
    )
    and (
      p_role is null
      or a.metadata ->> 'new_role' = p_role
      or a.metadata ->> 'old_role' = p_role
      or a.metadata ->> 'role' = p_role
    )
  order by a.created_at desc
  limit 1
  for update;

  if v_entry_id is null then
    raise exception 'verified_staff_activity_not_found';
  end if;

  update public.activity_log_entries
  set actor_id = auth.uid(),
      actor_name = v_actor_name,
      action_type = p_action_type,
      metadata = metadata || jsonb_build_object(
        'actor_attributed_at', now()
      )
  where id = v_entry_id
    and actor_id is null;

  if not found then
    raise exception 'staff_activity_already_attributed';
  end if;
  return v_entry_id;
end;
$$;

revoke all on function public.attribute_recent_staff_activity(
  uuid, text, uuid, text, text
) from public, anon;
grant execute on function public.attribute_recent_staff_activity(
  uuid, text, uuid, text, text
) to authenticated;
