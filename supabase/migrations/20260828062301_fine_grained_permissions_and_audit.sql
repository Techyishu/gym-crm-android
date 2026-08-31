-- Fine-grained, branch-aware authorization and an immutable business audit log.
-- Existing owner/manager/trainer/staff roles remain the fallback defaults. A
-- missing override therefore behaves exactly like the role matrix below.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.gym_role_permissions (
  gym_id uuid not null references public.gyms(id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'trainer', 'staff')),
  module text not null check (module in (
    'members', 'memberships', 'pt', 'services', 'attendance', 'payments',
    'reports', 'batches', 'leads', 'expenses', 'staff', 'settings'
  )),
  can_view boolean not null default false,
  can_add boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_freeze boolean not null default false,
  can_export boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (gym_id, role, module),
  check (role <> 'owner' or (
    can_view and can_add and can_edit and can_delete and can_freeze and can_export
  ))
);

create table public.staff_permission_overrides (
  gym_id uuid not null references public.gyms(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  module text not null check (module in (
    'members', 'memberships', 'pt', 'services', 'attendance', 'payments',
    'reports', 'batches', 'leads', 'expenses', 'staff', 'settings'
  )),
  can_view boolean not null,
  can_add boolean not null,
  can_edit boolean not null,
  can_delete boolean not null,
  can_freeze boolean not null,
  can_export boolean not null,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (gym_id, profile_id, module)
);

create index gym_role_permissions_gym_idx
  on public.gym_role_permissions (gym_id, role);
create index staff_permission_overrides_profile_idx
  on public.staff_permission_overrides (profile_id, gym_id);

alter table public.gym_role_permissions enable row level security;
alter table public.staff_permission_overrides enable row level security;
revoke all on table public.gym_role_permissions from anon, authenticated;
revoke all on table public.staff_permission_overrides from anon, authenticated;
grant select on table public.gym_role_permissions to authenticated;
grant select on table public.staff_permission_overrides to authenticated;

create or replace function private.builtin_gym_permission(
  p_role text,
  p_module text,
  p_action text
) returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  if p_role = 'owner' then
    return true;
  end if;

  if p_role = 'manager' then
    if p_action = 'view' then return true; end if;
    if p_action = 'add' then return p_module <> 'reports'; end if;
    if p_action = 'edit' then return p_module <> 'reports'; end if;
    if p_action = 'delete' then
      return p_module in ('members', 'memberships', 'pt', 'services', 'batches', 'leads');
    end if;
    if p_action = 'freeze' then return p_module = 'members'; end if;
    if p_action = 'export' then return true; end if;
    return false;
  end if;

  if p_role = 'trainer' then
    if p_action = 'view' then
      return p_module in ('members', 'memberships', 'pt', 'services', 'attendance', 'batches');
    end if;
    if p_action in ('add', 'edit') then
      return p_module in ('pt', 'services', 'attendance', 'batches');
    end if;
    if p_action = 'delete' then return p_module in ('pt', 'services', 'batches'); end if;
    return false;
  end if;

  if p_role = 'staff' then
    if p_action = 'view' then
      return p_module in ('members', 'memberships', 'pt', 'services', 'attendance', 'payments', 'batches');
    end if;
    if p_action = 'add' then
      return p_module in ('pt', 'services', 'attendance', 'payments', 'batches');
    end if;
    if p_action = 'edit' then return p_module in ('pt', 'services', 'attendance', 'batches'); end if;
    if p_action = 'delete' then return p_module in ('pt', 'services', 'batches'); end if;
    return false;
  end if;

  return false;
end;
$$;

create or replace function private.has_gym_permission(
  p_gym_id uuid,
  p_module text,
  p_action text
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_override public.staff_permission_overrides%rowtype;
  v_role_permission public.gym_role_permissions%rowtype;
begin
  if v_uid is null
     or p_module not in (
       'members', 'memberships', 'pt', 'services', 'attendance', 'payments',
       'reports', 'batches', 'leads', 'expenses', 'staff', 'settings'
     )
     or p_action not in ('view', 'add', 'edit', 'delete', 'freeze', 'export') then
    return false;
  end if;

  select sga.role into v_role
  from public.staff_gym_access sga
  where sga.profile_id = v_uid and sga.gym_id = p_gym_id;

  if v_role is null then return false; end if;
  if v_role = 'owner' then return true; end if;

  select * into v_override
  from public.staff_permission_overrides spo
  where spo.profile_id = v_uid
    and spo.gym_id = p_gym_id
    and spo.module = p_module;

  if found then
    return case p_action
      when 'view' then v_override.can_view
      when 'add' then v_override.can_add
      when 'edit' then v_override.can_edit
      when 'delete' then v_override.can_delete
      when 'freeze' then v_override.can_freeze
      when 'export' then v_override.can_export
      else false
    end;
  end if;

  select * into v_role_permission
  from public.gym_role_permissions grp
  where grp.gym_id = p_gym_id
    and grp.role = v_role
    and grp.module = p_module;

  if found then
    return case p_action
      when 'view' then v_role_permission.can_view
      when 'add' then v_role_permission.can_add
      when 'edit' then v_role_permission.can_edit
      when 'delete' then v_role_permission.can_delete
      when 'freeze' then v_role_permission.can_freeze
      when 'export' then v_role_permission.can_export
      else false
    end;
  end if;

  return private.builtin_gym_permission(v_role, p_module, p_action);
end;
$$;

revoke all on function private.builtin_gym_permission(text, text, text) from public, anon, authenticated;
revoke all on function private.has_gym_permission(uuid, text, text) from public, anon;
grant execute on function private.has_gym_permission(uuid, text, text) to authenticated;

-- Materialize the defaults so owners can edit role rows immediately. The
-- resolver still falls back to builtin_gym_permission for older/new gyms if a
-- row is ever missing.
insert into public.gym_role_permissions (
  gym_id, role, module, can_view, can_add, can_edit, can_delete, can_freeze, can_export
)
select g.id, r.role, m.module,
  private.builtin_gym_permission(r.role, m.module, 'view'),
  private.builtin_gym_permission(r.role, m.module, 'add'),
  private.builtin_gym_permission(r.role, m.module, 'edit'),
  private.builtin_gym_permission(r.role, m.module, 'delete'),
  private.builtin_gym_permission(r.role, m.module, 'freeze'),
  private.builtin_gym_permission(r.role, m.module, 'export')
from public.gyms g
cross join (values ('owner'), ('manager'), ('trainer'), ('staff')) as r(role)
cross join (values
  ('members'), ('memberships'), ('pt'), ('services'), ('attendance'), ('payments'),
  ('reports'), ('batches'), ('leads'), ('expenses'), ('staff'), ('settings')
) as m(module)
on conflict (gym_id, role, module) do nothing;

create or replace function private.seed_gym_role_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.gym_role_permissions (
    gym_id, role, module, can_view, can_add, can_edit, can_delete, can_freeze, can_export
  )
  select new.id, r.role, m.module,
    private.builtin_gym_permission(r.role, m.module, 'view'),
    private.builtin_gym_permission(r.role, m.module, 'add'),
    private.builtin_gym_permission(r.role, m.module, 'edit'),
    private.builtin_gym_permission(r.role, m.module, 'delete'),
    private.builtin_gym_permission(r.role, m.module, 'freeze'),
    private.builtin_gym_permission(r.role, m.module, 'export')
  from (values ('owner'), ('manager'), ('trainer'), ('staff')) as r(role)
  cross join (values
    ('members'), ('memberships'), ('pt'), ('services'), ('attendance'), ('payments'),
    ('reports'), ('batches'), ('leads'), ('expenses'), ('staff'), ('settings')
  ) as m(module)
  on conflict (gym_id, role, module) do nothing;
  return new;
end;
$$;

drop trigger if exists gyms_seed_role_permissions on public.gyms;
create trigger gyms_seed_role_permissions
after insert on public.gyms
for each row execute function private.seed_gym_role_permissions();

create policy gym_role_permissions_owner_read
on public.gym_role_permissions for select to authenticated
using (
  exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = (select auth.uid())
      and sga.gym_id = gym_role_permissions.gym_id
      and sga.role = 'owner'
  )
);

create policy staff_permission_overrides_owner_or_self_read
on public.staff_permission_overrides for select to authenticated
using (
  profile_id = (select auth.uid())
  or exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = (select auth.uid())
      and sga.gym_id = staff_permission_overrides.gym_id
      and sga.role = 'owner'
  )
);

