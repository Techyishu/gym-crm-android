# Production Operations Audit — GymCRM (Flutter + Supabase)

**Date:** 2026-08-26
**Scope:** whole codebase — `lib/` (38,574 LOC Dart), `supabase/migrations/` (51 files), `supabase/functions/` (8 edge functions), plus the **live production database** (schema, RLS policies, function bodies, grants, cron jobs) read read-only via the Supabase MCP connection.
**Method:** read-only. No repository file was modified; only this report was written. Every database query executed was a `SELECT` against catalog/aggregate data.

---

## 1. Executive summary

```
Production Readiness: HIGH RISK

Critical Issues: 2
High Issues:     7
Medium Issues:   9
Low Issues:      4

Most Dangerous Workflow:        Membership plan change → invoice generation → renewal collection
Biggest Data Integrity Risk:    change_member_plan minting invoices at a stale due date, then carry-forward doubling them
Biggest Revenue Risk:           increment_whatsapp_credits callable by anyone (bypasses the paid credit packs entirely)
Biggest Customer Experience Risk: Multi-branch owners are paywalled out of their own branches 24h after creating them
```

The application is already live (17 gyms carry demo data, cron jobs are running, real payments flow). It is architecturally sound in most places — RLS is enabled on all 40 public tables, money movement was deliberately moved into locking `SECURITY DEFINER` RPCs, and several hardening passes are visible in the migration history. The problems found are **gaps left behind by those hardening passes**, not an absence of security thinking.

### Fix these first, in this order

**1. `get_revenue_report` leaks every gym's revenue to every logged-in user (BUG-001).**
The 2026-07-23 hardening migration added a "caller must be staff of this gym" guard to `get_member_stats` and explicitly noted the pattern. `get_revenue_report` — created three weeks earlier, same shape, same client-supplied `p_gym_id` — was never given one. It is `SECURITY DEFINER`, granted to `authenticated`, and has zero authorization code. Any account (staff of any gym, or a gym member) can substitute another gym's UUID and read that gym's total revenue, billed amount, payment-method mix, dues aging and active-member count. Gym UUIDs are obtainable from `resolve_gym_by_member_code`, which is intentionally public and keyed by the short member code gyms print on their walls. This is cross-tenant exposure of the single most commercially sensitive number in the product.

**2. `increment_whatsapp_credits` can be called by anyone, with no auth check (BUG-002).**
The same 2026-07-23 migration tried to close this: `revoke execute … from anon, authenticated`. That revoke does not touch the `PUBLIC` grant Postgres creates by default, and `PUBLIC` still holds `EXECUTE` today (`proacl` = `=X/postgres | postgres=X/postgres | service_role=X/postgres`). Because `anon` and `authenticated` inherit `PUBLIC`, the hole the migration was written to close is still open. The function body is one unguarded `UPDATE`. Anyone holding the app's embedded anon key — which ships in every APK — can grant any gym unlimited WhatsApp credits (the same credits sold as ₹-priced App Store consumables) or drive any gym's balance negative to silence its reminders.

**3. Multi-branch gyms are structurally unentitled (BUG-003).**
`create_gym_branch` gives a new branch `trial_ends_at = now() + interval '1 day'` and no plan. The RevenueCat webhook resolves the gym to credit via `profiles.gym_id` — the owner's *primary* gym — so no payment ever reaches a branch row. Meanwhile `staffProfileProvider` loads whichever gym is *active*, and `StaffShell` paywalls on that gym. Net result: an owner who pays for Pro, creates a branch, and switches to it is locked out of that branch 24 hours later. The paywall screen replaces the entire shell, and it has no branch switcher — only sign-out clears the persisted `active_gym_id`, so the escape hatch is "sign out and back in", which no owner will guess. The whole branch feature is unusable past day one for paying customers.

**4. Changing a member's plan bills them twice (BUG-004).**
`change_member_plan` inserts the new `memberships` row *before* it updates `members.next_payment_date`. The `trg_create_invoice_for_membership` trigger fires on that insert and reads the member's **old** `next_payment_date` as the due date. The RPC then moves `next_payment_date` to the new derived date. The gym is left holding an invoice at a date the member's schedule no longer uses; when the real date arrives, `generate_monthly_invoices` creates the correct invoice *and folds the stale one into it as carried-forward dues*. The member is billed a full extra period for every plan change. The trigger's idempotency check also ignores already-`paid` invoices for every gym except one hardcoded pilot UUID, so re-assigning a plan can re-bill a period that was already collected.

**5. The lowest-privilege staff role can move money (BUG-005, BUG-006).**
The 2026-08-25 hardening migration correctly restricted `memberships` and `membership_plans` writes to owner/manager. Two paths route around it: the live `change_member_plan` is `SECURITY DEFINER` with no role check (RLS does not apply inside it), so a trainer can rewrite any member's plan, recurring discount and next payment date; and the `invoices_update` policy rewritten in that same migration permits any staff role to `PATCH` an invoice to `status='paid'` or change its `amount`, with no payment row created and no column guard — which additionally fires the "invoice paid" WhatsApp to the member.

---

## 2. Domain overview

**What it is.** A gym CRM sold to Indian gym owners as a SaaS subscription. One Flutter binary serves two audiences: a **staff portal** (`/staff/*`, owner / manager / trainer / staff) and a **member self-service portal** (`/portal/*`). A separate Next.js web app (`gymcrm.in`) shares the same Supabase project.

**Actors.**

| Actor | Identity | Reaches data via |
|---|---|---|
| Owner | `profiles` row, `role='owner'` | RLS via `auth_gym_ids()` |
| Manager / Trainer / Staff | `profiles` row | same |
| Member | `members.user_id` | RLS via `auth_member_id()` |
| Anonymous | app's embedded anon key | public RPCs, storage |
| Cron / edge functions | service role | bypasses RLS entirely |
| Platform admin | `platform_admins` | out of this repo's scope |

**Key entities.** `gyms` (the tenant; also carries plan/trial/billing columns) → `members` → `memberships` (→ `membership_plans`) → `invoices` → `payments`. Plus `check_ins`, `classes`/`class_sessions`/`bookings`, `leads`, `expenses`, `workout_plans`, `diet_plans`, `notifications_log`.

**Tenancy.** `staff_gym_access(profile_id, gym_id, role)` is the multi-branch link table; `auth_gym_ids()` returns the caller's gym array and is the basis of nearly every RLS policy. `profiles.gym_id` remains the *primary* gym and is still used by several server-side paths that were never migrated (see BUG-003, BUG-017).

**Billing architecture — three separate systems.**
- **iOS:** RevenueCat / StoreKit. Entitlement checked client-side (`iosProAccessProvider`) *or* from the `gyms` row. The `revenuecat-webhook` edge function writes `plan`/`plan_expires_at` back to Supabase.
- **Android/web:** Dodo Payments (webhook lives in the web repo), writing the same `gyms` columns.
- **Gym → member billing:** invoices and payments inside the product, collected through `record_invoice_payment_atomic` and `collect_membership_renewal_atomic`.

**Auth.** Supabase Auth. Email+password, email OTP (signup uses a `signUp → signOut → signInWithOtp` handshake guarded by `signupHandshakeInProgress`), Google OAuth, and a phone-OTP path via MSG91 + the `verify-phone-otp` edge function (the staff-facing button is currently commented out; the member self-signup path is live).

**Background work.** 10 active `pg_cron` jobs: monthly invoice generation, member expiry (IST-aligned), 4-hourly stale check-out sweep, WhatsApp reminders, push reminders, billing-expiry push, WhatsApp credit push, owner daily summary, monthly quota reset.

---

## 3. Workflow audit table

