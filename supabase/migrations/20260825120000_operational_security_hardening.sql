-- Security hardening for money movement, owner notifications, self check-in,
-- and invoice WhatsApp delivery. Deploy this migration before the matching app
-- and edge-function release.

-- Members may read their own invoices/payments, but cannot create a payment or
-- alter invoice status/amount. Staff payment collection goes through the RPC
-- below so the invoice lock, totals and status update are atomic.
drop policy if exists invoices_update on public.invoices;
create policy invoices_update on public.invoices for update to authenticated
using (gym_id = any (auth_gym_ids()))
with check (gym_id = any (auth_gym_ids()));

drop policy if exists payments_insert on public.payments;
create policy payments_insert on public.payments for insert to authenticated
with check (
  invoice_id in (
    select id from public.invoices where gym_id = any (auth_gym_ids())
  )
);

-- Plan catalog and member-plan writes are manager/owner operations. Staff can
-- still read these rows for billing and check-in screens.
drop policy if exists membership_plans_staff_insert on public.membership_plans;
drop policy if exists membership_plans_staff_update on public.membership_plans;
drop policy if exists membership_plans_staff_delete on public.membership_plans;
create policy membership_plans_staff_insert on public.membership_plans for insert to authenticated
with check (
  gym_id = any (auth_gym_ids())
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);
create policy membership_plans_staff_update on public.membership_plans for update to authenticated
using (
  gym_id = any (auth_gym_ids())
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
)
with check (
  gym_id = any (auth_gym_ids())
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);
create policy membership_plans_staff_delete on public.membership_plans for delete to authenticated
using (
  gym_id = any (auth_gym_ids())
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);

drop policy if exists memberships_staff_insert on public.memberships;
drop policy if exists memberships_staff_update on public.memberships;
drop policy if exists memberships_staff_delete on public.memberships;
create policy memberships_staff_insert on public.memberships for insert to authenticated
with check (
  member_id in (select id from public.members where gym_id = any (auth_gym_ids()))
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);
create policy memberships_staff_update on public.memberships for update to authenticated
using (
  member_id in (select id from public.members where gym_id = any (auth_gym_ids()))
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
)
with check (
  member_id in (select id from public.members where gym_id = any (auth_gym_ids()))
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);
create policy memberships_staff_delete on public.memberships for delete to authenticated
using (
  member_id in (select id from public.members where gym_id = any (auth_gym_ids()))
  and exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'manager'))
);

