-- Day passes: short (1-29 day), NON-renewing plans.
--
-- A pass is a normal membership_plans row with billing_interval = 'custom',
-- billing_interval_months = NULL and billing_interval_days = N. The assignment
-- copies N onto memberships.billing_interval_days, and that copy is what marks
-- a membership as a pass: no renewal invoice, no renewal date advance.
-- Converting a pass member to a monthly/yearly plan goes through the normal
-- change_member_plan, which cancels the pass row and inserts the new one.
--
-- Everything here is additive. Existing rows keep NULL in both new columns and
-- behave exactly as before.

-- ── Columns ──────────────────────────────────────────────────────────────────

alter table public.membership_plans
  add column if not exists billing_interval_days integer;

alter table public.membership_plans
  drop constraint if exists membership_plans_billing_interval_days_check;
alter table public.membership_plans
  add constraint membership_plans_billing_interval_days_check check (
    billing_interval_days is null
    or (
      billing_interval_days between 1 and 29
      and billing_interval = 'custom'
      and billing_interval_months is null
    )
  );

alter table public.memberships
  add column if not exists billing_interval_days integer;

alter table public.memberships
  drop constraint if exists memberships_billing_interval_days_check;
alter table public.memberships
  add constraint memberships_billing_interval_days_check check (
    billing_interval_days is null or billing_interval_days between 1 and 29
  );

-- ── Old app builds must not silently mis-date a pass ─────────────────────────
-- Builds that predate this change compute renewal dates in months. Any direct
-- membership insert for a pass plan has to carry the days marker; old builds
-- don't send it, so they get a clear error instead of a wrong date.

create or replace function public.require_day_pass_marker()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.billing_interval_days is null and exists (
    select 1
    from public.membership_plans p
    where p.id = new.plan_id
      and p.billing_interval_days is not null
  ) then
    raise exception 'app_update_required';
  end if;
  return new;
end;
$function$;

revoke all on function public.require_day_pass_marker() from public, anon, authenticated;

drop trigger if exists memberships_day_pass_marker on public.memberships;
create trigger memberships_day_pass_marker
before insert on public.memberships
for each row execute function public.require_day_pass_marker();

-- ── change_member_plan: copy the pass marker onto the new membership ─────────
-- One extra defaulted parameter. The old 6-argument signature is dropped in
-- the same transaction so PostgREST never sees two overloads; old clients keep
-- calling with 6 named arguments and resolve to this function.

drop function if exists public.change_member_plan(uuid, uuid, timestamptz, numeric, date, integer);

create function public.change_member_plan(
  p_member_id uuid,
  p_plan_id uuid,
  p_starts_at timestamp with time zone,
  p_discount_amount numeric,
  p_next_payment_date date,
  p_billing_interval_months integer,
  p_billing_interval_days integer default null
)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_member_gym_id uuid;
  v_plan_days integer;
begin
  if auth.uid() is null then
    raise exception 'unauthorized: not staff';
  end if;

  select gym_id into v_member_gym_id from members where id = p_member_id;

  if v_member_gym_id is null or not (v_member_gym_id = any (auth_gym_ids())) then
    raise exception 'member_not_in_gym';
  end if;

  select billing_interval_days into v_plan_days
    from membership_plans
   where id = p_plan_id and gym_id = v_member_gym_id;

  if not found then
    raise exception 'plan_not_in_gym';
  end if;

  -- A pass plan needs a client that knows how to date it.
  if v_plan_days is not null and p_billing_interval_days is distinct from v_plan_days then
    raise exception 'app_update_required';
  end if;

  update memberships
     set status = 'cancelled', cancelled_at = now()
   where member_id = p_member_id and status = 'active';

  insert into memberships (member_id, plan_id, status, starts_at, ends_at, discount_amount, billing_interval_days)
  values (p_member_id, p_plan_id, 'active', p_starts_at, null, coalesce(p_discount_amount, 0), v_plan_days);

  update members
     set next_payment_date = p_next_payment_date,
         billing_interval_months = p_billing_interval_months,
         status = case when status in ('expired', 'cancelled') then 'active' else status end
   where id = p_member_id;
end;
$function$;

revoke all on function public.change_member_plan(uuid, uuid, timestamptz, numeric, date, integer, integer) from public, anon;
grant execute on function public.change_member_plan(uuid, uuid, timestamptz, numeric, date, integer, integer) to authenticated, service_role;

-- ── generate_monthly_invoices: passes never get a renewal invoice ────────────
-- Same body as before; the only change is `ms.billing_interval_days is null`
-- in the plan lookup, so a pass member falls into the existing "no plan ->
-- skipped" branch.

create or replace function public.generate_monthly_invoices()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_today      date        := current_date;
  v_today_ts   timestamptz := (current_date::text || 'T00:00:00Z')::timestamptz;
  v_created    int         := 0;
  v_skipped    int         := 0;
  v_member     record;
  v_plan_name  text;
  v_plan_price numeric;
  v_discount   numeric;
  v_amount     numeric;
  v_exists     boolean;
  v_carried_due numeric;
  v_old_ids    uuid[];
  v_new_id     uuid;
  v_description text;