create table public.activity_log_entries (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  branch_id uuid not null references public.gyms(id) on delete cascade,
  actor_id uuid,
  actor_name text not null default 'System',
  module text not null,
  action_type text not null,
  entity_type text not null,
  entity_id uuid,
  entity_label text,
  amount numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (gym_id = branch_id),
  check (jsonb_typeof(metadata) = 'object')
);

create index activity_log_entries_gym_created_idx
  on public.activity_log_entries (gym_id, created_at desc);
create index activity_log_entries_gym_module_idx
  on public.activity_log_entries (gym_id, module, created_at desc);
create index activity_log_entries_actor_idx
  on public.activity_log_entries (actor_id, created_at desc);
create index activity_log_entries_action_idx
  on public.activity_log_entries (gym_id, action_type, created_at desc);

alter table public.activity_log_entries enable row level security;
revoke all on table public.activity_log_entries from anon, authenticated;
grant select on table public.activity_log_entries to authenticated;

create policy activity_log_owner_manager_read
on public.activity_log_entries for select to authenticated
using (
  (select private.has_gym_permission(gym_id, 'reports', 'view'))
  and exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = (select auth.uid())
      and sga.gym_id = activity_log_entries.gym_id
      and sga.role in ('owner', 'manager')
  )
);

create or replace function private.write_activity_log(
  p_gym_id uuid,
  p_module text,
  p_action_type text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_entity_label text default null,
  p_amount numeric default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_actor_name text;
begin
  if p_gym_id is null then return null; end if;

  select nullif(trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), '')
  into v_actor_name
  from public.profiles p where p.id = auth.uid();

  insert into public.activity_log_entries (
    gym_id, branch_id, actor_id, actor_name, module, action_type,
    entity_type, entity_id, entity_label, amount, metadata
  ) values (
    p_gym_id, p_gym_id, auth.uid(), coalesce(v_actor_name, 'System'), p_module,
    p_action_type, p_entity_type, p_entity_id, nullif(p_entity_label, ''),
    p_amount, coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.write_activity_log(uuid, text, text, text, uuid, text, numeric, jsonb)
  from public, anon, authenticated;

create or replace function public.get_my_permissions(p_gym_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(module, permissions), '{}'::jsonb)
  from (
    select m.module,
      jsonb_build_object(
        'view', private.has_gym_permission(p_gym_id, m.module, 'view'),
        'add', private.has_gym_permission(p_gym_id, m.module, 'add'),
        'edit', private.has_gym_permission(p_gym_id, m.module, 'edit'),
        'delete', private.has_gym_permission(p_gym_id, m.module, 'delete'),
        'freeze', private.has_gym_permission(p_gym_id, m.module, 'freeze'),
        'export', private.has_gym_permission(p_gym_id, m.module, 'export')
      ) as permissions
    from (values
      ('members'), ('memberships'), ('pt'), ('services'), ('attendance'), ('payments'),
      ('reports'), ('batches'), ('leads'), ('expenses'), ('staff'), ('settings')
    ) as m(module)
  ) resolved;
$$;

revoke all on function public.get_my_permissions(uuid) from public, anon;
grant execute on function public.get_my_permissions(uuid) to authenticated;

create or replace function public.get_permission_matrix(p_gym_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id and sga.role = 'owner'
  ) then raise exception 'permission_denied'; end if;

  select jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(to_jsonb(rp) order by rp.role, rp.module)
      from public.gym_role_permissions rp where rp.gym_id = p_gym_id
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'profile_id', sga.profile_id,
        'role', sga.role,
        'first_name', p.first_name,
        'last_name', p.last_name,
        'overrides', coalesce((
          select jsonb_agg(to_jsonb(spo) order by spo.module)
          from public.staff_permission_overrides spo
          where spo.gym_id = p_gym_id and spo.profile_id = sga.profile_id
        ), '[]'::jsonb)
      ) order by p.first_name, p.last_name)
      from public.staff_gym_access sga
      join public.profiles p on p.id = sga.profile_id
      where sga.gym_id = p_gym_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.get_permission_matrix(uuid) from public, anon;
