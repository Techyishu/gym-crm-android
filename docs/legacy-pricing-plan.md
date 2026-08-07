# Legacy pricing rollout — grandfather 40 gyms at ₹249/mo

Status: plan, not yet executed. Date: 2026-08-06.

Goal: raise Pro price for new customers while 40 existing paying gyms keep
₹249/mo permanently, including after cancel-and-resubscribe.

Cohorts: 10 on Dodo recurring, ~3 on Apple StoreKit, ~27 manual UPI/QR with
hand-granted Pro access and no subscription object.

---

## What surfaces change

This is **not** a DB-only change. Four separate places, two of which are
outside this repo.

| Surface | What changes | In this repo? |
|---|---|---|
| **Supabase DB** | 2 columns, backfill, protective trigger, audit rows | migrations only |
| **Flutter app** | price display, offering selection, settings row | yes — all Dart |
| **Web repo (`gym-crm`)** | checkout price routing, Dodo webhook | **no** |
| **Dodo + RevenueCat + App Store Connect** | new products/offerings | **no** — dashboards |

The Flutter changes are pure Dart, so Android can ship as a Shorebird patch
with no store release. iOS is not covered by the current `shorebird patch
android` workflow — assume a full App Store release for the iOS half.

---

## Phase 0 — verify before changing anything

No writes in this phase. Each item can invalidate the plan below.

1. **Audit RLS on `gyms`.** The app updates `gyms` directly from the client
   (`settings_screen.dart:936`, `:1503`, `reminders_screen.dart:234`, `:430`),
   so owners have UPDATE rights on their own row. Policies are not in
   `supabase/migrations/` — pull them from the dashboard and check whether a
   client can write `plan_expires_at`, `plan`, `status`, or `plan_price`.
   If yes, that is a live billing bypass today, independent of this work.
2. **Dodo price binding.** Does an active subscription bill from a frozen
   price captured at signup, or read the product's current price at renewal?
   Determines whether editing the old product would silently reprice the 10.
   Do not assume — confirm in Dodo's docs or dashboard.
3. **Trace the Dodo webhook** in the web repo. If it writes `plan_price` from
   Dodo's current price on every renewal event, it will overwrite the
   grandfathered value and silently un-grandfather people.
4. **Confirm the admin panel and webhook use the service role key**, not an
   authenticated user session. Phase 1's trigger will block them otherwise.

---

## Phase 1 — database

Migration: `supabase/migrations/20260806_legacy_pricing.sql`

### 1a. Columns

```sql
alter table gyms add column legacy_pricing boolean not null default false;
alter table gyms add column price_locked_at timestamptz;
```

Default `false` means this step changes nothing for anyone. Safe to ship alone.

`legacy_pricing` is the single source of truth. `price_locked_at` is audit
only, never load-bearing. Actual amount lives in the existing `plan_price`.

### 1b. Dry-run — review by hand

```sql
select id, name, plan, plan_price, dodo_subscription_id, apple_subscription_id,
       plan_expires_at, trial_ends_at, status, is_demo, created_at
from gyms
where not coalesce(is_demo, false)
  and plan = 'pro'
  and (dodo_subscription_id is not null
       or apple_subscription_id is not null
       or plan_expires_at is not null)
order by created_at;
```

Read every row. Remove: freebies granted as Pro, internal/test gyms, anyone
who never actually paid. Name-matching for test accounts is unreliable
(`%test%` matches "Latest") — use your eyes, not a WHERE clause.

### 1c. Backfill — explicit ids, per-gym price

```sql
update gyms set legacy_pricing = true, price_locked_at = now(), plan_price = 249
where id in (/* reviewed ids paying 249 */);

update gyms set legacy_pricing = true, price_locked_at = now(), plan_price = 500
where id in (/* the gym(s) actually paying 500 */);
```

Do **not** blanket-set `plan_price = 249`. At least one customer pays ₹500;
overwriting them creates a billing discrepancy you'll discover awkwardly.

### 1d. Audit trail

Reuse the existing `activity_events` table — no new schema:

```sql
insert into activity_events (gym_id, action, metadata)
select id, 'pricing_grandfathered',
       jsonb_build_object('price', plan_price, 'granted_by', 'manual_backfill_20260806')
from gyms where legacy_pricing = true;
```

### 1e. Lock billing columns (run last)

RLS is row-level and cannot restrict columns. Use a trigger:

```sql
create or replace function protect_gym_billing_columns()
returns trigger language plpgsql security definer as $$
begin
  if auth.role() = 'authenticated' then
    if new.legacy_pricing        is distinct from old.legacy_pricing
    or new.plan_price            is distinct from old.plan_price
    or new.plan                  is distinct from old.plan
    or new.plan_expires_at       is distinct from old.plan_expires_at
    or new.trial_ends_at         is distinct from old.trial_ends_at
    or new.status                is distinct from old.status
    or new.dodo_subscription_id  is distinct from old.dodo_subscription_id
    or new.apple_subscription_id is distinct from old.apple_subscription_id then
      raise exception 'billing columns are not client-writable';
    end if;
  end if;
  return new;
end $$;

create trigger gyms_protect_billing
before update on gyms
for each row execute function protect_gym_billing_columns();
```

