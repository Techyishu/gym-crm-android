-- Live Dodo products for the ₹299 Pro plan (created 2026-10-25).
-- Product ids are stored directly; dodo_product_env is cleared so no Vercel
-- env var can override them. pro_299 is NOT made the default here.
insert into public.pricing_plan_terms (plan_code, term, months, price_paise, dodo_product_id, dodo_product_env) values
  ('pro_299', '1mo',  1,  29900,  'pdt_0NqVJ5wd2KZyHDkoCzArP', null),
  ('pro_299', '3mo',  3,  82900,  'pdt_0NqVJE4yiTkkRlZQAeW8S', null),
  ('pro_299', '6mo',  6,  149500, 'pdt_0NqVJL9fwHGbsQ56cFhpT', null),
  ('pro_299', '12mo', 12, 299000, 'pdt_0NqVJXZV408pqxyXNFVQ0', null)
on conflict (plan_code, term) do update
  set months = excluded.months,
      price_paise = excluded.price_paise,
      dodo_product_id = excluded.dodo_product_id,
      dodo_product_env = excluded.dodo_product_env;