grant execute on function public.get_permission_matrix(uuid) to authenticated;

create or replace function public.set_role_permissions(
  p_gym_id uuid,
  p_role text,
  p_module text,
  p_can_view boolean,
  p_can_add boolean,
  p_can_edit boolean,
  p_can_delete boolean,
  p_can_freeze boolean,
  p_can_export boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id and sga.role = 'owner'
  ) then raise exception 'permission_denied'; end if;
  if p_role = 'owner' then raise exception 'owner_permissions_are_locked'; end if;

  insert into public.gym_role_permissions (
    gym_id, role, module, can_view, can_add, can_edit, can_delete,
    can_freeze, can_export, updated_by, updated_at
  ) values (
    p_gym_id, p_role, p_module, p_can_view, p_can_add, p_can_edit,
    p_can_delete, p_can_freeze, p_can_export, auth.uid(), now()
  ) on conflict (gym_id, role, module) do update set
    can_view = excluded.can_view,
    can_add = excluded.can_add,
    can_edit = excluded.can_edit,
    can_delete = excluded.can_delete,
    can_freeze = excluded.can_freeze,
    can_export = excluded.can_export,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform private.write_activity_log(
    p_gym_id, 'staff', 'staff_role_permissions_changed', 'role', null,
    p_role || ' · ' || p_module, null,
    jsonb_build_object(
      'role', p_role, 'module', p_module,
      'permissions', jsonb_build_object(
        'view', p_can_view, 'add', p_can_add, 'edit', p_can_edit,
        'delete', p_can_delete, 'freeze', p_can_freeze, 'export', p_can_export
      )
    )
  );
end;
$$;

revoke all on function public.set_role_permissions(uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean)
  from public, anon;
grant execute on function public.set_role_permissions(uuid, text, text, boolean, boolean, boolean, boolean, boolean, boolean)
  to authenticated;

create or replace function public.set_staff_permissions(
  p_gym_id uuid,
  p_profile_id uuid,
  p_module text,
  p_can_view boolean,
  p_can_add boolean,
  p_can_edit boolean,
  p_can_delete boolean,
  p_can_freeze boolean,
  p_can_export boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_target_role text;
begin
  if not exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id and sga.role = 'owner'
  ) then raise exception 'permission_denied'; end if;

  select role into v_target_role from public.staff_gym_access
  where profile_id = p_profile_id and gym_id = p_gym_id;
  if v_target_role is null then raise exception 'staff_not_in_branch'; end if;
  if v_target_role = 'owner' then raise exception 'owner_permissions_are_locked'; end if;

  insert into public.staff_permission_overrides (
    gym_id, profile_id, module, can_view, can_add, can_edit, can_delete,
    can_freeze, can_export, updated_by, updated_at
  ) values (
    p_gym_id, p_profile_id, p_module, p_can_view, p_can_add, p_can_edit,
    p_can_delete, p_can_freeze, p_can_export, auth.uid(), now()
  ) on conflict (gym_id, profile_id, module) do update set
    can_view = excluded.can_view,
    can_add = excluded.can_add,
    can_edit = excluded.can_edit,
    can_delete = excluded.can_delete,
    can_freeze = excluded.can_freeze,
    can_export = excluded.can_export,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  perform private.write_activity_log(
    p_gym_id, 'staff', 'staff_permissions_changed', 'profile', p_profile_id,
    p_module, null,
    jsonb_build_object(
      'profile_id', p_profile_id, 'module', p_module,
      'permissions', jsonb_build_object(
        'view', p_can_view, 'add', p_can_add, 'edit', p_can_edit,
        'delete', p_can_delete, 'freeze', p_can_freeze, 'export', p_can_export
      )
    )
  );
end;
$$;

revoke all on function public.set_staff_permissions(uuid, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean)
  from public, anon;
grant execute on function public.set_staff_permissions(uuid, uuid, text, boolean, boolean, boolean, boolean, boolean, boolean)
  to authenticated;

create or replace function public.clear_staff_permission_override(
  p_gym_id uuid,
  p_profile_id uuid,
  p_module text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = auth.uid() and sga.gym_id = p_gym_id and sga.role = 'owner'
  ) then raise exception 'permission_denied'; end if;
  if exists (
    select 1 from public.staff_gym_access sga
    where sga.profile_id = p_profile_id and sga.gym_id = p_gym_id and sga.role = 'owner'
  ) then raise exception 'owner_permissions_are_locked'; end if;

  delete from public.staff_permission_overrides
  where gym_id = p_gym_id and profile_id = p_profile_id and module = p_module;

  perform private.write_activity_log(
    p_gym_id, 'staff', 'staff_permission_override_cleared', 'profile',
    p_profile_id, p_module, null,
    jsonb_build_object('profile_id', p_profile_id, 'module', p_module)
  );
