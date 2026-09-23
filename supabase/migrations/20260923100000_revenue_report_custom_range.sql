-- Custom date range for the Reports > Revenue tab.
--
-- Adds p_to (window end, was always now()) and p_utc_offset_min (the device's
-- UTC offset, so daily/monthly chart buckets follow the gym's local day
-- instead of UTC — a 2 AM IST payment used to land on the previous day).
--
-- Both new params have defaults that reproduce the old behaviour exactly, so
-- app versions still calling with (p_gym_id, p_from, p_period) keep working.
-- The old 3-arg functions are DROPPED in the same migration: leaving them
-- beside the new 4/5-arg ones makes PostgREST fail with "could not choose the
-- best candidate function" for every named-param call (the multi-gym overload
-- trap, 2026-08-24).
--
-- Written from the LIVE definitions (public permission wrapper + private
-- unchecked body), not from 20260815_dues_aging_include_partial.sql, which is
-- stale and lacks the permission check.

begin;

drop function if exists public.get_revenue_report(uuid, timestamptz, text);
drop function if exists private.get_revenue_report_unchecked(uuid, timestamptz, text);

create function private.get_revenue_report_unchecked(
  p_gym_id uuid,
  p_from timestamptz,
  p_period text default 'month',
  p_to timestamptz default null,
  p_utc_offset_min integer default 0
)
returns json
language sql
stable
security definer
set search_path to 'public'
as $function$
  WITH bounds AS (
    SELECT p_from AS win_from,
           COALESCE(p_to, now()) AS win_to,
           p_from - (COALESCE(p_to, now()) - p_from) AS prev_from,
           make_interval(mins => COALESCE(p_utc_offset_min, 0)) AS tz_shift
  ),
  inv AS (
    SELECT amount, status, created_at, due_at, paid_at
    FROM   public.invoices, bounds
    WHERE  gym_id = p_gym_id
      AND  created_at >= win_from
      AND  created_at <  win_to
  ),
  paid AS (
    SELECT amount, COALESCE(paid_at, created_at) AS ts, due_at, paid_at
    FROM   inv
    WHERE  status = 'paid'
  ),
  collected AS (
    SELECT p.amount, p.created_at AS ts
    FROM   public.payments p
    JOIN   public.invoices i ON i.id = p.invoice_id, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  p.status = 'succeeded'
      AND  p.created_at >= b.win_from
      AND  p.created_at <  b.win_to
  ),
  prev_collected AS (
    SELECT SUM(p.amount) AS revenue
    FROM   public.payments p
    JOIN   public.invoices i ON i.id = p.invoice_id, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  p.status = 'succeeded'
      AND  p.created_at >= b.prev_from
      AND  p.created_at < b.win_from
  ),
  grouped AS (
    SELECT
      CASE p_period
        WHEN 'year'
          THEN to_char(date_trunc('month', (c.ts AT TIME ZONE 'UTC') + b.tz_shift), 'YYYY-MM')
        ELSE
          to_char(date_trunc('day',   (c.ts AT TIME ZONE 'UTC') + b.tz_shift), 'YYYY-MM-DD')
      END AS bucket,
      SUM(c.amount) AS revenue
    FROM  collected c, bounds b
    GROUP BY 1
  ),
  method_agg AS (
    SELECT p.method, SUM(p.amount) AS amount
    FROM   public.payments p
    JOIN   public.invoices i ON i.id = p.invoice_id, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  p.status = 'succeeded'
      AND  p.created_at >= b.win_from
      AND  p.created_at <  b.win_to
    GROUP BY p.method
  ),
  aging_bucket AS (
    SELECT
      CASE
        WHEN now() - inv.due_at < interval '8 days'  THEN '0-7'
        WHEN now() - inv.due_at < interval '16 days' THEN '8-15'
        ELSE '15+'
      END AS bucket,
      GREATEST(inv.amount - COALESCE(paid.total, 0), 0) AS amount
    FROM public.invoices inv
    LEFT JOIN LATERAL (
      SELECT SUM(p.amount) AS total FROM public.payments p
       WHERE p.invoice_id = inv.id AND p.status = 'succeeded'
    ) paid ON true
    WHERE inv.gym_id = p_gym_id
      AND inv.status IN ('open', 'partial')
      AND inv.due_at IS NOT NULL
      AND inv.due_at <= now()
  ),
  aging_agg AS (
    SELECT bucket, SUM(amount) AS amount
    FROM   aging_bucket
    GROUP BY bucket
  )
  SELECT json_build_object(
    'total_revenue',    COALESCE((SELECT SUM(amount) FROM collected), 0),
    'total_invoices',   (SELECT COUNT(*) FROM inv),
    'paid_count',       (SELECT COUNT(*) FROM paid),
    'partial_count',    (SELECT COUNT(*) FROM inv WHERE status = 'partial'),
    'failed_count',     (SELECT COUNT(*) FROM inv WHERE status = 'failed'),
    'total_billed',     COALESCE((SELECT SUM(amount) FROM inv), 0),
    'prev_total_revenue', COALESCE((SELECT revenue FROM prev_collected), 0),
    'active_members',   (SELECT COUNT(*) FROM public.members WHERE gym_id = p_gym_id AND status = 'active'),
    'avg_days_to_pay',  (SELECT AVG(EXTRACT(EPOCH FROM (paid_at - due_at)) / 86400.0)
                          FROM paid WHERE due_at IS NOT NULL AND paid_at IS NOT NULL),
    'chart_data',       COALESCE(
      (SELECT json_agg(json_build_object('key', bucket, 'value', revenue) ORDER BY bucket)
       FROM   grouped),
      '[]'::json
    ),
    'payment_method',   COALESCE(
      (SELECT json_agg(json_build_object('method', method, 'amount', amount) ORDER BY amount DESC)
       FROM   method_agg),
      '[]'::json
    ),
    'dues_aging',       COALESCE(
      (SELECT json_agg(json_build_object('bucket', bucket, 'amount', amount)
                        ORDER BY CASE bucket WHEN '0-7' THEN 1 WHEN '8-15' THEN 2 ELSE 3 END)
       FROM   aging_agg),
      '[]'::json
    )
  );
$function$;

create function public.get_revenue_report(
  p_gym_id uuid,
  p_from timestamptz,
  p_period text default 'month',
  p_to timestamptz default null,
  p_utc_offset_min integer default 0
)
returns json
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not private.has_gym_permission(p_gym_id, 'reports', 'view')
     or not private.has_gym_permission(p_gym_id, 'payments', 'view') then
    raise exception 'permission_denied';
  end if;
  if p_to is not null and p_to <= p_from then
    raise exception 'invalid_range';
  end if;
  return private.get_revenue_report_unchecked(p_gym_id, p_from, p_period, p_to, p_utc_offset_min);
end;
$function$;

-- Same grants as before: private callable only by owner/service_role, public
-- wrapper by authenticated. New functions get EXECUTE for PUBLIC by default.
revoke all on function private.get_revenue_report_unchecked(uuid, timestamptz, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function private.get_revenue_report_unchecked(uuid, timestamptz, text, timestamptz, integer) to service_role;

revoke all on function public.get_revenue_report(uuid, timestamptz, text, timestamptz, integer) from public, anon;
grant execute on function public.get_revenue_report(uuid, timestamptz, text, timestamptz, integer) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