| Workflow | Status | Risk | Notes |
|---|---|---|---|
| Signup (email + OTP handshake) | PASS | Low | `signupHandshakeInProgress` correctly suppresses the transient session; `setup_gym` is idempotent |
| Login (email/password) | PASS | Low | Invalidates all four providers on success |
| Login (Google OAuth) | ISSUE | Med | No provider invalidation on the OAuth return path — BUG-015 |
| Login (phone OTP, staff) | NOT VERIFIED | Med | Button commented out; the code path has an account-takeover shape — BUG-016 |
| Member self-signup (phone OTP) | ISSUE | Med | Unpaginated member fetch caps at 1000 rows — BUG-016 |
| Sign-out | ISSUE | Med | Forced sign-out (token-refresh failure) skips provider invalidation — BUG-015 |
| Gym setup | PASS | Low | `setup_gym` is idempotent, validates, blocks member-emails |
| Add gym branch | ISSUE | High | 1-day trial, never entitled by any webhook — BUG-003 |
| Branch switching | ISSUE | High | Switching into an unentitled branch traps the user behind the paywall — BUG-003 |
| Subscription purchase (iOS/RC) | ISSUE | High | Credits `profiles.gym_id` only — BUG-003 |
| Subscription lapse/renewal | PASS | Med | `ACTIVE`/`LAPSED` event sets are correct; `TRANSFER` handling not traced |
| Paywall enforcement | ISSUE | Med | Shell-only; ~12 root-navigator routes bypass it; no server-side billing check at all — BUG-012 |
| Add member | ISSUE | High | 4-step non-atomic write; orphan member + duplicate on retry — BUG-008 |
| Edit member | PASS | Low | RLS + `members_billing_guard` both enforce owner/manager |
| Delete member | NOT VERIFIED | Med | Cascade behaviour on invoices/payments/check-ins not traced |
| CSV import | NOT VERIFIED | Med | Batched inserts + separate memberships insert; same non-atomic shape as BUG-008 |
| Assign / change plan | ISSUE | High | Double-billing via trigger ordering — BUG-004; no role check — BUG-005 |
| Generate monthly invoices | ISSUE | Med | Correct carry-forward, but `authenticated`-executable and UTC-dated |
| Collect renewal (current path) | PASS | Low | `collect_membership_renewal_atomic` locks, compare-and-sets the date, validates the remaining balance, honours the billing interval — the best-built code in the repo |
| Record invoice payment | ISSUE | Med | No role check; legacy RPC ignores prior partial payments — BUG-013 |
| Direct invoice mutation | ISSUE | High | RLS permits any staff role to mark paid / change amount — BUG-006 |
| Staff check-in (online) | PASS | Low | Partial unique index blocks re-entry; status verified; owner alerted |
| Staff check-in (offline queue) | ISSUE | High | Permanent stuck items, duplicate-on-retry, no status check — BUG-009 |
| Member self check-in (QR) | PASS | Low | `self_checkin` validates gym, membership and status server-side |
| Biometric check-in (ADMS) | ISSUE | Med | Plain HTTP, serial number is the only credential — BUG-018 |
| Check-out | PASS | Low | `checkout_member` is gym-scoped and idempotent |
| Reports / revenue | ISSUE | Critical | Cross-tenant read — BUG-001; demo data inflates figures — BUG-010 |
| Dashboard stats | ISSUE | Med | Naive local dates sent as UTC — BUG-011 |
| WhatsApp reminders | ISSUE | High | Platform-wide run is unauthenticated — BUG-007 |
| WhatsApp credits | ISSUE | Critical | Publicly writable — BUG-002 |
| Owner push notifications | ISSUE | Med | All `trigger_*` RPCs publicly executable — BUG-014 |
| Blocked-check-in owner alert | ISSUE | Low | Never fires for branch gyms — BUG-017 |
| Razorpay key storage | PASS | Low | `save_razorpay_keys` checks `auth_gym_ids()` **and** the per-branch role |

---

## 4. Findings

### CRITICAL

---

### [BUG-001] `get_revenue_report` returns any gym's revenue to any authenticated user

**Severity:** Critical
**Confidence:** Confirmed
**Affected workflow:** Reports / revenue — multi-tenant isolation

**Files involved:**
- `lib/features/staff/reports/reports_screen.dart:98` — client passes `p_gym_id`
- `supabase/migrations/20260710_reports_metrics.sql` — original definition
- `supabase/migrations/20260723_close_public_rpc_and_storage_holes.sql:47` — fixed the sibling `get_member_stats`, missed this one
- Live: `public.get_revenue_report(p_gym_id uuid, p_from timestamptz, p_period text)`, `prosecdef = true`, `proacl = postgres=X/postgres | authenticated=X/postgres | service_role=X/postgres`

**Execution path:**

Any authenticated session (staff of gym B, or a gym member)
→ `POST /rest/v1/rpc/get_revenue_report` with `p_gym_id = <gym A's uuid>`
→ function is `SECURITY DEFINER`, so RLS on `invoices` / `payments` / `members` is bypassed
→ function body contains **no** `auth.uid()`, `auth_gym_ids()` or ownership check of any kind
→ returns gym A's `total_revenue`, `total_billed`, `total_invoices`, `paid_count`, `partial_count`, `prev_total_revenue`, `active_members`, `avg_days_to_pay`, a per-day/per-month revenue series, the payment-method breakdown, and the dues-aging buckets

**What happens:**
The RPC trusts a client-supplied tenant identifier while running with definer privileges. The only guard anywhere in the chain is the client screen choosing to pass its own `gymId`.

**Failure scenario:**
A competitor signs up for a free trial (`setup_gym` grants 3 days, no card required). They walk into a rival gym and photograph the member-code poster, or read the code off a member's app. They call the public `resolve_gym_by_member_code(code)` RPC — `SECURITY DEFINER`, granted to `anon`, no auth check — which returns that gym's `id` and `name`. They then call `get_revenue_report` with that UUID and a `p_from` of `2020-01-01` and receive the rival's complete revenue history, active member count, collection efficiency and outstanding dues.

**Expected behaviour:**
The RPC must reject any `p_gym_id` not in `auth_gym_ids()`, exactly as `get_member_stats`, `insert_checkin_secure`, `change_member_plan`, `record_invoice_payment_atomic` and `collect_membership_renewal_atomic` all already do.

**Why this happens:**
`get_revenue_report` predates the July hardening pass. That pass audited RPCs reachable by `anon` and fixed `get_member_stats`, `increment_whatsapp_credits` and `trigger_push_reminders`. `get_revenue_report` is granted to `authenticated` rather than `anon`, so it fell outside the sweep's filter — but "any signed-in user" is not a tenant boundary in a multi-tenant SaaS.

**Customer impact:**
None visible — the victim gym gets no signal at all. This is a silent breach.

**Business impact:**
Competitive intelligence leak across the entire customer base; a reportable personal/financial data exposure under DPDP; existential trust damage if disclosed.

**Recommended fix:**
Add as the first statement of the function body:

```sql
if p_gym_id is null or not (p_gym_id = any (public.auth_gym_ids())) then
  raise exception 'unauthorized: gym mismatch';
end if;
```

This requires converting the function from `LANGUAGE sql` to `LANGUAGE plpgsql` (wrap the existing query as `return query <existing select>`), or alternatively keeping it as SQL and adding the guard as a correlated `WHERE` predicate. Then sweep every remaining `SECURITY DEFINER` function that accepts a `gym_id`-shaped parameter and confirm each one checks it.

**How to verify the fix:**
Sign in as a member of gym A. Call `get_revenue_report` with gym B's UUID. Before the fix: a populated JSON object. After: `unauthorized: gym mismatch`. Then confirm the Reports screen still loads for a manager of gym B, on both their primary gym and a secondary branch.

---

### [BUG-002] `increment_whatsapp_credits` is executable by `PUBLIC` and has no authorization check

**Severity:** Critical
**Confidence:** Confirmed
**Affected workflow:** WhatsApp credit purchase (paid IAP) / reminder delivery

**Files involved:**
- `supabase/migrations/20260712_whatsapp_credits_increment_rpc.sql` — original definition
- `supabase/migrations/20260723_close_public_rpc_and_storage_holes.sql:23` — the revoke that did not take effect
- `supabase/functions/revenuecat-webhook/index.ts:128` — the legitimate caller
- Live: `proacl = =X/postgres | postgres=X/postgres | service_role=X/postgres`

**Execution path:**

Attacker extracts the anon key from the APK (`lib/main.dart:21`, also present verbatim in `cron.job` id 8)
→ `POST /rest/v1/rpc/increment_whatsapp_credits` with `{"p_gym_id": "<any>", "p_amount": 1000000}`
→ PostgREST executes as `anon`; `anon` inherits the `PUBLIC` EXECUTE grant that is still present
→ function is `SECURITY DEFINER` and its entire body is `update gyms set whatsapp_credits = whatsapp_credits + p_amount where id = p_gym_id;`
→ no `auth.uid()` check, no `auth_gym_ids()` check, no sign check on `p_amount`

**What happens:**
`REVOKE EXECUTE … FROM anon, authenticated` does not revoke the implicit `GRANT EXECUTE … TO PUBLIC` that Postgres applies to every new function. The catalog confirms `PUBLIC` still holds `EXECUTE` (`=X/postgres`). The 2026-07-23 migration is documented as having closed this hole; it did not.

**Failure scenario:**
*Revenue:* A gym owner (or anyone) reads the anon key out of the APK, calls the RPC with `p_amount = 100000` against their own gym, and never buys another `gymcrm_credits_500` pack. The RevenueCat purchase path becomes optional.
*Sabotage:* The same call with `p_amount = -999999` against a competitor's gym UUID (obtained per BUG-001) drives their balance negative. `whatsapp-reminders` skips gyms without credits, so that gym's payment reminders stop going out. Their collection rate drops and nobody can explain why.