end;
$$;

revoke all on function public.clear_staff_permission_override(uuid, uuid, text) from public, anon;
grant execute on function public.clear_staff_permission_override(uuid, uuid, text) to authenticated;

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

-- Business-table audit trigger. It records only identifiers, state transitions,
-- dates, and monetary totals; contact details, notes, tokens, and credentials are
-- deliberately excluded.
create or replace function private.audit_business_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_old jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
  v_new jsonb := case when tg_op = 'DELETE' then '{}'::jsonb else to_jsonb(new) end;
  v_gym_id uuid;
  v_entity_id uuid;
  v_entity_label text;
  v_entity_type text := tg_table_name;
  v_module text;
  v_action text;
  v_amount numeric;
  v_metadata jsonb := '{}'::jsonb;
  v_member_id uuid;
begin
  v_entity_id := nullif(v_row ->> 'id', '')::uuid;
  v_gym_id := nullif(v_row ->> 'gym_id', '')::uuid;

  if tg_table_name = 'members' then
    v_module := 'members';
    v_entity_type := 'member';
    v_entity_label := trim(coalesce(v_row ->> 'first_name', '') || ' ' || coalesce(v_row ->> 'last_name', ''));
    if tg_op = 'INSERT' then v_action := 'member_created';
    elsif tg_op = 'DELETE' then v_action := 'member_deleted';
    elsif v_old ->> 'status' is distinct from v_new ->> 'status' then
      v_action := case
        when v_new ->> 'status' = 'frozen' then 'member_frozen'
        when v_old ->> 'status' = 'frozen' then 'member_unfrozen'
        when v_new ->> 'status' = 'blocked' then 'member_blocked'
        when v_old ->> 'status' = 'blocked' then 'member_unblocked'
        when v_new ->> 'status' = 'active'
          and v_old ->> 'status' in ('expired', 'cancelled') then 'member_restored'
        else 'member_status_changed'
      end;
      v_metadata := jsonb_build_object('old_status', v_old ->> 'status', 'new_status', v_new ->> 'status');
    else v_action := 'member_edited'; end if;

  elsif tg_table_name = 'membership_plans' then
    v_module := 'memberships'; v_entity_type := 'membership_plan';
    v_entity_label := v_row ->> 'name'; v_amount := nullif(v_row ->> 'price', '')::numeric;
    v_action := case tg_op when 'INSERT' then 'plan_created' when 'DELETE' then 'plan_deleted' else 'plan_edited' end;
    v_metadata := jsonb_build_object('billing_interval', v_row ->> 'billing_interval');

  elsif tg_table_name = 'memberships' then
    v_module := 'memberships'; v_entity_type := 'membership';
    v_member_id := nullif(v_row ->> 'member_id', '')::uuid;
    select m.gym_id, trim(m.first_name || ' ' || coalesce(m.last_name, ''))
      into v_gym_id, v_entity_label from public.members m where m.id = v_member_id;
    v_action := case
      when tg_op = 'INSERT' then 'membership_assigned'
      when tg_op = 'DELETE' then 'membership_deleted'
      when v_new ->> 'status' = 'cancelled' and v_old ->> 'status' is distinct from 'cancelled' then 'membership_cancelled'
      else 'membership_edited'
    end;
    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'member_id', v_member_id, 'plan_id', v_row ->> 'plan_id',
      'status', v_row ->> 'status', 'starts_at', v_row ->> 'starts_at',
      'ends_at', v_row ->> 'ends_at', 'discount_amount', v_row ->> 'discount_amount'
    ));

  elsif tg_table_name = 'invoices' then
    v_module := 'payments'; v_entity_type := 'invoice';
    v_member_id := nullif(v_row ->> 'member_id', '')::uuid;
    select trim(m.first_name || ' ' || coalesce(m.last_name, '')) into v_entity_label
      from public.members m where m.id = v_member_id;
    v_amount := nullif(v_row ->> 'amount', '')::numeric;
    v_action := case tg_op when 'INSERT' then 'invoice_created' when 'DELETE' then 'invoice_deleted' else 'invoice_edited' end;
    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'member_id', v_member_id, 'status', v_row ->> 'status',
      'discount_amount', v_row ->> 'discount_amount', 'due_at', v_row ->> 'due_at'
    ));

  elsif tg_table_name = 'payments' then
    v_module := 'payments'; v_entity_type := 'payment';
    select i.gym_id, i.member_id into v_gym_id, v_member_id
      from public.invoices i where i.id = nullif(v_row ->> 'invoice_id', '')::uuid;
    select trim(m.first_name || ' ' || coalesce(m.last_name, '')) into v_entity_label
      from public.members m where m.id = v_member_id;
    v_amount := nullif(v_row ->> 'amount', '')::numeric;
    v_action := case
      when tg_op = 'INSERT' and v_row ->> 'status' = 'refunded' then 'payment_refunded'
      when tg_op = 'INSERT' then 'payment_collected'
      when tg_op = 'DELETE' then 'payment_deleted'
      when v_new ->> 'status' = 'refunded' and v_old ->> 'status' is distinct from 'refunded' then 'payment_refunded'
      else 'payment_edited'
    end;
    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'member_id', v_member_id, 'invoice_id', v_row ->> 'invoice_id',
      'method', v_row ->> 'method', 'status', v_row ->> 'status'
    ));

  elsif tg_table_name = 'check_ins' then
    v_module := 'attendance'; v_entity_type := 'attendance';
    v_member_id := nullif(v_row ->> 'member_id', '')::uuid;
    select trim(m.first_name || ' ' || coalesce(m.last_name, '')) into v_entity_label
      from public.members m where m.id = v_member_id;
    v_action := case tg_op when 'INSERT' then 'attendance_added' when 'DELETE' then 'attendance_deleted' else 'attendance_edited' end;
    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'member_id', v_member_id, 'checked_in_at', v_row ->> 'checked_in_at',
      'checked_out_at', v_row ->> 'checked_out_at', 'method', v_row ->> 'method',
      'reason', coalesce(
        nullif(current_setting('gymcrm.audit_reason', true), ''),
        v_row ->> 'manual_reason'
      )
    ));

  elsif tg_table_name = 'leads' then
    v_module := 'leads'; v_entity_type := 'lead';
    v_entity_label := trim(coalesce(v_row ->> 'first_name', '') || ' ' || coalesce(v_row ->> 'last_name', ''));
    v_action := case tg_op when 'INSERT' then 'lead_created' when 'DELETE' then 'lead_deleted' else 'lead_edited' end;
    v_metadata := jsonb_build_object('status', v_row ->> 'status', 'source', v_row ->> 'source');

  elsif tg_table_name = 'expenses' then
    v_module := 'expenses'; v_entity_type := 'expense'; v_entity_label := v_row ->> 'category';
    v_amount := nullif(v_row ->> 'amount', '')::numeric;
    v_action := case tg_op when 'INSERT' then 'expense_created' when 'DELETE' then 'expense_deleted' else 'expense_edited' end;
    v_metadata := jsonb_build_object('expense_date', v_row ->> 'expense_date', 'category', v_row ->> 'category');

  elsif tg_table_name = 'profiles' then
    v_module := 'staff'; v_entity_type := 'staff';
    v_entity_label := trim(coalesce(v_row ->> 'first_name', '') || ' ' || coalesce(v_row ->> 'last_name', ''));
    v_action := case tg_op when 'INSERT' then 'staff_created' when 'DELETE' then 'staff_removed' else 'staff_edited' end;
    v_metadata := jsonb_build_object('role', v_row ->> 'role');

  elsif tg_table_name = 'staff_gym_access' then
    v_module := 'staff'; v_entity_type := 'staff_access';
    v_gym_id := nullif(v_row ->> 'gym_id', '')::uuid;
    v_entity_id := nullif(v_row ->> 'profile_id', '')::uuid;
    select trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, ''))
      into v_entity_label from public.profiles p where p.id = v_entity_id;
    v_action := case
      when tg_op = 'INSERT' then 'staff_access_added'
      when tg_op = 'DELETE' then 'staff_access_removed'
      when v_old ->> 'role' is distinct from v_new ->> 'role' then 'staff_role_changed'
      else 'staff_access_edited'
    end;
    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'old_role', v_old ->> 'role', 'new_role', v_new ->> 'role'
    ));
  else
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  perform private.write_activity_log(
    v_gym_id, v_module, v_action, v_entity_type, v_entity_id,
    v_entity_label, v_amount, v_metadata
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'members', 'membership_plans', 'memberships', 'invoices', 'payments',
    'check_ins', 'leads', 'expenses', 'profiles', 'staff_gym_access'
  ] loop
    execute format('drop trigger if exists audit_business_change on public.%I', v_table);
    execute format(
      'create trigger audit_business_change after insert or update or delete on public.%I for each row execute function private.audit_business_change()',
      v_table
    );
  end loop;
