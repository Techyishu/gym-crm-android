-- Member deletion cascades through memberships, invoices/payments, and
-- check-ins. The normal child-table permission triggers cannot always resolve
-- the parent after PostgreSQL has begun the cascade, so they rejected an
-- otherwise-authorized member delete. This RPC verifies Members:Delete once
-- and marks only that transaction as an approved member cascade.

create or replace function private.secure_member_delete_context(
  p_member_id uuid default null
) returns boolean
language sql
stable
set search_path = ''
as $$
  select auth.uid() is not null
    and nullif(current_setting('gymcrm.delete_actor_id', true), '')::uuid
      = auth.uid()
    and (
      p_member_id is null
      or nullif(current_setting('gymcrm.delete_member_id', true), '')::uuid
        = p_member_id
    );
$$;

revoke all on function private.secure_member_delete_context(uuid)
  from public, anon, authenticated;

create or replace function private.enforce_membership_write_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_member_id uuid := nullif(v_row ->> 'member_id', '')::uuid;
  v_gym_id uuid;
  v_action text := case tg_op when 'INSERT' then 'add' when 'DELETE' then 'delete' else 'edit' end;
begin
  if auth.uid() is null then return case when tg_op = 'DELETE' then old else new end; end if;
  if tg_op = 'DELETE' and private.secure_member_delete_context(v_member_id) then
    return old;
  end if;
  select m.gym_id into v_gym_id from public.members m where m.id = v_member_id;
  if not private.has_gym_permission(v_gym_id, 'memberships', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

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
  if tg_op = 'DELETE' and private.secure_member_delete_context() then
    return old;
  end if;
  select i.gym_id into v_gym_id
  from public.invoices i where i.id = nullif(v_row ->> 'invoice_id', '')::uuid;
  if not private.has_gym_permission(v_gym_id, 'payments', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

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
  if tg_op = 'DELETE' and private.secure_member_delete_context(v_member_id) then
    return old;
  end if;
  if v_member_id = public.auth_member_id() and tg_op in ('INSERT', 'UPDATE') then
    return new;
  end if;
  if not private.has_gym_permission(v_gym_id, 'attendance', v_action) then
    raise exception 'permission_denied';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.delete_member_secure(p_member_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gym_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;

  select m.gym_id into v_gym_id
  from public.members m
  where m.id = p_member_id;

  if v_gym_id is null then raise exception 'member_not_found'; end if;
  if not private.has_gym_permission(v_gym_id, 'members', 'delete') then
    raise exception 'permission_denied';
  end if;

  perform set_config('gymcrm.delete_actor_id', auth.uid()::text, true);
  perform set_config('gymcrm.delete_member_id', p_member_id::text, true);

  delete from public.members where id = p_member_id;

  perform set_config('gymcrm.delete_actor_id', '', true);
  perform set_config('gymcrm.delete_member_id', '', true);
  return true;
end;
$$;

revoke all on function public.delete_member_secure(uuid) from public, anon;
grant execute on function public.delete_member_secure(uuid) to authenticated;