begin
  for v_member in
    select m.id, m.gym_id
    from   members m
    where  m.next_payment_date = v_today
      and  m.status <> 'cancelled'
  loop
    select mp.name, mp.price, ms.discount_amount
      into v_plan_name, v_plan_price, v_discount
      from memberships ms
      join membership_plans mp on mp.id = ms.plan_id
     where ms.member_id = v_member.id
       and ms.status    = 'active'
       and ms.billing_interval_days is null
     limit 1;

    if not found then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    select exists(
      select 1 from invoices
       where member_id = v_member.id
         and gym_id    = v_member.gym_id
         and status    in ('open', 'partial')
         and due_at    = v_today_ts
    ) into v_exists;

    if v_exists then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    select coalesce(sum(inv.amount - coalesce(paid.total, 0)), 0), array_agg(inv.id)
      into v_carried_due, v_old_ids
      from invoices inv
      left join lateral (
        select sum(p.amount) as total from payments p
         where p.invoice_id = inv.id and p.status = 'succeeded'
      ) paid on true
     where inv.member_id = v_member.id
       and inv.gym_id    = v_member.gym_id
       and inv.status    in ('open', 'partial')
       and inv.due_at    < v_today_ts;

    v_amount := greatest(v_plan_price - coalesce(v_discount, 0), 0) + coalesce(v_carried_due, 0);

    v_description := v_plan_name || ' — membership fee';
    if coalesce(v_carried_due, 0) > 0 then
      v_description := v_description || ' (includes ' || trim(to_char(v_carried_due, 'FM999999990.00')) || ' due from last month)';
    end if;

    insert into invoices (gym_id, member_id, amount, original_amount, discount_amount, description, due_at, status)
    values (
      v_member.gym_id,
      v_member.id,
      v_amount,
      v_plan_price,
      coalesce(v_discount, 0),
      v_description,
      v_today_ts,
      'open'
    )
    returning id into v_new_id;

    if v_old_ids is not null then
      update invoices
         set status = 'void',
             notes  = trim(both ' ' from coalesce(notes, '') || ' Balance carried forward to invoice ' || v_new_id)
       where id = any(v_old_ids);
    end if;

    v_created := v_created + 1;
  end loop;

  return jsonb_build_object(
    'created', v_created,
    'skipped', v_skipped,
    'date',    v_today::text
  );
end;
$function$;

-- ── collect_membership_renewal_atomic: passes don't renew ────────────────────
-- Same body as before plus v_is_pass: no new renewal invoice is minted for a
-- pass, and paying an existing pass invoice never moves next_payment_date.

create or replace function public.collect_membership_renewal_atomic(
  p_member_id uuid,
  p_expected_next_payment_date date,
  p_amount numeric,
  p_method text,
  p_reference_no text default null::text,
  p_notes text default null::text,
  p_invoice_id uuid default null::uuid
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
    -- No linked plan (legacy member) — bill exactly what staff entered.
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
    insert into public.invoices (
      gym_id, member_id, amount, original_amount, discount_amount,
      description, due_at, status
    ) values (
      v_member.gym_id, v_member.id, v_invoice_amount, v_plan_price, v_discount,
      v_plan_name || ' — membership fee', p_expected_next_payment_date, 'open'
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
    invoice_id, amount, method, status, reference_no, notes, recorded_by
  ) values (
    v_invoice.id, p_amount, p_method, 'succeeded', p_reference_no, p_notes, auth.uid()
  );

  v_fully_paid := p_amount = v_remaining;
  update public.invoices
  set status = case when v_fully_paid then 'paid' else 'partial' end,
      paid_at = case when v_fully_paid then now() else paid_at end
  where id = v_invoice.id;

  if v_fully_paid and not v_is_pass then
    v_next_date := (p_expected_next_payment_date + make_interval(months => v_interval_months))::date;
    update public.members
    set next_payment_date = v_next_date,
        billing_interval_months = v_interval_months,
        status = case when status in ('frozen', 'expired') then 'active' else status end
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

-- ── record_invoice_payment: paying a pass invoice never advances the date ────

create or replace function public.record_invoice_payment(
  p_invoice_id uuid,
  p_method text,
  p_reference_no text default null::text,
  p_notes text default null::text,
  p_advance_date boolean default true
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid       uuid := auth.uid();
  v_invoice   record;
  v_member    record;
  v_interval_months integer;
  v_is_pass   boolean;
  v_next_date date;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Not authorized');
  end if;

  select id, amount, status, member_id, gym_id into v_invoice
  from invoices
  where id = p_invoice_id;

  if not found or v_invoice.gym_id is null or not (v_invoice.gym_id = any (auth_gym_ids())) then
    return jsonb_build_object('ok', false, 'error', 'Invoice not found');
  end if;
  if v_invoice.status = 'paid' then
    return jsonb_build_object('ok', false, 'error', 'Invoice already paid');
  end if;

  insert into payments (invoice_id, amount, method, status, reference_no, notes, recorded_by)
  values (v_invoice.id, v_invoice.amount, p_method, 'succeeded', p_reference_no, p_notes, v_uid);

  update invoices set status = 'paid', paid_at = now() where id = v_invoice.id;

  select next_payment_date, status, billing_interval_months into v_member
  from members where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  select coalesce(
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
    into v_interval_months, v_is_pass
  from memberships ms
  join membership_plans mp on mp.id = ms.plan_id
  where ms.member_id = v_invoice.member_id
    and ms.status = 'active'
    and mp.gym_id = v_invoice.gym_id
  order by ms.starts_at desc nulls last
  limit 1;

  v_interval_months := coalesce(v_interval_months, v_member.billing_interval_months, 1);
  v_is_pass := coalesce(v_is_pass, false);

  if p_advance_date and not v_is_pass and v_member.next_payment_date is not null then
    v_next_date := (v_member.next_payment_date + make_interval(months => v_interval_months))::date;
  end if;

  update members
  set next_payment_date = coalesce(v_next_date, next_payment_date),
      billing_interval_months = v_interval_months,
      status = case when not v_is_pass and status in ('frozen', 'expired') then 'active' else status end
  where id = v_invoice.member_id and gym_id = v_invoice.gym_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice.id);
end;
$function$;