**Expected behaviour:**
The function should be callable only by the service role (the webhook is its only legitimate caller), and `p_amount` should be validated.

**Why this happens:**
A `REVOKE … FROM anon, authenticated` idiom that is correct-looking but incomplete. The pattern is repeated across this codebase — see BUG-014 for the same defect on seven more functions.

**Customer impact:**
Victim gym's WhatsApp reminders silently stop. No error is surfaced anywhere in the app.

**Business impact:**
Direct loss of consumable IAP revenue; DoS against any customer's core retention feature; MSG91 spend attributable to forged credits.

**Recommended fix:**

```sql
revoke all on function public.increment_whatsapp_credits(uuid, integer) from public, anon, authenticated;
```

Add `if p_amount <= 0 then raise exception 'invalid amount'; end if;` as defence in depth. Then run the audit query below over the whole schema and repeat the revoke wherever `PUBLIC` still holds `EXECUTE`:

```sql
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and (p.proacl is null or array_to_string(p.proacl, ',') like '=X/%');
```

**How to verify the fix:**
With only the anon key, call the RPC. Before: HTTP 200 and the balance moves. After: `permission denied for function increment_whatsapp_credits`. Then confirm an iOS credit-pack purchase still increments the balance through the webhook.

---

### HIGH

---

### [BUG-003] Multi-branch gyms are never entitled — a paying owner is locked out of their own branch after 24 hours

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Add gym branch → branch switching → subscription entitlement

**Files involved:**
- `supabase/migrations/20260823120000_multi_gym_branches.sql` — `create_gym_branch` sets `trial_ends_at = now() + interval '1 day'`
- `supabase/functions/revenuecat-webhook/index.ts:62-70` — `getGymId()` reads `profiles.gym_id`
- `lib/features/auth/providers/auth_provider.dart:71-98` — `staffProfileProvider` loads the gym row for the **active** gym
- `lib/core/shells/staff_shell.dart:174-181` — paywall gate reads that gym
- `lib/core/billing/billing_access.dart:1-33`
- `lib/features/staff/paywall/paywall_screen.dart` — no branch switcher among its actions

**Execution path:**

Owner (Pro, paid) taps **Add Branch**
→ `create_gym_branch` inserts a `gyms` row with `plan = null`, `plan_expires_at = null`, `trial_ends_at = now() + 1 day`
→ owner switches to it; `switchActiveGym` persists `active_gym_id` and invalidates `gymIdProvider`
→ `staffProfileProvider` now returns the **branch** gym row
→ 24 hours later `hasActiveBillingAccess(branchGym)` evaluates every clause to false
→ `StaffShell` returns `PaywallScreen` instead of the shell
→ the branch switcher lives in the shell's More sheet / side nav, which is no longer rendered
→ the paywall's only actions are Upgrade, Customer Center, WhatsApp support and Sign out

**What happens:**
No payment ever reaches a branch's `gyms` row. Every webhook that grants entitlement resolves the target gym through `profiles.gym_id`, which `create_gym_branch` deliberately does not touch ("the owner's primary gym stays the same"). Entitlement lives per-gym; payment lands per-owner-primary-gym. The two never meet.

**Failure scenario:**
An owner running two locations pays ₹X/month for Pro. They add their second location as a branch, spend an afternoon entering its members, and switch to it. The next morning the app shows them a paywall for a product they are already paying for. Tapping Upgrade would purchase a second subscription — which the webhook would once again apply to the primary gym, leaving the branch locked. The only working escape is Sign out (which clears `active_gym_id` and lands them back on the primary gym), and nothing on screen suggests that.

**Expected behaviour:**
Entitlement should be evaluated for the owner (or across `staff_gym_access`), not per gym row — or the webhook should credit every gym the payer owns. Until then the paywall must at minimum offer a branch switcher so the owner is never trapped.

**Why this happens:**
The multi-gym feature (2026-08-23) widened RLS and RPCs to `auth_gym_ids()` thoroughly, but the billing layer — the RevenueCat webhook, the Dodo webhook in the web repo, and `hasActiveBillingAccess` — was never part of that sweep. `create_gym_branch`'s 1-day trial hides the problem for exactly one day, which is long enough for the branch to look like it works during setup.

**Customer impact:**
A paying customer is locked out of a feature they paid for, with a dead-end screen and a non-obvious recovery. Guaranteed support ticket; plausible refund demand and churn.

**Business impact:**
The multi-branch feature is effectively non-functional for its entire (paying) target audience. Risk of accidental duplicate subscriptions.

**Recommended fix:**
Shortest correct change: resolve entitlement from the owner rather than the gym. Have the webhook update every gym in `staff_gym_access` for the payer where their role is `owner`, or add a `gyms.entitled_via_gym_id` pointer that `hasActiveBillingAccess` follows. Separately and immediately: add the branch switcher to `PaywallScreen` so no owner can be trapped, and reconsider the 1-day branch trial (it makes the failure look like a bug rather than a limit).

**How to verify the fix:**
Create a branch on a Pro account. Set its `trial_ends_at` into the past. Switch to it. Expect the full shell, not the paywall. Then confirm a genuinely unpaid single-gym account is still paywalled.

---

### [BUG-004] Changing a member's plan mints an invoice at the old due date, which is then double-billed via carry-forward

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Assign / change membership plan → monthly invoice generation

**Files involved:**
- `lib/features/staff/members/member_detail_screen.dart:1127-1178` — computes `derived` and calls the RPC
- Live `public.change_member_plan(...)` — insert-then-update ordering
- Live `public.create_invoice_for_membership()` — `AFTER INSERT ON memberships`
- Live `public.generate_monthly_invoices()` — carry-forward block

**Execution path:**

Staff opens a member with `next_payment_date = 2026-09-15`, picks a new monthly plan, chooses "start today"
→ client computes `derived = advancePaymentDate('2026-08-26', months: 1)` = `2026-09-26`
→ `change_member_plan` cancels the active membership
→ `change_member_plan` **inserts** the new `memberships` row
→ `trg_create_invoice_for_membership` fires and reads `members.next_payment_date`, which is **still `2026-09-15`**
→ trigger inserts an invoice with `due_at = 2026-09-15`, `amount = new plan price`, `status = 'open'`
→ `change_member_plan` **then** updates `members.next_payment_date = 2026-09-26`
→ on 2026-09-26 `generate_monthly_invoices` sees `next_payment_date = today`, finds the 2026-09-15 invoice as an unpaid past-due invoice, adds its full amount as carried-forward dues to the new invoice and voids the old one
→ the new invoice reads `<plan> — membership fee (includes 1500.00 due from last month)` and totals **two** periods

**What happens:**
The trigger's notion of "when is this invoice due" is read one statement too early. Because the update that would have made it correct happens afterwards in the same transaction, the trigger can never see the right date.

**Failure scenario:**
A member on a ₹1,500/month plan, paid through 15 September, upgrades on 26 August and asks to start immediately. An invoice for ₹1,500 due 15 September appears that nobody collects (it does not correspond to anything the member owes). On 26 September the member receives an invoice for ₹3,000 with a note about last month's dues — for a plan they have used for one month. If `whatsapp_invoice_enabled` is on, the `trg_notify_invoice_whatsapp` trigger WhatsApps both invoices to the member as they are created.

**Expected behaviour:**
Exactly one invoice, for one period, dated to the member's new schedule.

**Why this happens:**
`change_member_plan` was written as three ordered statements without accounting for the `AFTER INSERT` trigger sitting on the middle one. The trigger's own idempotency guard (`due_at = v_due_at and status = 'open'`) cannot help, because the stale and correct due dates differ. A related defect sits in the same trigger: the guard only treats `status = 'open'` as blocking, except for one hardcoded gym (`v_pilot_gym := '604de979-…'`), so for every other gym re-assigning a plan can re-bill a period that was already paid. That pilot comment shows the team has already hit this in production for one customer.

**Customer impact:**
Members are billed roughly double on any plan change. Staff must void invoices manually and explain the charge. Members who pay by standing instruction may be overcharged before anyone notices.

**Business impact:**
Direct billing errors against end customers of the gym — the most damaging class of bug for a billing product's reputation. Support burden per plan change.

**Recommended fix:**
Update `members.next_payment_date` **before** inserting the `memberships` row inside `change_member_plan` — a two-line reorder, and the smallest correct change. Additionally, promote the pilot's already-paid check to all gyms by removing the `v_pilot_gym` condition so the `exists` guard reads `status in ('open','paid')`.