end;
$$;

-- Add blocked as an explicit operational state. Existing values are unchanged.
alter table public.members drop constraint if exists members_status_check;
alter table public.members add constraint members_status_check
  check (status in ('active', 'frozen', 'expired', 'cancelled', 'blocked'));

create or replace function private.enforce_member_update_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_other_changes boolean;
  v_billing_only boolean;
begin
  -- Trusted server/cron work has no end-user uid; RLS still blocks anonymous
  -- client writes before they can reach this trigger.
  if auth.uid() is null then return new; end if;

  v_other_changes := (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status');
  v_billing_only :=
    (to_jsonb(new) - array['status', 'next_payment_date', 'billing_interval_months'])
      is not distinct from
    (to_jsonb(old) - array['status', 'next_payment_date', 'billing_interval_months']);

  -- Collection RPCs legitimately advance the renewal schedule. Direct staff
  -- updates never reach this exception because the members UPDATE policy still
  -- requires Members:Edit/Freeze.
  if v_billing_only
     and private.has_gym_permission(old.gym_id, 'payments', 'add')
     and not (
       new.status is distinct from old.status
       and (new.status in ('frozen', 'blocked') or old.status in ('frozen', 'blocked'))
     ) then
    return new;
  end if;
  if v_other_changes and not private.has_gym_permission(old.gym_id, 'members', 'edit') then
    raise exception 'permission_denied';
  end if;
  if new.status is distinct from old.status
     and (new.status in ('frozen', 'blocked') or old.status in ('frozen', 'blocked'))
     and not private.has_gym_permission(old.gym_id, 'members', 'freeze') then
    raise exception 'permission_denied';
  end if;
  if new.status is distinct from old.status
     and new.status not in ('frozen', 'blocked')
     and old.status not in ('frozen', 'blocked')
     and not private.has_gym_permission(old.gym_id, 'members', 'edit') then
    raise exception 'permission_denied';
  end if;
  return new;
end;
$$;

drop trigger if exists members_permission_guard on public.members;
create trigger members_permission_guard
before update on public.members
for each row execute function private.enforce_member_update_permission();

-- Replace broad role-only policies with module/action checks. Member portal
-- access remains intact via auth_member_id()/user_id.
drop policy if exists members_select on public.members;
drop policy if exists members_insert on public.members;
drop policy if exists members_update on public.members;
drop policy if exists members_delete on public.members;
create policy members_select on public.members for select to authenticated
using (user_id = (select auth.uid()) or (select private.has_gym_permission(gym_id, 'members', 'view')));
create policy members_insert on public.members for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'members', 'add')));
create policy members_update on public.members for update to authenticated
using (
  (select private.has_gym_permission(gym_id, 'members', 'edit'))
  or (select private.has_gym_permission(gym_id, 'members', 'freeze'))
)
with check (
  (select private.has_gym_permission(gym_id, 'members', 'edit'))
  or (select private.has_gym_permission(gym_id, 'members', 'freeze'))
);
create policy members_delete on public.members for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'members', 'delete')));

