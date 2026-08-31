-- Old app builds still call DELETE /rest/v1/members directly instead of the
-- delete_member_secure RPC added in 20260828112025. That raw delete cascades
-- to memberships/payments/check_ins, whose permission-guard triggers look up
-- the parent member row to resolve gym_id -- but by the time they fire, the
-- cascade has already removed it, so gym_id resolves to null and every
-- cascade child delete is rejected with permission_denied, rolling back the
-- whole member delete. This trigger sets the same session flags
-- delete_member_secure sets, so a direct client-side delete is also treated
-- as an approved cascade, without requiring an app update.

create or replace function private.mark_member_delete_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null
     and private.has_gym_permission(old.gym_id, 'members', 'delete') then
    perform set_config('gymcrm.delete_actor_id', auth.uid()::text, true);
    perform set_config('gymcrm.delete_member_id', old.id::text, true);
  end if;
  return old;
end;
$$;

drop trigger if exists members_mark_delete_context on public.members;
create trigger members_mark_delete_context
before delete on public.members
for each row execute function private.mark_member_delete_context();
