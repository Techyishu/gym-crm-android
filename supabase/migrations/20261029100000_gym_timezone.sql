-- "Today" was Asia/Kolkata everywhere, so a US or UAE gym's members expired,
-- and back-dated payments/attendance landed, on India's date. Now each gym
-- uses its own zone: gyms.settings->>'timezone' if set, else its country's
-- zone, else Asia/Kolkata — so every Indian gym (and every gym that never
-- picked a country) behaves exactly as before.

-- One zone per country. Countries spanning several zones get the most
-- populous one.
-- ponytail: multi-zone countries (US, CA, AU, BR, MX, RU, ID) use one zone; set settings.timezone per gym if one complains
create or replace function public.country_tz(p_country text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case upper(coalesce(p_country, ''))
    when 'IN' then 'Asia/Kolkata'
    when 'AE' then 'Asia/Dubai'
    when 'SA' then 'Asia/Riyadh'
    when 'QA' then 'Asia/Qatar'
    when 'KW' then 'Asia/Kuwait'
    when 'OM' then 'Asia/Muscat'
    when 'BH' then 'Asia/Bahrain'
    when 'PK' then 'Asia/Karachi'
    when 'BD' then 'Asia/Dhaka'
    when 'NP' then 'Asia/Kathmandu'
    when 'LK' then 'Asia/Colombo'
    when 'MM' then 'Asia/Yangon'
    when 'IR' then 'Asia/Tehran'
    when 'SG' then 'Asia/Singapore'
    when 'MY' then 'Asia/Kuala_Lumpur'
    when 'TH' then 'Asia/Bangkok'
    when 'VN' then 'Asia/Ho_Chi_Minh'
    when 'PH' then 'Asia/Manila'
    when 'ID' then 'Asia/Jakarta'
    when 'GB' then 'Europe/London'
    when 'IE' then 'Europe/Dublin'
    when 'DE' then 'Europe/Berlin'
    when 'FR' then 'Europe/Paris'
    when 'NL' then 'Europe/Amsterdam'
    when 'IT' then 'Europe/Rome'
    when 'ES' then 'Europe/Madrid'
    when 'TR' then 'Europe/Istanbul'
    when 'EG' then 'Africa/Cairo'
    when 'NG' then 'Africa/Lagos'
    when 'KE' then 'Africa/Nairobi'
    when 'ZA' then 'Africa/Johannesburg'
    when 'US' then 'America/New_York'
    when 'CA' then 'America/Toronto'
    when 'MX' then 'America/Mexico_City'
    when 'BR' then 'America/Sao_Paulo'
    when 'AU' then 'Australia/Sydney'
    when 'NZ' then 'Pacific/Auckland'
  end;
$$;

create or replace function public.gym_tz(p_gym_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select coalesce(g.settings->>'timezone', public.country_tz(g.settings->>'country'))
       from public.gyms g where g.id = p_gym_id),
    'Asia/Kolkata'
  );
$$;

revoke execute on function public.gym_tz(uuid) from public;
grant execute on function public.gym_tz(uuid) to authenticated, service_role;

-- Rollback copy: `select def from private.fn_backup_20261029` and run it.
create table if not exists private.fn_backup_20261029 as
  select p.proname::text as proname, pg_get_functiondef(p.oid) as def
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prosrc like '%''Asia/Kolkata''%';

-- Swap the hard-coded zone in the six functions that used it. Each gets the
-- gym id it already has in scope (or looks it up from the invoice/member it
-- was given). Done by text replacement so the rest of each body is untouched.
do $$
declare
  r record;
  v_def text;
begin
  for r in
    select p.oid, p.proname,
      case p.proname
        when 'expire_overdue_members' then 'public.gym_tz(gym_id)'
        when 'record_invoice_payment_atomic' then
          'public.gym_tz((select i.gym_id from public.invoices i where i.id = p_invoice_id))'
        when 'collect_membership_renewal_atomic' then
          'public.gym_tz((select mm.gym_id from public.members mm where mm.id = p_member_id))'
        else 'public.gym_tz(p_gym_id)'
      end as tz_expr
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'expire_overdue_members', 'get_attendance_calendar',
        'upsert_manual_attendance', 'prepare_data_export',
        'record_invoice_payment_atomic', 'collect_membership_renewal_atomic'
      )
      and p.prosrc like '%''Asia/Kolkata''%'
  loop
    v_def := replace(pg_get_functiondef(r.oid), '''Asia/Kolkata''', r.tz_expr);
    execute v_def;
  end loop;
end;
$$;

-- Was 18:30 UTC (= midnight IST) only. Hourly lets every zone expire just
-- after its own midnight; for Indian gyms nothing changes, since their date
-- still only rolls over at the 18:30 run.
select cron.schedule('expire-overdue-members', '30 * * * *', 'SELECT expire_overdue_members();');
