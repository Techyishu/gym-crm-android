-- Reports redesign: extend get_revenue_report + get_member_stats with the
-- extra metrics the new Reports screen needs (collection rate, ARPM, avg
-- days to pay, payment method mix, dues aging, avg tenure, plan mix, lead
-- conversion). All computed from existing columns — no new tables.
-- Retention/Churn are deliberately NOT added here: they'd need a renewal/
-- cancellation event history we don't track (members.status is a snapshot,
-- not a timeline), so any number would be fabricated.

CREATE OR REPLACE FUNCTION public.get_revenue_report(p_gym_id uuid, p_from timestamp with time zone, p_period text DEFAULT 'month'::text)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT p_from AS win_from, now() AS win_to,
           p_from - (now() - p_from) AS prev_from
  ),
  inv AS (
    SELECT amount, status, created_at, due_at, paid_at
    FROM   public.invoices, bounds
    WHERE  gym_id = p_gym_id
      AND  created_at >= win_from
  ),
  paid AS (
    SELECT amount, COALESCE(paid_at, created_at) AS ts, due_at, paid_at
    FROM   inv
    WHERE  status = 'paid'
  ),
  prev_paid AS (
    SELECT SUM(i.amount) AS revenue
    FROM   public.invoices i, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  i.status = 'paid'
      AND  COALESCE(i.paid_at, i.created_at) >= b.prev_from
      AND  COALESCE(i.paid_at, i.created_at) < b.win_from
  ),
  grouped AS (
    SELECT
      CASE p_period
        WHEN 'year'
          THEN to_char(date_trunc('month', ts), 'YYYY-MM')
        ELSE
          to_char(date_trunc('day',   ts), 'YYYY-MM-DD')
      END AS bucket,
      SUM(amount) AS revenue
    FROM  paid
    GROUP BY 1
  ),
  method_agg AS (
    SELECT p.method, SUM(p.amount) AS amount
    FROM   public.payments p
    JOIN   public.invoices i ON i.id = p.invoice_id, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  p.status = 'succeeded'
      AND  p.created_at >= b.win_from
    GROUP BY p.method
  ),
  aging_bucket AS (
    SELECT
      CASE
        WHEN now() - due_at < interval '8 days'  THEN '0-7'
        WHEN now() - due_at < interval '16 days' THEN '8-15'
        ELSE '15+'
      END AS bucket,
      amount
    FROM public.invoices
    WHERE gym_id = p_gym_id
      AND status = 'open'
      AND due_at IS NOT NULL
      AND due_at <= now()
  ),
  aging_agg AS (
    SELECT bucket, SUM(amount) AS amount
    FROM   aging_bucket
    GROUP BY bucket
  )
  SELECT json_build_object(
    'total_revenue',    COALESCE((SELECT SUM(amount) FROM paid), 0),
    'total_invoices',   (SELECT COUNT(*) FROM inv),
    'paid_count',       (SELECT COUNT(*) FROM paid),
    'failed_count',     (SELECT COUNT(*) FROM inv WHERE status = 'failed'),
    'total_billed',     COALESCE((SELECT SUM(amount) FROM inv), 0),
    'prev_total_revenue', COALESCE((SELECT revenue FROM prev_paid), 0),
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

DROP FUNCTION IF EXISTS public.get_member_stats(uuid);

CREATE OR REPLACE FUNCTION public.get_member_stats(p_gym_id uuid, p_lead_days integer DEFAULT 30)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH mem AS (
    SELECT status, joined_at, billing_interval_months FROM public.members WHERE gym_id = p_gym_id
  ),
  monthly AS (
    SELECT
      to_char(date_trunc('month', joined_at::timestamptz), 'YYYY-MM') AS month_key,
      COUNT(*) AS cnt
    FROM mem
    WHERE joined_at IS NOT NULL
      AND joined_at::timestamptz >= now() - interval '365 days'
    GROUP BY 1
  ),
  plan_agg AS (
    SELECT billing_interval_months, COUNT(*) AS cnt
    FROM   mem
    WHERE  status = 'active' AND billing_interval_months IS NOT NULL
    GROUP BY billing_interval_months
  ),
  leads_window AS (
    SELECT status FROM public.leads
    WHERE gym_id = p_gym_id
      AND created_at >= now() - make_interval(days => p_lead_days)
  )
  SELECT json_build_object(
    'total',       (SELECT COUNT(*)                           FROM mem),
    'active',      (SELECT COUNT(*) FROM mem WHERE status = 'active'),
    'frozen',      (SELECT COUNT(*) FROM mem WHERE status = 'frozen'),
    'expired',     (SELECT COUNT(*) FROM mem WHERE status = 'expired'),
    'cancelled',   (SELECT COUNT(*) FROM mem WHERE status = 'cancelled'),
    'new_last_30d', (SELECT COUNT(*) FROM mem WHERE joined_at IS NOT NULL AND joined_at::timestamptz >= now() - interval '30 days'),
    'avg_tenure_days', (SELECT AVG(EXTRACT(EPOCH FROM (now() - joined_at)) / 86400.0)
                         FROM mem WHERE status = 'active' AND joined_at IS NOT NULL),
    'growth_data', COALESCE(
      (SELECT json_agg(json_build_object('key', month_key, 'count', cnt) ORDER BY month_key)
       FROM   monthly),
      '[]'::json
    ),
    'plan_mix', COALESCE(
      (SELECT json_agg(json_build_object('months', billing_interval_months, 'count', cnt) ORDER BY cnt DESC)
       FROM   plan_agg),
      '[]'::json
    ),
    'leads_total',     (SELECT COUNT(*) FROM leads_window),
    'leads_trial',     (SELECT COUNT(*) FROM leads_window WHERE status = 'trial'),
    'leads_converted', (SELECT COUNT(*) FROM leads_window WHERE status = 'converted')
  );
$function$;
