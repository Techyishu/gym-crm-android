-- Perf fix for 20261029100000_gym_timezone: that swap called
-- public.gym_tz(p_gym_id) inside row filters, i.e. once per row (~0.2 ms
-- each — SECURITY DEFINER functions can't be inlined). The busiest gym's
-- month of check-ins went from 24 ms to 3.3 s. The zone is the same for every
-- row of a call, so look it up once into v_tz.
--
-- record_invoice_payment_atomic / collect_membership_renewal_atomic only call
-- it twice per call, outside any row loop — left as they are.

do $$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid, p.proname from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('get_attendance_calendar', 'upsert_manual_attendance', 'prepare_data_export')
  loop
    v_def := pg_get_functiondef(r.oid);
    if position('public.gym_tz(p_gym_id)' in v_def) = 0 then
      raise exception '%: gym_tz call not found', r.proname;
    end if;
    v_new := replace(v_def, 'public.gym_tz(p_gym_id)', 'v_tz');
    -- First declaration, so later defaults (upsert's v_today) can use it.
    v_new := regexp_replace(v_new, E'\\ndeclare\\n',
      E'\ndeclare\n  v_tz text := public.gym_tz(p_gym_id);\n');
    if position('v_tz text := public.gym_tz(p_gym_id)' in v_new) = 0 then
      raise exception '%: declare block not found', r.proname;
    end if;
    execute v_new;
  end loop;
end;
$$;

-- All gyms at once: join gyms and use the inlinable country_tz instead of a
-- gym_tz call per member row. Same zone rule as gym_tz.
create or replace function public.expire_overdue_members()
returns integer
language plpgsql
security definer
as $$
declare
  updated_count integer;
begin
  update members m
     set status = 'expired'
    from gyms g
   where g.id = m.gym_id
     and m.status = 'active'
     and m.next_payment_date is not null
     and m.next_payment_date < (now() at time zone coalesce(
           g.settings->>'timezone',
           public.country_tz(g.settings->>'country'),
           'Asia/Kolkata'))::date;

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;
