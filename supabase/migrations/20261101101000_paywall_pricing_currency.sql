-- get_paywall_pricing: return each plan's billing currency so the paywall
-- shows $ for the USD plan (pricing_plans.currency, added in
-- 20261101100000_intl_pricing_whatsapp_gate). One field added by text
-- replacement; the rest of the body is untouched.
do $$
declare
  v_def text := pg_get_functiondef('public.get_paywall_pricing(text)'::regprocedure);
  v_new text;
begin
  v_new := replace(v_def,
    $x$'monthly_price', (select monthly_price from public.pricing_plans where code = v_code),$x$,
    $x$'monthly_price', (select monthly_price from public.pricing_plans where code = v_code),
      'currency', (select currency from public.pricing_plans where code = v_code),$x$);
  if v_new = v_def then
    raise exception 'get_paywall_pricing: anchor not found';
  end if;
  execute v_new;
end;
$$;