**How to verify the fix:**
Seed a member with `next_payment_date = today + 20 days` and an active plan. Change the plan choosing "start today". Assert exactly one `invoices` row is created and its `due_at` equals the new `next_payment_date`. Run `generate_monthly_invoices()` on that date and assert the resulting invoice amount equals one plan period with no carried-forward text.

---

### [BUG-005] `change_member_plan` has no role check — any staff or trainer can rewrite a member's plan, discount and next payment date

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Membership plan management / permission enforcement

**Files involved:**
- Live `public.change_member_plan(...)` — guards are `auth.uid() is not null` and `member.gym_id = any(auth_gym_ids())` only
- `supabase/migrations/20260825120000_operational_security_hardening.sql:56-80` — restricts `memberships` INSERT/UPDATE/DELETE to owner/manager
- `lib/core/access/role_access.dart:27` — `canEditMembers` is manager-or-above

**Execution path:**

Trainer or staff account signs in
→ `POST /rest/v1/rpc/change_member_plan` with any `p_member_id` in their gym, any `p_plan_id` in their gym, an arbitrary `p_discount_amount` and an arbitrary `p_next_payment_date`
→ function is `SECURITY DEFINER`, so the owner/manager RLS policies on `memberships` do not apply
→ the old membership is cancelled, a new one inserted with the caller's discount, and `members.next_payment_date` set to the caller's date

**What happens:**
The hardening migration closed the direct-table route to `memberships` but the `SECURITY DEFINER` RPC route was left open. `SECURITY DEFINER` bypasses RLS by definition, so the RPC must re-implement the role check itself — as `collect_membership_renewal_atomic` correctly does (`role in ('owner','manager','staff')`) and `save_razorpay_keys` correctly does (`role in ('owner','manager')`).

**Failure scenario:**
A trainer about to leave sets a recurring discount equal to the plan price on twenty members, and pushes their `next_payment_date` twelve months out. `generate_monthly_invoices` then produces ₹0 invoices (`greatest(price - discount, 0)`) and `expire_overdue_members` never expires them. The gym stops billing those members and nothing in the UI flags it. Reconstructing the correct dates afterwards requires the audit log, if one exists.

**Expected behaviour:**
The RPC should refuse callers whose role in that gym is not `owner` or `manager`, matching `RoleAccess.canEditMembers` and the RLS policies added on 2026-08-25.

**Why this happens:**
The multi-gym widening pass rewrote the gym check from `= auth_gym_id()` to `= any(auth_gym_ids())` but did not add the role dimension; the later hardening pass added roles at the RLS layer and did not revisit the RPCs.

**Customer impact:**
Silent revenue loss for the gym owner, discovered weeks later via a missing-revenue investigation.

**Business impact:**
Insider fraud vector inside a product whose selling point is that the owner controls billing.

**Recommended fix:**
Add to `change_member_plan`, mirroring `save_razorpay_keys`'s per-branch role lookup:

```sql
if not exists (
  select 1 from staff_gym_access
  where profile_id = auth.uid() and gym_id = v_member_gym_id
    and role in ('owner','manager')
) then
  raise exception 'insufficient_role';
end if;
```

Then audit every `SECURITY DEFINER` RPC that writes billing-relevant data against the role matrix in `RoleAccess`.

**How to verify the fix:**
Sign in as a trainer, call the RPC against a member of their own gym. Expect `insufficient_role`. Repeat as a manager and confirm the plan change still succeeds, including on a secondary branch.

---

### [BUG-006] `invoices_update` RLS lets any staff role mark an invoice paid or change its amount

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Invoice / payment integrity

**Files involved:**
- `supabase/migrations/20260825120000_operational_security_hardening.sql:8-12`
- Live: no `BEFORE UPDATE` trigger exists on `invoices` (only two `AFTER` notification triggers)

**Execution path:**

Any account with a `profiles` row in the gym — including `trainer`, the lowest-trust role
→ `PATCH /rest/v1/invoices?id=eq.<uuid>` with `{"status":"paid"}` or `{"amount": 1}`
→ policy `invoices_update` evaluates `gym_id = any(auth_gym_ids())` → true
→ no role condition, no column restriction, no guard trigger
→ the update commits with **no `payments` row created**
→ `trg_notify_invoice_paid_whatsapp` fires and WhatsApps a payment confirmation to the member

**What happens:**
The migration's own comment states members "cannot create a payment or alter invoice status/amount". That is true for members — they have no `profiles` row, so `auth_gym_ids()` returns `{}` for them. It is not true for staff, for whom the policy is unconditional. `members` got both a role condition in RLS and a `members_billing_guard` column trigger; `invoices` got neither.

**Failure scenario:**
A staff member collects ₹2,000 cash from a member, pockets it, and marks the invoice paid directly rather than through the Collect Payment screen. The member receives a WhatsApp confirming payment, so they never complain. The owner's Reports screen reads `total_revenue` from the `payments` table, which shows nothing — but the invoice list and dues aging both show settled. The books disagree with themselves and the discrepancy looks like a reporting glitch rather than theft.

**Expected behaviour:**
`status`, `amount`, `paid_at` and `gym_id` should be writable only by the definer RPCs. Staff-facing updates should be limited to non-financial fields (notes, description).

**Why this happens:**
The hardening migration correctly funnelled payment *creation* through `record_invoice_payment_atomic` and locked down `payments` INSERT — then left the invoice row itself directly mutable, which makes the RPC optional.

**Customer impact:**
Members receive payment confirmations for money the gym never banked.

**Business impact:**
Embezzlement channel with a built-in alibi; reports that contradict each other and cannot be reconciled.

**Recommended fix:**
Add a `BEFORE UPDATE` guard trigger on `invoices` modelled directly on the existing `block_member_self_billing_edit`:

```sql
create or replace function block_invoice_financial_edit()
returns trigger language plpgsql as $$
begin
  if auth.role() <> 'service_role'
     and (new.status is distinct from old.status
          or new.amount is distinct from old.amount
          or new.paid_at is distinct from old.paid_at
          or new.gym_id is distinct from old.gym_id) then
    raise exception 'invoice financial fields are set by payment RPCs only';
  end if;
  return new;
end;
$$;
```

The RPCs are `SECURITY DEFINER` but still run as the invoking role for `auth.role()` purposes, so verify they are exempted — either by widening the exemption to `current_setting('gymcrm.in_payment_rpc', true)` set inside each RPC, or by moving the guard into the policy as a column-level `WITH CHECK`. Confirm against `record_invoice_payment_atomic`, `collect_membership_renewal_atomic` and `generate_monthly_invoices` before deploying.

**How to verify the fix:**
As a trainer, `PATCH` an invoice to `status='paid'`. Expect rejection. Then collect a payment normally through the app and confirm it still settles the invoice and sends the WhatsApp.

---

### [BUG-007] `whatsapp-reminders` runs platform-wide with no authorization when `gym_id` is omitted

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** WhatsApp payment reminders / per-gym credit spend

**Files involved:**
- `supabase/functions/whatsapp-reminders/index.ts:184-204`
- Live `cron.job` id 8 — invokes this endpoint with the **anon** key in the Authorization header

**Execution path:**

`POST /functions/v1/whatsapp-reminders` with body `{}` and the app's anon key as bearer
→ gateway JWT verification passes (the anon key is a valid project JWT — cron job 8 relies on exactly this)
→ `filterGymId` is undefined, so the entire authorization block at lines 191-203 is **skipped**
→ the function proceeds with the service-role client over **every** gym where `whatsapp_reminder_enabled` is true
→ each matching gym's `whatsapp_credits` and `whatsapp_monthly_quota_used` are spent, and MSG91 messages are sent to their members

**What happens:**
Authorization is attached to the optional narrowing parameter rather than to the endpoint. Omitting the parameter widens the blast radius *and* removes the check.

**Failure scenario:**
Anyone with the APK triggers the platform-wide reminder run at 3 a.m. local time. Every gym's members receive payment reminders at an hour their gym did not choose. The day's cooldown buckets (`notifications_log`) are consumed, so when the legitimate 08:00 IST cron fires, the messages the gym actually intended are suppressed. Repeating this daily makes every customer's reminder feature appear broken while consuming their paid credits.

**Expected behaviour:**
The unfiltered platform-wide run is a cron operation and should require the same `CRON_SECRET` bearer that `push-reminders`, `owner-daily-summary`, `whatsapp-credit-push` and `send-whatsapp-invoice` all already require. The per-gym manual trigger keeps its existing staff check.

**Why this happens:**
Four of the five cron-invoked edge functions use the `CRON_SECRET` pattern. This one does not, because it doubles as a user-triggerable manual send, and the auth was written for that case only.

