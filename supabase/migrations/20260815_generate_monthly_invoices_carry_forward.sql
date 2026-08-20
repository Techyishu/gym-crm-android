-- Monthly auto-invoice generator, updated for partial payments:
-- 1. The same-day idempotency check now also recognizes 'partial' (previously
--    only 'open'), so it won't create a duplicate invoice for today if
--    today's invoice already has a partial payment on it.
-- 2. Before creating this month's invoice, any still-unpaid balance from
--    PAST invoices (open or partial, due before today) is folded into the
--    new invoice's amount, noted in its description, and the old invoice(s)
--    are closed (status set to 'void') so the balance isn't counted twice.
--    Monthly invoice creation itself is unaffected either way — a member
--    with an outstanding balance still gets a new invoice every month, it
--    just includes what they still owe from before.
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

    -- Outstanding balance from past invoices (before today) that are still
    -- open or partial: amount minus whatever's already been paid on each.
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