create or replace function public.record_invoice_payment_atomic(
  p_invoice_id uuid,
  p_amount numeric,
  p_method text,
  p_reference_no text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_invoice public.invoices%rowtype;
  v_paid numeric;
  v_remaining numeric;
  v_fully_paid boolean;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and gym_id = any (auth_gym_ids())
  ) then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Payment amount must be greater than zero');
  end if;

  select * into v_invoice from public.invoices where id = p_invoice_id for update;
  if not found or not (v_invoice.gym_id = any (auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Invoice not found');
  end if;
  if v_invoice.status in ('paid', 'void') then
    return jsonb_build_object('ok', false, 'error', 'Invoice cannot accept a payment');
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where invoice_id = v_invoice.id and status = 'succeeded';
  v_remaining := v_invoice.amount - v_paid;
  if p_amount > v_remaining then
    return jsonb_build_object('ok', false, 'error', 'Payment exceeds the remaining invoice balance');
  end if;

  insert into public.payments (invoice_id, amount, method, status, reference_no, notes, recorded_by)
  values (v_invoice.id, p_amount, p_method, 'succeeded', p_reference_no, p_notes, auth.uid());

  v_fully_paid := p_amount = v_remaining;
  update public.invoices
  set status = case when v_fully_paid then 'paid' else 'partial' end,
      paid_at = case when v_fully_paid then now() else paid_at end
  where id = v_invoice.id;

  return jsonb_build_object('ok', true, 'is_fully_paid', v_fully_paid, 'invoice_id', v_invoice.id);
end;
$$;
revoke all on function public.record_invoice_payment_atomic(uuid, numeric, text, text, text) from public;
grant execute on function public.record_invoice_payment_atomic(uuid, numeric, text, text, text) to authenticated;

-- Only a member of the affected gym, staff of that gym, or the service role
-- may create an owner alert. Member-supplied display fields are replaced with
-- their actual record to prevent forged alert content.
create or replace function public.notify_owner_expired_checkin(
  p_gym_id uuid,
  p_member_name text,
  p_member_status text,
  p_method text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_member record;
begin
  if auth.role() <> 'service_role' then
    if auth.uid() is null then
      raise exception 'unauthorized';
    end if;
    if not (p_gym_id = any (auth_gym_ids())) then
      select first_name, last_name, status into v_member
      from public.members where user_id = auth.uid() and gym_id = p_gym_id;
      if not found or v_member.status = 'active' then
        raise exception 'unauthorized';
      end if;
      p_member_name := trim(v_member.first_name || ' ' || coalesce(v_member.last_name, ''));
      p_member_status := v_member.status;
      p_method := 'self-checkin';
    end if;
  end if;

  select id into v_owner_id from public.profiles
  where gym_id = p_gym_id and role = 'owner' limit 1;
  if v_owner_id is null then return; end if;

  insert into public.push_notifications (admin_id, target_user_id, title, body, segment, status, scheduled_at)
  values (null, v_owner_id, 'Blocked check-in attempt',
    p_member_name || ' tried to check in via ' || p_method || ' but their membership is ' || p_member_status || '.',
    'all', 'scheduled', now());
end;
$$;
revoke all on function public.notify_owner_expired_checkin(uuid, text, text, text) from public;
grant execute on function public.notify_owner_expired_checkin(uuid, text, text, text) to authenticated;

-- Frozen membership is not active membership; keep member QR behavior aligned
-- with the manual and biometric check-in flows.
create or replace function public.self_checkin(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid(); v_gym record; v_member record; v_open record;
  v_checked_in timestamptz; v_checked_out timestamptz;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'Not authenticated'); end if;
  select id, name into v_gym from public.gyms where checkin_token::text = p_token limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'Invalid check-in QR code'); end if;
  select id, first_name, last_name, status into v_member from public.members where user_id = v_uid and gym_id = v_gym.id limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'You are not a member of this gym'); end if;
  if v_member.status <> 'active' then
    perform public.notify_owner_expired_checkin(v_gym.id, trim(v_member.first_name || ' ' || coalesce(v_member.last_name, '')), v_member.status, 'self-checkin');
    return jsonb_build_object('ok', false, 'error', 'Membership not active', 'reason', 'Your membership is ' || v_member.status || '. Please contact your gym.');
  end if;
  select id, checked_in_at into v_open from public.check_ins where member_id = v_member.id and gym_id = v_gym.id and checked_out_at is null limit 1;
  if found then
    update public.check_ins set checked_out_at = now() where id = v_open.id returning checked_out_at into v_checked_out;
    return jsonb_build_object('ok', true, 'action', 'checkout', 'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status), 'checked_in_at', v_open.checked_in_at, 'checked_out_at', v_checked_out, 'gym_name', v_gym.name);
  end if;
  insert into public.check_ins (member_id, gym_id, method) values (v_member.id, v_gym.id, 'qr') returning checked_in_at into v_checked_in;
  return jsonb_build_object('ok', true, 'action', 'checkin', 'member', jsonb_build_object('first_name', v_member.first_name, 'last_name', v_member.last_name, 'status', v_member.status), 'checked_in_at', v_checked_in, 'gym_name', v_gym.name);
end;
$$;

-- The edge gateway validates JWTs before entering the function, so the trigger
-- must send a service-role JWT, not a random shared secret. Before applying
-- this migration, store the project's service-role key in Vault as
-- `invoice_whatsapp_service_role_key`.
create or replace function public.notify_invoice_whatsapp()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_secret text;
begin
  if not exists (select 1 from public.gyms where id = new.gym_id and whatsapp_invoice_enabled) then return new; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'invoice_whatsapp_service_role_key';
  if v_secret is null then raise warning 'invoice_whatsapp_service_role_key is not configured'; return new; end if;
  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('invoice_id', new.id)
  );
  return new;
end;
$$;

create or replace function public.notify_invoice_paid_whatsapp()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_secret text;
begin
  if new.status <> 'paid' or old.status is not distinct from 'paid'
     or not exists (select 1 from public.gyms where id = new.gym_id and whatsapp_invoice_enabled) then return new; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'invoice_whatsapp_service_role_key';
  if v_secret is null then raise warning 'invoice_whatsapp_service_role_key is not configured'; return new; end if;
  perform net.http_post(
    url := 'https://orlqjhqxeyukvfzsursl.supabase.co/functions/v1/send-whatsapp-invoice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('invoice_id', new.id, 'event', 'paid')
  );
  return new;
end;
$$;

-- Trigger functions are never client-callable. Postgres grants EXECUTE to
-- PUBLIC by default, so explicitly remove the Data API surface.
revoke all on function public.notify_invoice_whatsapp() from public;
revoke all on function public.notify_invoice_paid_whatsapp() from public;