**Customer impact:**
Reminders at wrong hours, then no reminders at all when they matter. Credits drain with no purchase.

**Business impact:**
MSG91 spend across the whole customer base is attacker-controlled; the reminder feature — a headline retention feature — becomes unreliable for everyone.

**Recommended fix:**
Require `CRON_SECRET` whenever `filterGymId` is absent:

```ts
if (!filterGymId) {
  const auth = req.headers.get('Authorization') ?? ''
  if (auth !== `Bearer ${Deno.env.get('CRON_SECRET')}`) {
    return new Response('Unauthorized', { status: 401 })
  }
}
```

Update `cron.job` id 8 to send the Vault-held `push_reminders_cron_secret` instead of the anon key — the same pattern `trigger_push_reminders` already uses. That also removes a hardcoded JWT from `cron.job`.

**How to verify the fix:**
`POST {}` with the anon key → expect 401. `POST {"gym_id": "<own gym>"}` as a manager → expect the send to run. Confirm the rescheduled cron job still delivers the daily run.

---

### [BUG-008] Adding a member is a four-step non-atomic write — a mid-way failure orphans the member, and retrying duplicates them

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Data creation — add member

**Files involved:**
- `lib/features/staff/members/members_screen.dart:1132-1216`
- Live `public.generate_monthly_invoices()` — the `if not found then v_skipped := v_skipped + 1; continue;` branch
- `lib/features/staff/members/import_csv_screen.dart` — same shape at batch scale

**Execution path:**

Staff fills the Add Member form and taps Save
→ 1. `insert into members (…)` → commits, id returned
→ 2. `insert into memberships (member_id, plan_id, 'active', …)` → `trg_create_invoice_for_membership` creates the invoice
→ 3. `select` the newest open invoice for that member
→ 4. `recordInvoicePayment(...)` if an amount was collected
→ each step is a separate HTTP request; there is no transaction and no compensating delete

**What happens:**
If the process dies between steps 1 and 2 — the connection drops, the app is backgrounded and killed, the request times out — the member row exists permanently with `next_payment_date` and `billing_interval_months` set, but with **no membership and no invoice**. `generate_monthly_invoices` looks up the active membership, finds none, increments `v_skipped` and moves on. That member is never billed again, and nothing anywhere surfaces the fact.

The `catch` shows a single generic message, "Failed to add member. Please try again." Staff take it at face value and re-enter the member — creating a second `members` row. The duplicate-phone trigger (`members_no_duplicate_phone`) blocks this only when a phone number was supplied; phone is optional on the form.

**Failure scenario:**
A gym signs up members at the front desk on patchy mobile data. The membership insert times out. The screen says the member was not added, so the receptionist adds them again — now there are two rows for the same person, one of which is invisible to invoicing forever. Weeks later the owner asks why revenue does not match headcount.

**Expected behaviour:**
Member + membership + first invoice + optional first payment should be one transaction, exposed as a single RPC — the pattern the codebase already uses well for `collect_membership_renewal_atomic` and `change_member_plan`.

**Why this happens:**
This screen predates the move to atomic RPCs. The comment at line 1165 ("A DB trigger auto-creates the invoice the moment this insert commits") shows the trigger dependency was understood, but not that the two inserts can be split by a failure.

**Customer impact:**
Duplicate member records; members who silently stop being billed; headcount and revenue that never reconcile.

**Business impact:**
Revenue leakage the owner cannot see, in the product they bought specifically to stop revenue leakage.

**Recommended fix:**
Add a `create_member_with_plan(...)` `SECURITY DEFINER` RPC performing all four writes in one transaction, and have the screen call it. As an immediate mitigation ahead of that: distinguish the failure in the `catch` — if `inserted['id']` is non-null when the membership insert fails, tell staff the member was created but the plan was not, and route them to the member's detail screen to assign it, rather than inviting a blind retry.

**How to verify the fix:**
Add a member with the network cut after the first request. Assert either zero rows or a complete member+membership+invoice set. Then assert `generate_monthly_invoices()` reports `skipped = 0` for a gym whose members were all added through the new path.

---

### [BUG-009] Offline check-in queue: items expire permanently, duplicate on retry, and skip the membership-status check

**Severity:** High
**Confidence:** Confirmed
**Affected workflow:** Offline check-in → sync

**Files involved:**
- `lib/core/services/offline_checkin_queue.dart:86-123` — `flush()`
- `lib/features/staff/check_in/check_in_screen.dart:190-224` — the offline branch
- `supabase/migrations/20260823130000_multi_gym_widen_rls.sql` — `insert_checkin_secure`'s `checkin_too_old` guard

**Execution path — three distinct defects on one path:**

*(a) Permanent stuck items.* Gym goes offline → check-ins queue with `queued_at = now` → connectivity returns more than 24 hours later → `flush()` calls `insert_checkin_secure` with `p_checked_in_at = queued_at` → the RPC raises `checkin_too_old: timestamp must be within the last 24 hours` → the `catch` at line 115 pushes the item into `remaining` → it is written back to SharedPreferences → every future flush repeats this forever. The attendance is never recorded, and the check-in screen shows a "pending sync" count that can never reach zero.

*(b) Duplicate on lost response.* The RPC commits server-side, then the connection drops before the response arrives → the client's `catch` treats it as a failure and re-queues → the next flush inserts a second `check_ins` row. There is no idempotency key. (The partial unique index `check_ins_open_session_unique` blocks this only while the first session is still open; `auto_checkout_stale_sessions` closes it after four hours, after which the duplicate goes through cleanly.)

*(c) Expired members check in free.* The online path fetches `members.status` and blocks anything other than `active`, notifying the owner. The offline path enqueues on nothing but a UUID-shape check, and `insert_checkin_secure` validates only that the member belongs to the gym — **it never looks at `status`**. Every queued check-in is inserted regardless of whether the membership lapsed.

**What happens:**
Errors are logged with `debugPrint` and otherwise swallowed. No error path distinguishes "retry later" from "will never succeed", and no path surfaces a permanent failure to staff.

**Failure scenario:**
A gym's broadband fails Friday evening. Staff keep scanning; the app reassuringly says "Saved offline. Will sync automatically when connected." The line is fixed Monday morning. Every check-in from Friday and Saturday is now older than 24 hours and is rejected forever — two days of attendance data lost, with the badge still showing "43 pending". Meanwhile, three members whose memberships expired on Friday were checked in without challenge and without the owner alert that the online path would have sent.

**Expected behaviour:**
Permanently-rejected items should be dropped from the queue and reported to staff. A successful insert should be idempotent under retry. Membership status should be enforced server-side, where it cannot be skipped.

**Why this happens:**
`flush()` treats every exception identically. The 24-hour window was added to `insert_checkin_secure` to stop timestamp tampering, without a corresponding client-side rule to stop queueing (or to give up on) items that will age out. Status checking lives in the Flutter screen rather than in the RPC, so the offline path — which does not run that screen code — has no equivalent.

**Customer impact:**
Silent, permanent attendance data loss; a pending-sync badge that never clears; expired members training free during every outage.

**Business impact:**
Attendance is a core deliverable of the product and one input to renewal decisions. Losing it invisibly is worse than failing loudly.

**Recommended fix:**
In `flush()`, inspect the `PostgrestException` message: drop the item on the terminal errors (`checkin_too_old`, `member_not_in_gym`) and record a user-visible summary; keep only genuinely transient failures in `remaining`. Add a client-generated `client_ref` UUID to the enqueued payload, accept it in `insert_checkin_secure`, and add a unique index on it so a retried insert is a no-op. Move the `status <> 'active'` check (and the `notify_owner_expired_checkin` call) inside `insert_checkin_secure`, so both the online and offline paths inherit it — one guard in the shared function rather than one per caller.

**How to verify the fix:**
Queue a check-in, set its `queued_at` back 30 hours, flush. Assert the queue empties and staff see a "3 check-ins too old to sync" message. Flush the same item twice with the response suppressed on the first attempt and assert exactly one `check_ins` row. Queue a check-in for an `expired` member and assert the RPC rejects it and the owner alert fires.

---

### MEDIUM

---

### [BUG-010] Reports include seeded demo data; the owner daily-summary push excludes it

**Severity:** Medium
**Confidence:** Confirmed
**Affected workflow:** Reporting

**Files involved:**
- Live `public.get_revenue_report(...)` and `public.get_member_stats(...)` — no `is_demo_data` filter
- `supabase/functions/owner-daily-summary/index.ts:81-97` — filters `is_demo_data = false`
- `lib/features/staff/paywall/paywall_screen.dart:48-67` — also filters it