drop policy if exists membership_plans_select on public.membership_plans;
drop policy if exists membership_plans_staff_insert on public.membership_plans;
drop policy if exists membership_plans_staff_update on public.membership_plans;
drop policy if exists membership_plans_staff_delete on public.membership_plans;
create policy membership_plans_select on public.membership_plans for select to authenticated
using (
  (select private.has_gym_permission(gym_id, 'memberships', 'view'))
  or id in (select ms.plan_id from public.memberships ms where ms.member_id = public.auth_member_id())
);
create policy membership_plans_staff_insert on public.membership_plans for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'memberships', 'add')));
create policy membership_plans_staff_update on public.membership_plans for update to authenticated
using ((select private.has_gym_permission(gym_id, 'memberships', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'memberships', 'edit')));
create policy membership_plans_staff_delete on public.membership_plans for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'memberships', 'delete')));

drop policy if exists memberships_select on public.memberships;
drop policy if exists memberships_staff_insert on public.memberships;
drop policy if exists memberships_staff_update on public.memberships;
drop policy if exists memberships_staff_delete on public.memberships;
create policy memberships_select on public.memberships for select to authenticated
using (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m
    where m.id = memberships.member_id
      and private.has_gym_permission(m.gym_id, 'memberships', 'view')
  )
);
create policy memberships_staff_insert on public.memberships for insert to authenticated
with check (exists (
  select 1 from public.members m
  where m.id = memberships.member_id
    and private.has_gym_permission(m.gym_id, 'memberships', 'add')
));
create policy memberships_staff_update on public.memberships for update to authenticated
using (exists (
  select 1 from public.members m
  where m.id = memberships.member_id
    and private.has_gym_permission(m.gym_id, 'memberships', 'edit')
))
with check (exists (
  select 1 from public.members m
  where m.id = memberships.member_id
    and private.has_gym_permission(m.gym_id, 'memberships', 'edit')
));
create policy memberships_staff_delete on public.memberships for delete to authenticated
using (exists (
  select 1 from public.members m
  where m.id = memberships.member_id
    and private.has_gym_permission(m.gym_id, 'memberships', 'delete')
));

drop policy if exists check_ins_select on public.check_ins;
drop policy if exists check_ins_insert on public.check_ins;
drop policy if exists check_ins_update on public.check_ins;
drop policy if exists check_ins_delete on public.check_ins;
create policy check_ins_select on public.check_ins for select to authenticated
using (member_id = public.auth_member_id() or (select private.has_gym_permission(gym_id, 'attendance', 'view')));
create policy check_ins_insert on public.check_ins for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'attendance', 'add')));
create policy check_ins_update on public.check_ins for update to authenticated
using ((select private.has_gym_permission(gym_id, 'attendance', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'attendance', 'edit')));
create policy check_ins_delete on public.check_ins for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'attendance', 'delete')));

drop policy if exists invoices_select on public.invoices;
drop policy if exists invoices_staff_insert on public.invoices;
drop policy if exists invoices_update on public.invoices;
drop policy if exists invoices_staff_delete on public.invoices;
create policy invoices_select on public.invoices for select to authenticated
using (member_id = public.auth_member_id() or (select private.has_gym_permission(gym_id, 'payments', 'view')));
create policy invoices_staff_insert on public.invoices for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'payments', 'add')));
create policy invoices_update on public.invoices for update to authenticated
using ((select private.has_gym_permission(gym_id, 'payments', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'payments', 'edit')));
create policy invoices_staff_delete on public.invoices for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'payments', 'delete')));

drop policy if exists payments_select on public.payments;
drop policy if exists payments_insert on public.payments;
drop policy if exists payments_staff_update on public.payments;
drop policy if exists payments_staff_delete on public.payments;
create policy payments_select on public.payments for select to authenticated
using (exists (
  select 1 from public.invoices i
  where i.id = payments.invoice_id
    and (i.member_id = public.auth_member_id() or private.has_gym_permission(i.gym_id, 'payments', 'view'))
));
create policy payments_insert on public.payments for insert to authenticated
with check (exists (
  select 1 from public.invoices i
  where i.id = payments.invoice_id
    and private.has_gym_permission(i.gym_id, 'payments', 'add')
));
create policy payments_staff_update on public.payments for update to authenticated
using (exists (
  select 1 from public.invoices i
  where i.id = payments.invoice_id
    and private.has_gym_permission(i.gym_id, 'payments', 'edit')
))
with check (exists (
  select 1 from public.invoices i
  where i.id = payments.invoice_id
    and private.has_gym_permission(i.gym_id, 'payments', 'edit')
));
create policy payments_staff_delete on public.payments for delete to authenticated
using (exists (
  select 1 from public.invoices i
  where i.id = payments.invoice_id
    and private.has_gym_permission(i.gym_id, 'payments', 'delete')
));

drop policy if exists gym_isolation_leads on public.leads;
create policy leads_select on public.leads for select to authenticated
using ((select private.has_gym_permission(gym_id, 'leads', 'view')));
create policy leads_insert on public.leads for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'leads', 'add')));
create policy leads_update on public.leads for update to authenticated
using ((select private.has_gym_permission(gym_id, 'leads', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'leads', 'edit')));
create policy leads_delete on public.leads for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'leads', 'delete')));

