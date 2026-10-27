-- Fields for the photo-card offer popup (all optional):
--   badge      — gold label on the image, e.g. 'LIMITED TIME'
--   price_now  — big price, e.g. '₹2,490'
--   price_was  — struck-out price, e.g. '₹2,990'
-- The "Ends 5 Nov" line comes from ends_at.
alter table public.promotions
  add column if not exists badge text,
  add column if not exists price_now text,
  add column if not exists price_was text,
  add column if not exists dismiss_label text not null default 'Maybe later';
