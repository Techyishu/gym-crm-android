-- FCM device tokens, replacing OneSignal's external_id mapping.
-- The app calls register_device_token() after sign-in; edge functions read
-- this table with the service role via _shared/fcm.ts and prune tokens FCM
-- reports as invalid. RLS is on with no policies: clients never touch the
-- table directly, only through the RPC.

create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios')),
  updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_id_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Upsert keyed on token so a device that switches accounts is re-pointed at
-- the new user instead of staying with the old one.
create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if coalesce(p_token, '') = '' then
    raise exception 'token required';
  end if;

  insert into public.device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