drop policy if exists staff_view_expenses on public.expenses;
drop policy if exists staff_add_expenses on public.expenses;
drop policy if exists expenses_update on public.expenses;
drop policy if exists owner_delete_expenses on public.expenses;
create policy expenses_select on public.expenses for select to authenticated
using ((select private.has_gym_permission(gym_id, 'expenses', 'view')));
create policy expenses_insert on public.expenses for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'expenses', 'add')));
create policy expenses_update on public.expenses for update to authenticated
using ((select private.has_gym_permission(gym_id, 'expenses', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'expenses', 'edit')));
create policy expenses_delete on public.expenses for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'expenses', 'delete')));

drop policy if exists classes_select on public.classes;
drop policy if exists classes_staff_insert on public.classes;
drop policy if exists classes_staff_update on public.classes;
drop policy if exists classes_staff_delete on public.classes;
create policy classes_select on public.classes for select to authenticated
using (
  (select private.has_gym_permission(gym_id, 'batches', 'view'))
  or id in (select public.member_enrolled_class_ids())
);
create policy classes_staff_insert on public.classes for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'batches', 'add')));
create policy classes_staff_update on public.classes for update to authenticated
using ((select private.has_gym_permission(gym_id, 'batches', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'batches', 'edit')));
create policy classes_staff_delete on public.classes for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'batches', 'delete')));

-- Limit staff/profile discovery to self or users with Staff:View. Contact-data
-- edits to one's own profile remain available; role/gym changes stay protected
-- by the existing profiles_role_guard trigger.
drop policy if exists profiles_own_gym on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or (gym_id is not null and (select private.has_gym_permission(gym_id, 'staff', 'view')))
);
create policy profiles_self_update on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Staff access rows can also be reached through SECURITY DEFINER workflows.
-- Keep those writes aligned with Staff:Add/Edit/Delete while preserving the
-- one-time setup_gym owner bootstrap.
create or replace function private.enforce_staff_access_write_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_gym_id uuid := nullif(v_row ->> 'gym_id', '')::uuid;
  v_profile_id uuid := nullif(v_row ->> 'profile_id', '')::uuid;
  v_target_role text := v_row ->> 'role';
  v_action text := case tg_op when 'INSERT' then 'add' when 'DELETE' then 'delete' else 'edit' end;
begin
  if auth.uid() is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'INSERT'
     and v_profile_id = auth.uid()
     and v_target_role = 'owner'
     and exists (
       select 1 from public.profiles p
       where p.id = auth.uid() and p.gym_id = v_gym_id and p.role = 'owner'
     )
     and not exists (
       select 1 from public.staff_gym_access sga
       where sga.gym_id = v_gym_id and sga.role = 'owner'
     ) then
    return new;
  end if;

  if v_target_role = 'owner' then raise exception 'owner_role_is_locked'; end if;
  if not private.has_gym_permission(v_gym_id, 'staff', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists staff_gym_access_permission_guard on public.staff_gym_access;
create trigger staff_gym_access_permission_guard
before insert or update or delete on public.staff_gym_access
for each row execute function private.enforce_staff_access_write_permission();

-- SECURITY DEFINER business RPCs bypass RLS, so permission checks also live in
-- narrow table triggers. auth.uid() remains the original caller inside those
-- RPCs. Service/cron writes have no end-user uid and are allowed.
create or replace function private.enforce_membership_write_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_gym_id uuid;
  v_action text := case tg_op when 'INSERT' then 'add' when 'DELETE' then 'delete' else 'edit' end;
begin
  if auth.uid() is null then return case when tg_op = 'DELETE' then old else new end; end if;
  select m.gym_id into v_gym_id
  from public.members m where m.id = nullif(v_row ->> 'member_id', '')::uuid;
  if not private.has_gym_permission(v_gym_id, 'memberships', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists memberships_permission_guard on public.memberships;
create trigger memberships_permission_guard
before insert or update or delete on public.memberships
for each row execute function private.enforce_membership_write_permission();

create or replace function private.enforce_payment_write_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_gym_id uuid;
  v_action text := case tg_op when 'INSERT' then 'add' when 'DELETE' then 'delete' else 'edit' end;
begin
  if auth.uid() is null then return case when tg_op = 'DELETE' then old else new end; end if;
  select i.gym_id into v_gym_id
  from public.invoices i where i.id = nullif(v_row ->> 'invoice_id', '')::uuid;
  if not private.has_gym_permission(v_gym_id, 'payments', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists payments_permission_guard on public.payments;
create trigger payments_permission_guard
before insert or update or delete on public.payments
for each row execute function private.enforce_payment_write_permission();

create or replace function private.enforce_check_in_write_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_gym_id uuid := nullif(v_row ->> 'gym_id', '')::uuid;
  v_member_id uuid := nullif(v_row ->> 'member_id', '')::uuid;
  v_action text := case tg_op when 'INSERT' then 'add' when 'DELETE' then 'delete' else 'edit' end;
begin
  if auth.uid() is null then return case when tg_op = 'DELETE' then old else new end; end if;
  if v_member_id = public.auth_member_id() and tg_op in ('INSERT', 'UPDATE') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if not private.has_gym_permission(v_gym_id, 'attendance', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists check_ins_permission_guard on public.check_ins;
create trigger check_ins_permission_guard
before insert or update or delete on public.check_ins
for each row execute function private.enforce_check_in_write_permission();

-- PT maps to workout plans. Member-portal users retain access to their own
-- plans; staff actions are resolved from the member's branch.
drop policy if exists workout_plans_select on public.workout_plans;
drop policy if exists workout_plans_insert on public.workout_plans;
drop policy if exists workout_plans_update on public.workout_plans;
drop policy if exists workout_plans_delete on public.workout_plans;
create policy workout_plans_select on public.workout_plans for select to authenticated
using (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m where m.id = workout_plans.member_id
      and private.has_gym_permission(m.gym_id, 'pt', 'view')
  )
);
create policy workout_plans_insert on public.workout_plans for insert to authenticated
with check (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m where m.id = workout_plans.member_id
      and private.has_gym_permission(m.gym_id, 'pt', 'add')
  )
);
create policy workout_plans_update on public.workout_plans for update to authenticated
using (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m where m.id = workout_plans.member_id
      and private.has_gym_permission(m.gym_id, 'pt', 'edit')
  )
)
with check (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m where m.id = workout_plans.member_id
      and private.has_gym_permission(m.gym_id, 'pt', 'edit')
  )
);
create policy workout_plans_delete on public.workout_plans for delete to authenticated
using (
  member_id = public.auth_member_id()
  or exists (
    select 1 from public.members m where m.id = workout_plans.member_id
      and private.has_gym_permission(m.gym_id, 'pt', 'delete')
  )
);

