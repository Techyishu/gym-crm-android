-- create_membership_plan_secure rejected 'biannual' (6 months) with
-- invalid_billing_interval, although the membership_plans table check
-- constraint and the app's plan form both allow it.
CREATE OR REPLACE FUNCTION public.create_membership_plan_secure(
  p_gym_id uuid,
  p_name text,
  p_price numeric,
  p_billing_interval text,
  p_features jsonb DEFAULT '[]'::jsonb,
  p_is_active boolean DEFAULT true,
  p_billing_interval_months integer DEFAULT NULL::integer,
  p_max_classes integer DEFAULT NULL::integer
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_plan public.membership_plans;
  v_months integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'plan_name_required'; end if;
  if p_price is null or p_price <= 0 then raise exception 'invalid_plan_price'; end if;
  if p_billing_interval not in ('monthly', 'quarterly', 'biannual', 'annual', 'custom') then
    raise exception 'invalid_billing_interval';
  end if;
  if jsonb_typeof(coalesce(p_features, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_plan_features';
  end if;
  if jsonb_array_length(coalesce(p_features, '[]'::jsonb)) > 30 then
    raise exception 'too_many_plan_features';
  end if;
  if p_max_classes is not null and p_max_classes <= 0 then
    raise exception 'invalid_max_classes';
  end if;

  v_months := case p_billing_interval
    when 'monthly' then 1
    when 'quarterly' then 3
    when 'biannual' then 6
    when 'annual' then 12
    else p_billing_interval_months
  end;
  if v_months is null or v_months <= 0 then
    raise exception 'invalid_billing_interval_months';
  end if;

  insert into public.membership_plans (
    gym_id, name, price, billing_interval, billing_interval_months,
    features, max_classes, is_active
  ) values (
    p_gym_id, trim(p_name), p_price, p_billing_interval, v_months,
    coalesce(p_features, '[]'::jsonb), p_max_classes, coalesce(p_is_active, true)
  ) returning * into v_plan;

  return to_jsonb(v_plan);
end;
$function$;
