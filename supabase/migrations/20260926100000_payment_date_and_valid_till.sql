-- Editable payment date + valid-till date on collect.
--
-- Both RPCs gain OPTIONAL trailing parameters. When a client leaves them out
-- (every build older than this change) the behaviour is byte-for-byte the same
-- as before: payment stamped now(), next due date = old due date + plan length.
--
--   p_paid_at            date the money was received (India time). Backdated
--                        payments count in that day's reports. Never future.
--   p_next_payment_date  (renewal only) the member's new "valid till" date,
--                        overriding old-due + plan length. Must be after the
--                        payment date. Ignored on partial payments and passes.
--
-- The old signatures are dropped in the same migration so the database never
-- holds two overloads of either function (the ambiguous-call trap, see
-- multi-gym RPC overload bug, 2026-08-24).

drop function if exists public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid);
drop function if exists public.record_invoice_payment_atomic(uuid, numeric, text, text, text);

create function public.collect_membership_renewal_atomic(
  p_member_id uuid,
  p_expected_next_payment_date date,
  p_amount numeric,
  p_method text,
  p_reference_no text default null,
  p_notes text default null,
  p_invoice_id uuid default null,
  p_paid_at date default null,
  p_next_payment_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_member public.members%rowtype;
  v_invoice public.invoices%rowtype;
  v_plan_name text;
  v_plan_price numeric;
  v_discount numeric;
  v_interval_months integer;
  v_invoice_amount numeric;
  v_paid numeric;
  v_remaining numeric;
  v_fully_paid boolean;
  v_next_date date;
  v_has_plan boolean;
  v_is_pass boolean;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_paid_ts timestamptz;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('owner', 'manager', 'staff')
      and gym_id = any (public.auth_gym_ids())
  ) then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  if p_expected_next_payment_date is null then
    return jsonb_build_object('ok', false, 'error', 'The renewal date is missing. Refresh and try again.');
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Payment amount must be greater than zero');
  end if;
  if p_paid_at is not null and p_paid_at > v_today then
    return jsonb_build_object('ok', false, 'error', 'Payment date cannot be in the future');
  end if;
  if p_next_payment_date is not null and p_next_payment_date <= coalesce(p_paid_at, v_today) then
    return jsonb_build_object('ok', false, 'error', 'Valid till must be after the payment date');
  end if;

  -- Today keeps the real time; a backdated payment lands at noon that day.
  v_paid_ts := case
    when p_paid_at is null or p_paid_at = v_today then now()
    else (p_paid_at::text || ' 12:00:00')::timestamp at time zone 'Asia/Kolkata'
  end;

  select * into v_member
  from public.members
  where id = p_member_id
  for update;

  if not found or not (v_member.gym_id = any (public.auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Member not found');
  end if;

  if v_member.next_payment_date is distinct from p_expected_next_payment_date then
    return jsonb_build_object(
      'ok', false,
      'stale', true,
      'error', 'This renewal was already collected or changed. Refreshing the list.'
    );
  end if;

  select mp.name,
         mp.price,
         coalesce(ms.discount_amount, 0),
         coalesce(
           mp.billing_interval_months,
           case lower(mp.billing_interval)
             when 'monthly' then 1
             when 'quarterly' then 3
             when 'biannual' then 6
             when 'annual' then 12
           end,
           v_member.billing_interval_months,
           1
         ),
         (ms.billing_interval_days is not null)
    into v_plan_name, v_plan_price, v_discount, v_interval_months, v_is_pass
  from public.memberships ms
  join public.membership_plans mp on mp.id = ms.plan_id
  where ms.member_id = v_member.id
    and ms.status = 'active'
    and mp.gym_id = v_member.gym_id
  order by ms.starts_at desc nulls last
  limit 1;

  v_has_plan := found;
  v_is_pass := coalesce(v_is_pass, false);
  if not v_has_plan then
    v_plan_name := 'Membership fee';
    v_plan_price := p_amount;
    v_discount := 0;
    v_interval_months := coalesce(v_member.billing_interval_months, 1);
  end if;

  v_invoice_amount := greatest(v_plan_price - v_discount, 0);
  if v_invoice_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'The membership plan has no collectible balance');
  end if;

  select * into v_invoice
  from public.invoices
  where member_id = v_member.id
    and gym_id = v_member.gym_id
    and status in ('open', 'partial')
    and (p_invoice_id is null or id = p_invoice_id)
  order by created_at asc
  limit 1
  for update;

  if not found and p_invoice_id is not null then
    return jsonb_build_object('ok', false, 'stale', true, 'error', 'This invoice is already paid or changed. Refreshing the list.');
  elsif not found then
    if v_is_pass then
      return jsonb_build_object('ok', false, 'error', 'Day passes do not renew. Convert this member to a full plan instead.');
    end if;
    -- A bill raised for a backdated payment is dated with it, so the bill and
    -- its payment fall in the same report period.
    insert into public.invoices (
      gym_id, member_id, amount, original_amount, discount_amount,
      description, due_at, status, created_at
    ) values (
      v_member.gym_id, v_member.id, v_invoice_amount, v_plan_price, v_discount,
      v_plan_name || ' — membership fee', p_expected_next_payment_date, 'open', v_paid_ts
    )
    returning * into v_invoice;
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.payments
  where invoice_id = v_invoice.id
    and status = 'succeeded';

  v_remaining := v_invoice.amount - v_paid;
  if v_remaining <= 0 then
    return jsonb_build_object('ok', false, 'stale', true, 'error', 'This invoice is already paid. Refreshing the list.');
  end if;
  if p_amount > v_remaining then
    return jsonb_build_object('ok', false, 'error', 'Payment exceeds the remaining invoice balance');
  end if;

  insert into public.payments (
    invoice_id, amount, method, status, reference_no, notes, recorded_by, created_at
  ) values (
    v_invoice.id, p_amount, p_method, 'succeeded', p_reference_no, p_notes, auth.uid(), v_paid_ts
  );

  v_fully_paid := p_amount = v_remaining;
  update public.invoices
  set status = case when v_fully_paid then 'paid' else 'partial' end,
      paid_at = case when v_fully_paid then v_paid_ts else paid_at end
  where id = v_invoice.id;

  if v_fully_paid and not v_is_pass then
    v_next_date := coalesce(
      p_next_payment_date,
      (p_expected_next_payment_date + make_interval(months => v_interval_months))::date
    );
    update public.members
    set next_payment_date = v_next_date,
        billing_interval_months = v_interval_months,
        -- A staff-chosen valid-till already in the past (entering an old
        -- renewal late) must not reactivate the member.
        status = case
          when p_next_payment_date is not null and v_next_date < v_today then status
          when status in ('frozen', 'expired') then 'active'
          else status
        end
    where id = v_member.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'is_fully_paid', v_fully_paid,
    'invoice_id', v_invoice.id,
    'next_payment_date', case when v_fully_paid and not v_is_pass then v_next_date else p_expected_next_payment_date end
  );