-- The current Services surface is diet/service programming.
drop policy if exists member_read_diet_plans on public.diet_plans;
drop policy if exists staff_manage_diet_plans on public.diet_plans;
create policy diet_plans_select on public.diet_plans for select to authenticated
using (
  member_id = public.auth_member_id()
  or (select private.has_gym_permission(gym_id, 'services', 'view'))
);
create policy diet_plans_insert on public.diet_plans for insert to authenticated
with check ((select private.has_gym_permission(gym_id, 'services', 'add')));
create policy diet_plans_update on public.diet_plans for update to authenticated
using ((select private.has_gym_permission(gym_id, 'services', 'edit')))
with check ((select private.has_gym_permission(gym_id, 'services', 'edit')));
create policy diet_plans_delete on public.diet_plans for delete to authenticated
using ((select private.has_gym_permission(gym_id, 'services', 'delete')));

-- Batch child rows inherit the permission of their parent class.
drop policy if exists class_sessions_select on public.class_sessions;
drop policy if exists class_sessions_staff_insert on public.class_sessions;
drop policy if exists class_sessions_staff_update on public.class_sessions;
drop policy if exists class_sessions_staff_delete on public.class_sessions;
create policy class_sessions_select on public.class_sessions for select to authenticated
using (
  id in (select b.session_id from public.bookings b where b.member_id = public.auth_member_id())
  or exists (
    select 1 from public.classes c where c.id = class_sessions.class_id
      and private.has_gym_permission(c.gym_id, 'batches', 'view')
  )
);
create policy class_sessions_staff_insert on public.class_sessions for insert to authenticated
with check (exists (
  select 1 from public.classes c where c.id = class_sessions.class_id
    and private.has_gym_permission(c.gym_id, 'batches', 'add')
));
create policy class_sessions_staff_update on public.class_sessions for update to authenticated
using (exists (
  select 1 from public.classes c where c.id = class_sessions.class_id
    and private.has_gym_permission(c.gym_id, 'batches', 'edit')
))
with check (exists (
  select 1 from public.classes c where c.id = class_sessions.class_id
    and private.has_gym_permission(c.gym_id, 'batches', 'edit')
));
create policy class_sessions_staff_delete on public.class_sessions for delete to authenticated
using (exists (
  select 1 from public.classes c where c.id = class_sessions.class_id
    and private.has_gym_permission(c.gym_id, 'batches', 'delete')
));

-- Put the legacy report implementations behind permission-aware wrappers.
-- Their SQL stays byte-for-byte intact; only their callable surface changes.
alter function public.get_revenue_report(uuid, timestamptz, text)
  rename to get_revenue_report_unchecked;
alter function public.get_revenue_report_unchecked(uuid, timestamptz, text)
  set schema private;
revoke all on function private.get_revenue_report_unchecked(uuid, timestamptz, text)
  from public, anon, authenticated;

create function public.get_revenue_report(
  p_gym_id uuid,
  p_from timestamptz,
  p_period text default 'month'
) returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_gym_permission(p_gym_id, 'reports', 'view')
     or not private.has_gym_permission(p_gym_id, 'payments', 'view') then
    raise exception 'permission_denied';
  end if;
  return private.get_revenue_report_unchecked(p_gym_id, p_from, p_period);
end;
$$;
revoke all on function public.get_revenue_report(uuid, timestamptz, text) from public, anon;
grant execute on function public.get_revenue_report(uuid, timestamptz, text) to authenticated;

alter function public.get_member_stats(uuid, integer)
  rename to get_member_stats_unchecked;
alter function public.get_member_stats_unchecked(uuid, integer)
  set schema private;
revoke all on function private.get_member_stats_unchecked(uuid, integer)
  from public, anon, authenticated;

create function public.get_member_stats(
  p_gym_id uuid,
  p_lead_days integer default 30
) returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not private.has_gym_permission(p_gym_id, 'members', 'view') then
    raise exception 'permission_denied';
  end if;
  v_result := to_jsonb(private.get_member_stats_unchecked(p_gym_id, p_lead_days));
  if not private.has_gym_permission(p_gym_id, 'leads', 'view') then
    v_result := v_result - array['leads_total', 'leads_trial', 'leads_converted'];
  end if;
  return v_result::json;
end;
$$;
revoke all on function public.get_member_stats(uuid, integer) from public, anon;
grant execute on function public.get_member_stats(uuid, integer) to authenticated;

-- Gym settings remain owner-updatable through the legacy policy; managers and
-- custom-authorized staff use narrow settings RPCs rather than broad gym-row
-- UPDATE access, preventing billing/secrets changes.