**What happens:**
Production currently holds **169 demo members and 167 demo invoices across 17 gyms**. The Reports screen counts them in revenue, active members, growth charts, plan mix and dues aging. The daily summary push and the paywall's value summary exclude them.

**Failure scenario:**
A trial gym opens Reports and sees revenue it never collected and members it never signed up. That evening the daily summary push reports a different, smaller number. The owner cannot tell which is real, and the first impression of the reporting feature is that it is wrong.

**Recommended fix:**
Add `and coalesce(is_demo_data, false) = false` to the `inv`, `collected`, `prev_collected`, `method_agg`, `aging_bucket` CTEs in `get_revenue_report` and to the `mem` CTE in `get_member_stats`. Fold this into the BUG-001 fix, since both functions are being edited anyway.

**How to verify:** Compare the Reports total against the daily summary for a gym with demo data; they must match.

---

### [BUG-011] Naive local dates are sent as UTC — "today" begins at 05:30 IST

**Severity:** Medium
**Confidence:** Confirmed
**Affected workflow:** Dashboard stats, billing period stats, today's check-ins

**Files involved:**
- `lib/features/staff/dashboard/dashboard_screen.dart:29-39`
- `lib/features/staff/billing/billing_screen.dart:65-68`
- `lib/features/staff/check_in/check_in_screen.dart:56-63`

**What happens:**
`DateTime(now.year, now.month, now.day).toIso8601String()` produces `2026-08-26T00:00:00.000` with **no timezone offset**. Postgres interprets an offsetless literal against a `timestamptz` column as UTC. For an IST (+05:30) gym, every "since start of day" filter actually starts at 05:30 IST.

**Failure scenario:**
Indian gyms peak between 05:00 and 08:00. Until 05:30 the dashboard's "today's check-ins" reads zero while the floor is full, and members who came in at 05:15 never appear in that count at all. The same defect shifts "new members this month" and month-over-month revenue comparisons by 5.5 hours across every month boundary. Note the backend is already IST-aware — `expire_overdue_members` uses `now() at time zone 'Asia/Kolkata'` — so client and server disagree about what day it is.

**Recommended fix:**
Use `.toUtc().toIso8601String()` on the local midnight (`DateTime(y, m, d).toUtc()`), which produces the correct instant with a `Z` suffix. Apply at all three sites; the same expression appears in `collect_payment.dart:20,36` for comparison-only purposes where it is harmless.

**How to verify:** With the device clock at 05:00 IST, insert a check-in and confirm the dashboard count includes it.

---

### [BUG-012] The paywall is enforced only inside `StaffShell`, and nowhere on the server

**Severity:** Medium
**Confidence:** High Confidence
**Affected workflow:** Subscription entitlement

**Files involved:**
- `lib/core/shells/staff_shell.dart:174-181` — the only `hasActiveBillingAccess` call site in the app
- `lib/core/router.dart:311-380` — twelve staff routes declared with `parentNavigatorKey: rootNavigatorKey`

**What happens:**
Only the four shell branches (dashboard, members, billing, check-in) pass through the billing gate. `/staff/reports`, `/staff/settings`, `/staff/leads`, `/staff/expenses`, `/staff/classes`, `/staff/communications`, `/staff/reminders`, `/staff/staff`, `/staff/workout-plans`, `/staff/diet-plans`, `/staff/upcoming-payments`, `/staff/notifications` and `/invoice/:id` render outside the shell. The router's redirect performs role checks for several of these but never a billing check. Separately, **no RLS policy or RPC anywhere consults `plan`, `plan_expires_at` or `trial_ends_at`** — entitlement exists purely in the Flutter layer.

**Failure scenario:**
A user sitting on `/staff/reports` when their plan lapses keeps full access, because the shell that would paywall them is not in the widget tree. More broadly, anyone willing to talk to PostgREST directly with the anon key and a valid session has complete access to an expired gym's data and mutations.

**Why this is Medium rather than High:** reaching the unshelled routes normally requires navigating through the shell, which is already paywalled, so the everyday bypass window is narrow. The systemic point — that entitlement has no server-side existence — is the finding that matters.

**Recommended fix:**
Extract the gate into a small `BillingGate` wrapper and apply it to the root-navigator staff routes as well. For the deeper issue, add a plan check to the write-path RPCs (`collect_membership_renewal_atomic`, `record_invoice_payment_atomic`, `change_member_plan`) so a lapsed gym cannot be operated through the API.

**How to verify:** Deep-link to `/staff/reports` on an expired gym; expect the paywall.

---

### [BUG-013] Payment RPCs have no role check, and the legacy RPC ignores prior partial payments

**Severity:** Medium
**Confidence:** Confirmed (role gap) / High Confidence (legacy over-collection)
**Affected workflow:** Record invoice payment

**Files involved:**
- `supabase/migrations/20260825120000_operational_security_hardening.sql:82-96` — `record_invoice_payment_atomic`'s guard is `profiles.gym_id = any(auth_gym_ids())` with no role condition
- `supabase/migrations/20260826060000_fix_record_invoice_payment_interval.sql` — the legacy `record_invoice_payment`
- `lib/core/access/role_access.dart:16` — `canRecordPayment` excludes `trainer`

**What happens:**
*(a)* A trainer can call `record_invoice_payment_atomic` even though the UI never offers it to them. Contrast `collect_membership_renewal_atomic`, which correctly requires `role in ('owner','manager','staff')`.

*(b)* The legacy `record_invoice_payment` — kept alive for app installs that have not updated — inserts a payment for the **full `invoice.amount`** and marks the invoice paid, without summing existing succeeded payments. Its only guard is `status = 'paid'`, and a partially-paid invoice sits at `status = 'partial'`. An invoice of ₹1,000 with ₹400 already collected receives a further ₹1,000 payment, recording ₹1,400 against a ₹1,000 invoice. `get_revenue_report` sums the `payments` table, so revenue is overstated by the overlap.

**Failure scenario:**
A member pays ₹400 of a ₹1,000 invoice through the current app. A second staff member on an older build collects the ₹600 balance; their build calls the legacy RPC, which records ₹1,000. The month's revenue is ₹400 too high and the member's payment history shows a charge they did not make.

**Recommended fix:**
Add `role in ('owner','manager','staff')` to `record_invoice_payment_atomic`, matching its sibling. For the legacy RPC, either compute the remaining balance the way `record_invoice_payment_atomic` does, or drop it once telemetry shows no installs still call it — the cleaner option, given it exists only for backwards compatibility.

**How to verify:** As a trainer, call `record_invoice_payment_atomic`; expect rejection. Create a partially-paid invoice, call the legacy RPC, and assert the summed payments never exceed the invoice amount.

---

### [BUG-014] Seven maintenance and notification RPCs are executable by `PUBLIC`

**Severity:** Medium
**Confidence:** Confirmed
**Affected workflow:** Background jobs / notification delivery

**Live catalog evidence — `SECURITY DEFINER` functions where `PUBLIC` holds `EXECUTE`:**
`expire_overdue_members()`, `auto_checkout_stale_sessions()`, `trigger_push_reminders()`, `trigger_send_push_notifications()`, `trigger_billing_expiry_push()`, `trigger_owner_daily_summary()`, `trigger_whatsapp_credit_push()` (plus `increment_whatsapp_credits`, filed separately as BUG-002).

**What happens:**
Each `trigger_*` function reads the Vault-held cron secret and calls its edge function with it — so the edge functions' `CRON_SECRET` checks provide no protection against a caller who goes through the RPC. An anonymous caller holding only the app's public key can therefore fire owner push notifications, billing-expiry pushes and WhatsApp credit pushes at will, and can mass-mutate `members.status` platform-wide via `expire_overdue_members()` or force-close every open check-in via `auto_checkout_stale_sessions()`.

**Failure scenario:**
Every gym owner on the platform receives their daily summary push forty times in an hour. There is no rate limit, the OneSignal spend is real, and the source is indistinguishable from a legitimate cron run in the logs.

**Recommended fix:**
`revoke all on function public.<fn>() from public, anon, authenticated;` for each of the seven. These have no legitimate client caller — every one is invoked by `pg_cron` as `postgres`. Add the audit query from BUG-002 to the deployment checklist so newly created functions cannot reintroduce this.

**How to verify:** Call each from an anon client; expect `permission denied`. Confirm the cron jobs still run (`select * from cron.job_run_details order by start_time desc limit 20`).

---

### [BUG-015] Riverpod providers are not invalidated on the forced sign-out and Google OAuth paths

**Severity:** Medium
**Confidence:** High Confidence
**Affected workflow:** Account switching / session lifecycle

