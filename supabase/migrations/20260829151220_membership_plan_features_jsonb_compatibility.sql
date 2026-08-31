-- Backward compatibility for already-installed app versions: PostgREST sends
-- Dart feature lists as JSON arrays. Store the field in its native JSONB form
-- so legacy direct inserts and the new secure RPC both accept the same payload.
-- Existing text[] values are preserved as JSON arrays.
alter table public.membership_plans
  alter column features drop default;
alter table public.membership_plans
  alter column features type jsonb using to_jsonb(features);
alter table public.membership_plans
  alter column features set default '[]'::jsonb;
alter table public.membership_plans
  alter column features set not null;

create or replace function public.create_membership_plan_secure(
  p_gym_id uuid,
  p_name text,
  p_price numeric,
  p_billing_interval text,
  p_features jsonb default '[]'::jsonb,
  p_is_active boolean default true,
  p_billing_interval_months integer default null,
  p_max_classes integer default null
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_plan public.membership_plans;
  v_months integer;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'plan_name_required'; end if;
  if p_price is null or p_price <= 0 then raise exception 'invalid_plan_price'; end if;
  if p_billing_interval not in ('monthly', 'quarterly', 'annual', 'custom') then
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
$$;
