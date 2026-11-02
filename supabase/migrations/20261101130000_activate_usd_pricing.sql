-- Switch on USD pricing for international gyms (country != IN), with only two
-- terms: Monthly $10 and Yearly $100. Indian plans keep 1/3/6/12 months —
-- every statement here touches pro_usd_10 only.
delete from public.pricing_plan_terms where plan_code = 'pro_usd_10' and term in ('3mo', '6mo');

update public.pricing_plan_terms
   set dodo_product_id = 'pdt_0Nr0X4i9BQ0ggt9vpfu8j', dodo_product_env = null
 where plan_code = 'pro_usd_10' and term = '1mo';

update public.pricing_plan_terms
   set dodo_product_id = 'pdt_0Nr0XBpu2g1s6ijiYNa7t', dodo_product_env = null
 where plan_code = 'pro_usd_10' and term = '12mo';

-- Activated here, not via gymcrm.in/admin "make default": that route unsets
-- every 'pro' default regardless of market and would switch off pro_299.
update public.pricing_plans set is_default = true where code = 'pro_usd_10';