**Files involved:**
- `lib/main.dart:132-139` — forced `signOut()` on refresh-token failure, no invalidation
- `lib/features/auth/providers/auth_provider.dart:277-307` — `signUpWithGoogle` invalidates nothing
- `lib/features/auth/providers/auth_provider.dart:47,71,114,175` — `userTypeProvider`, `staffProfileProvider`, `gymIdProvider`, `memberRecordProvider` are all plain (non-`autoDispose`) `FutureProvider`s in a root `ProviderScope`

**What happens:**
`signIn`, `verifyEmailOtp` and `verifyPhoneOtpToken` each invalidate all four providers, and `AuthNotifier.signOut()` invalidates `gymIdProvider` (which cascades to `staffProfileProvider`). Two paths do neither: the forced sign-out triggered by a stale refresh token, and the Google OAuth return, where the session arrives through `supabase_flutter`'s own deep-link handler without passing through `AuthNotifier`. On those paths `userTypeProvider` and `memberRecordProvider` — neither of which depends on `gymIdProvider` — keep serving the previous account's cached values for the life of the process.

**Failure scenario:**
A gym's shared front-desk tablet. The manager's refresh token expires overnight; the app force-signs-out via `main.dart:136` without invalidating anything. A trainer signs in with Google. The router reads `home_route`, and the portal/profile providers still hold the manager's cached record until something forces a refetch — showing one person's data under another person's session.

**Recommended fix:**
Invalidate the four providers from a single place keyed off the auth stream rather than from each call site. In `main.dart`'s existing `onAuthStateChange` listener, invalidate on `signedOut` and `signedIn`; that covers every path including OAuth, and lets the per-method invalidations be removed. Making the four providers `autoDispose` would also work and is a smaller diff, at the cost of extra refetches.

**How to verify:** Sign in as A, force a token-refresh failure, sign in as B via Google, and assert every screen shows B's data with no restart.

---

### [BUG-016] `verify-phone-otp`: member lookup is capped at 1000 rows, and staff phone matching can grant the wrong session

**Severity:** Medium
**Confidence:** Confirmed (pagination) / High Confidence (phone matching)
**Affected workflow:** Member self-signup / phone OTP login

**Files involved:**
- `supabase/functions/verify-phone-otp/index.ts:76-104` — `findOrCreateMemberUserId`
- `supabase/functions/verify-phone-otp/index.ts:106-130` — `findOrCreateUserId`

**What happens:**
*(a)* `findOrCreateMemberUserId` selects **all** members of the gym with no `range()` and filters in JavaScript. PostgREST caps unbounded responses (default 1000 rows). Members beyond that cap are invisible to the matcher and receive "No member found with this number at this gym" — a message that tells them to ask their gym to add them, which the gym already has. The failure is silent, correlates with gym size, and gets worse as a customer grows.

*(b)* `findOrCreateUserId` (the staff phone-OTP path) resolves an account by matching `profiles.phone` or `members.phone`. Those columns are free-text, staff-entered, never normalized on write and not unique, while `normalizePhone` force-prefixes `91`. A typo in a staff member's profile phone that happens to be a real number lets that number's owner obtain a session for the account. Two profiles sharing a phone makes `.maybeSingle()` throw and the login fail outright.

**Mitigation in place:** the staff phone-OTP button is currently commented out, so *(b)* is not reachable from the shipping app. The member-signup path *(a)* is live. This also intersects the known unfixed country-code normalization issue.

**Recommended fix:**
For *(a)*, filter server-side instead of in JS: normalize the incoming phone, then query `members` with an `or()` of the plausible stored formats, or add a generated normalized-phone column with an index and match on it exactly. For *(b)*, before re-enabling the staff path, resolve identity only through `phone_identities` (a table that exists for exactly this purpose) and require an explicit in-app link step to populate it — never infer an identity from an unverified free-text column.

**How to verify:** Seed a gym with 1200 members and attempt self-signup as member 1150; expect success.

---

### [BUG-017] Blocked-check-in owner alerts never fire for branch gyms

**Severity:** Medium
**Confidence:** Confirmed
**Affected workflow:** Owner notification on expired-member check-in attempt

**Files involved:**
- `supabase/migrations/20260825120000_operational_security_hardening.sql:160-163` — `select id into v_owner_id from profiles where gym_id = p_gym_id and role = 'owner' limit 1;`

**What happens:**
The owner is resolved through `profiles.gym_id`, which only ever holds the *primary* gym. `create_gym_branch` explicitly does not touch it. For any branch gym no profile matches, `v_owner_id` is null, and the function returns silently without inserting the notification. The caller cannot tell the difference between "alerted" and "did nothing".

**Failure scenario:**
An expired member is turned away at a branch location. The owner, who monitors these alerts to spot renewal opportunities and staff overrides, is never told — for that location only. They reasonably conclude no one has been turned away there.

**Recommended fix:**
Resolve the owner through `staff_gym_access` instead:

```sql
select profile_id into v_owner_id
from staff_gym_access where gym_id = p_gym_id and role = 'owner' limit 1;
```

Then grep for other `profiles.gym_id` reads on server-side paths — `revenuecat-webhook`'s `getGymId()` (BUG-003) is the same defect in a costlier place.

**How to verify:** Attempt an expired-member check-in at a branch; assert a `push_notifications` row is created for the owner.

---

### [BUG-018] Biometric ADMS endpoint authenticates gyms by device serial number over plain HTTP

**Severity:** Medium
**Confidence:** High Confidence
**Affected workflow:** Biometric check-in

**Files involved:**
- `supabase/functions/biometric-adms/index.ts:1-30` — documented device config specifies `HTTPS: OFF`
- `supabase/migrations/20260820150000_biometric_device_sn_unique.sql`

**What happens:**
Gym identity comes solely from the `?SN=` query parameter the device appends. There is no shared secret, no signature, and the documented device configuration disables TLS. The function then writes `check_ins` with the service-role client.

**Failure scenario:**
A serial number is printed on a sticker on the device and is visible to any member standing at it. Anyone who notes it can POST forged ATTLOG records to that gym, inflating attendance or fabricating a member's presence on a given date — which matters if attendance is ever used to settle a dispute. Because the device speaks cleartext HTTP, the serial is also observable on any shared network path.

**Constraint worth stating:** ZKTeco/eSSL ADMS firmware does not support bearer tokens, so a per-device shared secret is not straightforwardly available within the protocol. This is a real limitation, not an oversight.

**Recommended fix:**
Move the endpoint behind TLS where the firmware supports it. Add a per-device pairing secret carried in the server path (`Server Path` is configurable on these devices and is included in the request URI), IP-allowlist the gym's egress address on the `biometric_devices` row, and rate-limit per serial. At minimum, log and surface punches from unrecognised serials rather than discarding them.

**How to verify:** POST an ATTLOG for a valid serial from an unrelated host and assert it is rejected once pairing is enforced.

---

### LOW

**[BUG-019] `auto_checkout_stale_sessions` fabricates 4-hour sessions.** It sets `checked_out_at = checked_in_at + interval '4 hours'` for every session open longer than four hours. Any member who does not scan out — the common case — gets a recorded 4-hour visit. Session-duration figures derived from `check_ins` are therefore synthetic for a large share of rows. Consider recording a `auto_closed` flag so reporting can exclude them.

**[BUG-020] Raw database errors are shown to gym staff.** `lib/features/staff/check_in/check_in_screen.dart:305-307` returns `subtitle: '$e'`, putting Postgrest exception text (including constraint and function names) in front of end users. Map known error codes to plain messages, as the Add Member screen does for `23505`.

**[BUG-021] Seven tables have RLS enabled with no policies at all.** `admin_comms_log`, `announcements`, `customer_notes`, `feature_flags`, `impersonation_audit`, `platform_admins`, `super_admins`. This is deny-all for non-service-role callers, which is safe. Confirm it is intended for `announcements` and `feature_flags` — if the app is expected to read either, it currently receives an empty list with no error, which will present as a missing feature rather than a permissions problem.

**[BUG-022] A migration claims a fix it does not contain.** `20260826051227_respect_plan_billing_interval.sql` is byte-for-byte identical to `20260826050623_guard_repeated_renewal_collection.sql` (both `md5 = 2ceeb1b7a601a7fef6aaa3d9f2e340e7`). The billing-interval logic the filename advertises is present in both, so the deployed behaviour is correct — but the history now records a fix that was actually shipped in the previous migration. The genuine interval fix for the *legacy* RPC is `20260826060000`. Worth a note in the file so a future reader does not chase a phantom change.

---

## 5. Systemic architectural risks

These patterns will keep producing bugs until they are addressed as patterns.