Runs after backfill so the migration itself isn't blocked. Migrations run as
`postgres`, not `authenticated`, so they pass through regardless.

**Test immediately after**: log in as a normal gym owner, try to PATCH
`plan_expires_at`. It must fail. Then confirm settings/reminders screens still
save normally.

---

## Phase 2 — external dashboards

No user-visible impact yet.

- **Dodo**: create a NEW Product at the new price. Leave the ₹249 product
  completely untouched — never edit its price. This is safe whether or not
  Dodo pins price per-subscription, so it doesn't block on Phase 0 item 2.
- **App Store Connect**: create a new subscription product at the new price
  inside the same subscription group. Do not touch the existing product's
  price. Apple grandfathers existing subscribers automatically.
- **RevenueCat**: create a `legacy_pro` Offering pointing at the OLD App Store
  product. Keep it OUT of `current` so new users never see it. Point `current`
  at the new product.

---

## Phase 3 — web repo (`gym-crm`)

**Must ship before any price is raised anywhere.** If the app shows a new
price while checkout still bills the old product (or vice versa), you get
mismatched charges and refund requests.

- Checkout endpoint (`/api/billing/mobile/checkout`): read `legacy_pricing`
  fresh from the `gyms` row on every call. If true, route to the OLD Dodo
  product id. Never cache it, never derive it from subscription state — that's
  what makes cancel-and-return work.
- Dodo webhook: when `legacy_pricing = true`, do not overwrite `plan_price`.

Price is decided server-side by gym id. The mobile app never sends a price.

---

## Phase 4 — Flutter app (this repo)

All Dart. Android ships via `shorebird patch android`.

| File | Change |
|---|---|
| `lib/features/auth/providers/auth_provider.dart:60` | add `legacy_pricing` to the gyms select (currently selects `plan_price` but not the flag) |
| `lib/core/config/app_config.dart` (new or existing) | single `currentProPrice` constant — a hardcoded number you edit by hand beats remote config here |
| `lib/features/staff/paywall/paywall_screen.dart:144` | replace hardcoded `'₹249/mo'`: if `legacy_pricing`, show `plan_price` as "Your locked price · ₹249/mo" with the new price struck through; else show `currentProPrice` |
| `lib/features/staff/paywall/ios_custom_paywall.dart` | accept the `gym` param (thread from `_IosPaywall`, which already has it); fetch `offerings.all['legacy_pro']` when `legacy_pricing`, else `offerings.current` |
| `lib/features/staff/settings/settings_screen.dart` | **new row**: "Your plan — Pro, ₹249/mo (locked)" — see note below |

`lib/core/billing/billing_access.dart` needs **no change**. `legacy_pricing`
affects price, not access. The existing "grandfathered pro with no expiry"
branch at line 15 is unrelated and does not collide — both Dodo and manual
gyms have `plan_expires_at` set and flow through the later branches.

### Why the settings row matters

`StaffShell` only renders `PaywallScreen` when `hasActiveBillingAccess()` is
false. All 40 grandfathered gyms currently have access, so **they will never
see the paywall** and never see the locked-price message if it only lives
there. The paywall change is still correct for the lapse-and-return case, but
Settings is where an active customer will actually see it.

---

## Phase 5 — flip the price and tell people

1. Change `currentProPrice` to the new number. Ship.
2. WhatsApp all 40: their price is locked at ₹249 forever, new customers pay
   more. You have their numbers and the sending infrastructure already.
3. Optional one-time in-app banner.

Goodwill only counts if they know about it. A silent grandfather earns nothing.

---

## Phase 6 — verify

1. Query the backfilled ids: `legacy_pricing = true`, correct per-gym
   `plan_price`, one `activity_events` row each.
2. Count `legacy_pricing = true` — must equal your reviewed list exactly.
3. As a normal owner session, attempt to write `plan_expires_at` → must fail.
4. Settings and reminders screens still save → trigger isn't over-blocking.
5. New signup → sees new price, checkout bills new Dodo product.
6. Legacy gym → sees ₹249, Settings shows locked row.
7. Test gym: cancel a legacy sub, resubscribe → still ₹249.
8. iOS: legacy user sees old product, new user sees new product.

---

## Rollback

- Phase 1: `update gyms set legacy_pricing = false` — reversible. Dropping the
  columns is also safe since nothing reads them until Phase 4.
- Phase 1e trigger: `drop trigger gyms_protect_billing on gyms;`
- Phase 2: new Dodo/Apple products can sit unused indefinitely. Old products
  were never touched, so there is nothing to restore.
- Phase 4: `shorebird patch android` to revert Dart. iOS needs a release.
- Phase 5: revert the constant. Anyone already charged the new price must be
  refunded manually — this is the only genuinely hard-to-undo step, which is
  why it goes last.

---

## Open questions

1. Dodo price binding — Phase 0 item 2.
2. Does the web repo's webhook overwrite `plan_price`? — Phase 0 item 3.
3. Current RLS policy on `gyms` — Phase 0 item 1. Highest priority; may be a
   live vulnerability regardless of pricing work.
4. The ₹500 customer — confirm the exact amount and whether anyone else is on
   a non-standard price before writing the backfill.
