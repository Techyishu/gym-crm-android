-- Two remaining partial-payment gaps in get_revenue_report:
-- 1. total_revenue/chart_data/prev_total_revenue were built from invoices
--    with status='paid', so cash already collected via a partial payment on
--    a still-open invoice was invisible until the final installment landed
--    — understating revenue, and inconsistent with payment_method (which
--    already sums the payments table correctly, so its total could exceed
--    total_revenue). Now sourced from `payments` throughout, matching
--    payment_method's method.
-- 2. dues_aging summed each invoice's full original amount rather than its
--    remaining balance, overstating aging dues for partially-paid invoices.
-- paid_count/avg_days_to_pay are left as invoice-level completion metrics
-- (unaffected — they measure when an invoice was fully settled, not partial
-- cash flow).
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
  collected AS (
    SELECT p.amount, p.created_at AS ts
    FROM   public.payments p
    JOIN   public.invoices i ON i.id = p.invoice_id, bounds b
    WHERE  i.gym_id = p_gym_id
      AND  p.status = 'succeeded'
      AND  p.created_at >= b.win_from
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
          THEN to_char(date_trunc('month', ts), 'YYYY-MM')
        ELSE
          to_char(date_trunc('day',   ts), 'YYYY-MM-DD')
      END AS bucket,
      SUM(amount) AS revenue
    FROM  collected
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