**1. `REVOKE … FROM anon, authenticated` is used as though it removed public access.** It does not touch the default `GRANT … TO PUBLIC`. Eight `SECURITY DEFINER` functions are publicly executable today, including two the migration history documents as fixed (BUG-002, BUG-014). Every future function inherits the same default. *Evidence:* `20260723_close_public_rpc_and_storage_holes.sql:23` vs. the live `proacl` for `increment_whatsapp_credits`.

**2. `SECURITY DEFINER` RPCs are not held to the RLS policies they bypass.** RLS was tightened to owner/manager for `memberships`, `membership_plans` and `members`, while the definer RPCs that write those same tables kept a gym-membership check only. Every time a policy gains a role condition, the corresponding RPC must too. *Evidence:* BUG-005, BUG-013.

**3. Server-side code still resolves the gym through `profiles.gym_id`.** The 2026-08-23 multi-gym pass migrated RLS and most RPCs to `auth_gym_ids()` but left `profiles.gym_id` reads in the RevenueCat webhook and `notify_owner_expired_checkin`. Each surviving read is a feature that quietly does not work for branch gyms. A grep for `profiles.gym_id` outside `auth_gym_ids()` would enumerate the rest. *Evidence:* BUG-003, BUG-017.

**4. Multi-step business workflows are not transactional, and their failures are indistinguishable.** Add Member and CSV Import each perform 3-4 sequential writes with no transaction, no compensation, and a single generic error message that invites a duplicating retry. The codebase already demonstrates the right pattern — `collect_membership_renewal_atomic` locks, compare-and-sets and validates in one transaction. Extend it to the remaining creation flows. *Evidence:* BUG-008.

**5. Business rules are enforced in the Flutter screen rather than in the shared function.** Membership-status checking lives in `check_in_screen.dart`, so the offline path skips it. Role gating lives in `RoleAccess`, so the API skips it. Billing entitlement lives in `StaffShell`, so twelve routes and the entire API skip it. The rule belongs at the point every caller passes through. *Evidence:* BUG-009, BUG-012, BUG-013.

**6. Triggers and their calling RPCs are written independently.** `trg_create_invoice_for_membership` reads member state that its caller mutates one statement later. Any `AFTER INSERT` trigger reading a row the transaction is about to change is a correctness hazard; the ordering must be part of the RPC's design, not an accident of it. The hardcoded `v_pilot_gym` UUID inside that trigger is a related smell — per-tenant branching in shared server logic. *Evidence:* BUG-004.

**7. Client and server disagree about what "today" means.** The server is IST-aware (`expire_overdue_members`); the client sends offsetless local timestamps that Postgres reads as UTC; `generate_monthly_invoices` uses UTC `current_date`. Three notions of a day in one billing product. *Evidence:* BUG-011.

**8. Failures on background paths are `debugPrint`-ed and dropped.** The offline flush loop, the invoice-WhatsApp triggers (fire-and-forget `net.http_post`), and `ActivityLogService` calls all fail without any signal reaching staff or an error table. Route these through the existing `error_logs` table, which `biometric-adms` already uses well.

---

## 6. Recommended priority order

| # | Bug | Why this position |
|---|---|---|
| 1 | **BUG-001** `get_revenue_report` cross-tenant read | Active data breach; ~10-line fix |
| 2 | **BUG-002** `increment_whatsapp_credits` public | Active revenue bypass; one-line fix |
| 3 | **BUG-014** seven public `trigger_*` RPCs | Same root cause as #2 — fix in the same migration |
| 4 | **BUG-004** plan-change double-billing | Charging real end customers twice; two-line reorder |
| 5 | **BUG-006** invoices directly mutable by staff | Embezzlement channel; guard trigger |
| 6 | **BUG-005** `change_member_plan` role check | Same migration as #5 |
| 7 | **BUG-003** branch entitlement | Paying customers locked out; ship the paywall branch switcher first as a stopgap |
| 8 | **BUG-007** unauthenticated WhatsApp platform run | Cost + reliability across all tenants |
| 9 | **BUG-009** offline check-in queue | Silent permanent data loss |
| 10 | **BUG-008** non-atomic add member | Silent revenue leakage |
| 11 | **BUG-013** payment RPC role + legacy over-collection | |
| 12 | **BUG-010** demo data in reports | Cheap; fold into #1 |
| 13 | **BUG-011** timezone handling | Cheap; visible daily |
| 14 | **BUG-015** provider invalidation | Cross-account display on shared devices |
| 15 | **BUG-012** paywall coverage | |
| 16 | **BUG-016**, **BUG-017**, **BUG-018** | |
| 17 | **BUG-019** – **BUG-022** | Housekeeping |

Items 1-3 and 12 are a single migration. Items 5-6 are a single migration. Item 4 is a two-line reorder inside one function. A large share of the critical and high severity surface closes in roughly three migrations.

---

## 7. Suggested regression tests

**T1 — Cross-tenant report isolation (BUG-001).**
Create gyms A and B with distinct invoice data. As a signed-in member of A, call `get_revenue_report(B.id, '2020-01-01', 'year')`. Expect `unauthorized: gym mismatch`. As a manager of B, expect correct data — repeat while B's manager has a secondary branch active, to confirm `auth_gym_ids()` (not `auth_gym_id()`) is used.

**T2 — Public execute audit (BUG-002, BUG-014).**
Assert this returns zero rows, and wire it into CI so a new function cannot reintroduce the default grant:
```sql
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and (p.proacl is null or array_to_string(p.proacl, ',') like '=X/%')
  and p.proname not in ('resolve_gym_by_member_code');
```

**T3 — Plan change bills exactly one period (BUG-004).**
Member with an active monthly plan and `next_payment_date = today + 20`. Call `change_member_plan` with `p_next_payment_date = today + 30`. Assert exactly one new `invoices` row, with `due_at = today + 30`. Run `generate_monthly_invoices()` on that date; assert the invoice amount equals one plan period and its description contains no carried-forward clause.

**T4 — Plan re-assignment does not re-bill a paid period (BUG-004b).**
Assign a plan, collect the invoice in full, re-assign the same plan without changing the date. Assert no second invoice is created — for a gym other than the pilot UUID.

**T5 — Role matrix, backend-enforced (BUG-005, BUG-006, BUG-013).**
For each of `trainer` and `staff`, attempt: `change_member_plan`, `record_invoice_payment_atomic`, `PATCH /invoices {status:'paid'}`, `PATCH /invoices {amount:1}`, `PATCH /membership_plans`. Assert each is refused for `trainer`, and that `staff` is refused everything except `record_invoice_payment_atomic`. Assert `owner` and `manager` succeed at all of them. Run the whole matrix against a secondary branch as well.

**T6 — Branch entitlement (BUG-003).**
Owner with an active Pro subscription creates a branch. Set the branch's `trial_ends_at` to the past. Switch to it. Assert the full shell renders, not the paywall. Separately assert that from `PaywallScreen` a multi-branch owner can always reach the branch switcher.

**T7 — Offline queue terminal failures (BUG-009).**
Enqueue three check-ins; rewrite `queued_at` to 30 hours ago; flush. Assert the queue empties, `pendingCount()` is 0, and staff see a message naming the dropped count. Flush a single item twice with the first response dropped; assert exactly one `check_ins` row. Enqueue for an `expired` member; assert `insert_checkin_secure` rejects it and a `push_notifications` row is created for the owner.

**T8 — Add member atomicity (BUG-008).**
Inject a failure into the `memberships` insert. Assert no orphan `members` row survives, or that the UI reports the partial state specifically and does not invite a blind retry. Then assert `generate_monthly_invoices()` reports `skipped = 0` for that gym.

**T9 — Timezone boundary (BUG-011).**
Device clock at 05:00 IST. Record a check-in. Assert the dashboard's today count and the check-in screen's today list both include it.

**T10 — WhatsApp endpoint authorization (BUG-007).**
`POST /functions/v1/whatsapp-reminders` with `{}` and the anon key: expect 401. With `{"gym_id": <own>}` as a manager: expect 200. With `{"gym_id": <other gym>}` as that same manager: expect 403.

**T11 — Account switching (BUG-015).**
Sign in as A; force a refresh-token failure; sign in as B via Google. Assert no screen shows A's gym, profile or member record without a restart.

**T12 — Reports exclude demo data (BUG-010).**
For a gym holding demo rows, assert `get_revenue_report` and the `owner-daily-summary` payload report identical revenue and member counts.

---

*Audit performed read-only against the repository at commit `da4e158` and the live Supabase project `orlqjhqxeyukvfzsursl`. No repository file was modified and no database write was issued. Findings marked **Confirmed** have complete code or catalog evidence for every link in the failure chain; findings marked **High Confidence** have exactly one link inferred rather than directly observed, and that link is named in the finding.*