end;
$function$;

create function public.record_invoice_payment_atomic(
  p_invoice_id uuid,
  p_amount numeric,
  p_method text,
  p_reference_no text default null,
  p_notes text default null,
  p_paid_at date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_invoice public.invoices%rowtype;
  v_paid numeric;
  v_remaining numeric;
  v_fully_paid boolean;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  v_paid_ts timestamptz;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and gym_id = any (auth_gym_ids())
  ) then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Payment amount must be greater than zero');
  end if;
  if p_paid_at is not null and p_paid_at > v_today then
    return jsonb_build_object('ok', false, 'error', 'Payment date cannot be in the future');
  end if;

  v_paid_ts := case
    when p_paid_at is null or p_paid_at = v_today then now()
    else (p_paid_at::text || ' 12:00:00')::timestamp at time zone 'Asia/Kolkata'
  end;

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

  insert into public.payments (invoice_id, amount, method, status, reference_no, notes, recorded_by, created_at)
  values (v_invoice.id, p_amount, p_method, 'succeeded', p_reference_no, p_notes, auth.uid(), v_paid_ts);

  v_fully_paid := p_amount = v_remaining;
  update public.invoices
  set status = case when v_fully_paid then 'paid' else 'partial' end,
      paid_at = case when v_fully_paid then v_paid_ts else paid_at end
  where id = v_invoice.id;

  return jsonb_build_object('ok', true, 'is_fully_paid', v_fully_paid, 'invoice_id', v_invoice.id);
end;
$function$;

-- Same grants the previous versions carried.
revoke all on function public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid, date, date) from public, anon;
grant execute on function public.collect_membership_renewal_atomic(uuid, date, numeric, text, text, text, uuid, date, date) to authenticated, service_role;

revoke all on function public.record_invoice_payment_atomic(uuid, numeric, text, text, text, date) from public;
grant execute on function public.record_invoice_payment_atomic(uuid, numeric, text, text, text, date) to anon, authenticated, service_role;

notify pgrst, 'reload schema';
