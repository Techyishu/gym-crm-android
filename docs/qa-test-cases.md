# GymCRM Android — Exhaustive QA Test Plan

Derived from source, not guesswork. Every case names the code path it exercises.

**Legend** — Type: `F` functional · `E` edge · `R` regression · `O` offline · `P` performance · `S` security · `A` accessibility.
Priority: `P0` blocker (money, auth, data loss) · `P1` major · `P2` minor.

---

## 0. Test environment & data

### 0.1 Device matrix

| Class | Device | OS | Why |
|---|---|---|---|
| Low-end | 2GB RAM, Android 8 | API 26 | perf floor, `POST_NOTIFICATIONS` absent, scoped storage absent |
| Mid | 4GB, Android 12 | API 31 | runtime notification perm boundary (API 33 is the cut) |
| Modern | 8GB, Android 14/15 | API 34/35 | scoped storage, photo picker, predictive back |
| Tablet / foldable | 10" + fold | any | `StatefulShellRoute` layout, bottom nav 66+inset height |
| iOS | iPhone SE + Pro Max | iOS 16/18 | `Platform.isIOS` branches: RevenueCat gate, "Create Gym" label, hidden subscribe |

Also cover: font scale 0.85 / 1.0 / 1.3 / 2.0, display size largest, dark-mode OS setting, RTL pseudo-locale, `hi-IN` + `en-US` locales, airplane mode, 2G throttle (Charles/Network Link Conditioner), battery saver, "Don't keep activities" ON.

### 0.2 Accounts required

| # | Account | Notes |
|---|---|---|
| A1 | Owner, gym on active trial | `trial_ends_at` future |
| A2 | Owner, trial expired, no plan | must hit paywall |
| A3 | Owner, `plan=pro`, `plan_expires_at=null` | grandfathered |
| A4 | Owner, `plan=pro` + `dodo_subscription_id` + future expiry | recurring |
| A5 | Owner, gym `status='suspended'` with future expiry | must still be blocked |
| A6 | Manager | full minus owner-only |
| A7 | Trainer | no check-in, no billing, no PII |
| A8 | Staff | no classes-management, no leads/reports/settings |
| A9 | Member (portal) with active membership | |
| A10 | Member, no membership, no plans assigned | empty states |
| A11 | Auth user with **no** `profiles` and **no** `members` row | → `/gym-setup` |
| A12 | Member of gym X used against gym Y QR | cross-gym security |
| A13 | Gym with 5,000+ members, 20k check-ins | perf/pagination |

---

## 1. Cross-cutting suites

### 1.1 CC-AUTH — session & token (`auth_provider.dart`, `router.dart`)

| ID | Title | Steps | Expected | Type | Pri |
|---|---|---|---|---|---|
| CC-AUTH-01 | Cold start signed in | Kill app, relaunch | Lands on cached `home_route` with no visible login flash | F | P0 |
| CC-AUTH-02 | Cold start signed out | Clear session, launch | `/login`; `home_route` key removed from prefs | F | P0 |
| CC-AUTH-03 | Access token expiry mid-session | Idle >1h, then act | Silent refresh; no 401 toast | F | P0 |
| CC-AUTH-04 | Refresh token revoked server-side | Revoke in Supabase, tap any action | Redirect to `/login`, no infinite spinner | E | P0 |
| CC-AUTH-05 | Sign out clears cache | Sign out, sign in as **different** role | Nav tabs match new role, not previous (`home_route` + `gymIdProvider` invalidated) | R | P0 |
| CC-AUTH-06 | Sign out during in-flight request | Tap sign out while list loading | No "setState after dispose", no crash | E | P1 |
| CC-AUTH-07 | Two devices, sign out on one | Other device continues | Other stays valid until its own token expires; no data leak | S | P1 |
| CC-AUTH-08 | `gymIdProvider` throws for A11 | Force staff route for account with null `gym_id` | "No gym assigned — please complete gym setup", not a raw exception | E | P1 |
| CC-AUTH-09 | Session expired during payment record | Expire token, tap Save on collect sheet | "Session expired. Please sign in again." snackbar, **no** duplicate payment row | S | P0 |
| CC-AUTH-10 | Google OAuth cancel | Start Google sign-in, press back on browser | Returns to login, button re-enabled, no stuck spinner | E | P1 |
| CC-AUTH-11 | OAuth deep-link `io.supabase.gymcrm://login-callback` | Complete Google auth | Router's non-http scheme branch sends user to `home_route`/`/login`, never a 404 page | R | P0 |
| CC-AUTH-12 | `gymcrm://payment-success` deep link | Open link while app cold | No 404 route; lands on valid screen | R | P1 |
| CC-AUTH-13 | Deep link while signed out | Open `gymcrm://…` unauthenticated | `/login`, no crash | S | P1 |
| CC-AUTH-14 | Concurrent provider invalidation | Sign in → immediately background app | Providers resolve or cancel cleanly; on resume dashboard populated | E | P2 |

### 1.2 CC-NAV — routing & back stack

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CC-NAV-01 | Hardware back on each staff branch root | Exits app (or shows nothing weird); does not jump between branches | F | P1 |
| CC-NAV-02 | Back from `/staff/members/:id` | Returns to member list preserving scroll + filter | R | P1 |
| CC-NAV-03 | Re-tap active bottom tab | Pops branch to its root (`initialLocation: true`) | F | P2 |
| CC-NAV-04 | Deep push chain: More→Reports→back | Returns to previous branch, "More" highlight cleared | F | P2 |
| CC-NAV-05 | Predictive back (Android 14 gesture) | No frame flicker / black screen | E | P2 |
| CC-NAV-06 | `/invoice/:id` with garbage id | Error state, not crash | E | P1 |
| CC-NAV-07 | `/staff/members/:id` with id of another gym's member | No data leaked; not-found state | S | P0 |
| CC-NAV-08 | Rotate device on every screen | State preserved; no rebuild loss of typed form data | E | P1 |
| CC-NAV-09 | "Don't keep activities" ON, background/return on each screen | Screen rebuilds without crash | E | P1 |
| CC-NAV-10 | Firebase screen_view logging | Each nav logs exactly one `logScreenView` (dedup via `lastScreen`) | R | P2 |
| CC-NAV-11 | Branch-switch during in-flight fetch | No cross-branch data bleed | E | P1 |

### 1.3 CC-RBAC — role matrix (`role_access.dart`)

Run the whole grid for A6/A7/A8 plus owner. Expected column derived directly from `RoleAccess`.

| ID | Surface | owner | manager | trainer | staff | Type | Pri |
|---|---|---|---|---|---|---|---|
| CC-RBAC-01 | Billing tab visible | ✔ | ✔ | ✘ | ✔ | S | P0 |
| CC-RBAC-02 | Check-in center button | ✔ | ✔ | ✘ | ✔ | S | P0 |
| CC-RBAC-03 | More → Batches | ✔ | ✔ | ✔ | ✔ | F | P1 |
| CC-RBAC-04 | More → Leads | ✔ | ✔ | ✘ | ✘ | S | P0 |
| CC-RBAC-05 | More → Reminders | ✔ | ✔ | ✘ | ✘ | S | P1 |
| CC-RBAC-06 | More → Staff & roles | ✔ | ✔ | ✘ | ✘ | S | P0 |
| CC-RBAC-07 | More → Reports | ✔ | ✔ | ✘ | ✘ | S | P1 |
| CC-RBAC-08 | More → Settings | ✔ | ✔ | ✘ | ✘ | S | P0 |
| CC-RBAC-09 | More → Workout/Diet plans | ✔ | ✔ | ✔ | ✔ | F | P1 |
| CC-RBAC-10 | Member email/phone shown | ✔ | ✔ | ✘ | ✘ | S | P0 |
| CC-RBAC-11 | Edit/delete member | ✔ | ✔ | ✘ | ✘ | S | P0 |
| CC-RBAC-12 | **Direct route push** of a hidden route (`context.push('/staff/reports')` via deep link) as trainer | Blocked or empty, never full data | S | P0 |
| CC-RBAC-13 | Server-side enforcement | With trainer JWT, call the same PostgREST query the hidden screen uses | RLS denies; UI hiding is not the only control | S | P0 |
| CC-RBAC-14 | Role changed while app open | Change role in DB, pull-to-refresh | Nav recomputes after `staffProfileProvider` refresh; document if it needs relaunch | E | P1 |
| CC-RBAC-15 | Unknown/null role | Set `role='viewer'` | Nav degrades safely (no billing/check-in), no crash | E | P1 |

### 1.4 CC-BILL — paywall gate (`billing_access.dart`, `staff_shell.dart`)

| ID | Gym state | Expected | Type | Pri |
|---|---|---|---|---|
| CC-BILL-01 | `status='suspended'`, expiry future | Paywall shown (status wins) | S | P0 |
| CC-BILL-02 | `status='cancelled'` | Paywall | S | P0 |
| CC-BILL-03 | `plan='pro'`, `plan_expires_at=null` | Full access | F | P0 |
| CC-BILL-04 | `plan='pro'` + dodo id + expiry yesterday | Paywall | E | P0 |
| CC-BILL-05 | `plan='starter'`, expiry tomorrow | Access | F | P1 |
| CC-BILL-06 | Trial ends in 1 day, Android | Access + expiry banner | F | P0 |
| CC-BILL-07 | Trial active, **iOS** | Paywall (`ignoreTrial: true`) unless RevenueCat entitlement | F | P0 |
| CC-BILL-08 | Expiry exactly `now` | Blocked (`isAfter` strict) — confirm intended | E | P1 |
| CC-BILL-09 | Malformed `plan_expires_at` string | `tryParse` null → treated as no access, no crash | E | P1 |
| CC-BILL-10 | Device clock set 1 year forward | Paywall appears; document that clock is trusted | S | P1 |
| CC-BILL-11 | Device clock 1 year back with expired plan | Access wrongly granted → confirm server also enforces on writes | S | P0 |
| CC-BILL-12 | Timezone UTC+14 / UTC-11 on expiry day | Consistent (all comparisons `.toUtc()`) | E | P1 |
| CC-BILL-13 | Gym row null (network fail on profile) | `hasActiveBillingAccess(null)=false` → paywall on transient error? Verify UX doesn't paywall on a flaky network | E | P0 |
| CC-BILL-14 | Plan renewed on web while app open | Pull-to-refresh restores access without reinstall | R | P1 |
| CC-BILL-15 | `trialDaysRemaining` at 0 days | Banner copy sane, no "0 days left" duplicate of expired state | E | P2 |

### 1.5 CC-OFF — offline & connectivity (`offline_checkin_queue.dart`)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CC-OFF-01 | Airplane mode on every screen | Error/empty state with retry, never white screen or raw stack trace | O | P0 |
| CC-OFF-02 | `isOnline()` with captive-portal wifi | DNS lookup to 8.8.8.8 succeeds/fails deterministically; check-in path picks the right branch | O | P1 |
| CC-OFF-03 | `isOnline()` on network with DNS blocked but internet up | Falsely offline → check-in queues; verify flush later succeeds and no duplicate | E | P1 |
| CC-OFF-04 | Queue check-in offline, reconnect | Banner count decrements, RPC `insert_checkin_secure` inserts with original `queued_at` | O | P0 |
| CC-OFF-05 | Queue 50 items, flush | All flush; partial failures stay queued; count accurate | O | P1 |
| CC-OFF-06 | Flush with expired session | Items remain queued, no data loss | O | P0 |
| CC-OFF-07 | Queue then sign out then sign in as other gym staff | Queued items must not insert into the wrong gym (server re-validates) | S | P0 |
| CC-OFF-08 | Enqueue with malformed member id | `ArgumentError` thrown, queue not polluted, UI shows failure not crash | E | P1 |
| CC-OFF-09 | Offline with no cached `gym_id` | Clear "sign in online once first" style failure, not a silent no-op | O | P1 |
| CC-OFF-10 | Duplicate offline check-in same member twice | Server `23505` on flush → item dropped or surfaced, never infinite retry loop | E | P1 |
| CC-OFF-11 | App killed with pending queue | Queue survives (SharedPreferences) | O | P0 |
| CC-OFF-12 | Clear app storage with pending queue | Data lost — verify no crash on next launch | E | P2 |
| CC-OFF-13 | 3s lookup timeout on very slow network | Check-in path doesn't hang >3s before falling back | P | P1 |
| CC-OFF-14 | Offline writes on non-queued screens (add member, payment) | Explicit failure message; nothing silently dropped | O | P0 |
| CC-OFF-15 | Network flaps mid-upload (photo/PDF) | Partial upload cleaned up or retried; no orphan storage object | E | P1 |

### 1.6 CC-PERF

| ID | Title | Target | Type | Pri |
|---|---|---|---|---|
| CC-PERF-01 | Cold start to first frame (low-end) | < 3s; `home_route` cache avoids DB round trip | P | P0 |
| CC-PERF-02 | Warm start | < 1s | P | P1 |
| CC-PERF-03 | Dashboard with A13 dataset | 12 parallel queries complete < 2.5s; skeleton visible meanwhile | P | P0 |
| CC-PERF-04 | Members list scroll, 5k rows | Jank < 16ms/frame p95; verify pagination/limit exists (profile with DevTools) | P | P0 |
| CC-PERF-05 | Check-in "recent today" with 500 check-ins | Loads < 1.5s | P | P1 |
| CC-PERF-06 | Reports RPC (`get_revenue_report`) 12-month range | < 3s; loading indicator | P | P1 |
| CC-PERF-07 | Member photo grid | Signed/Worker URLs cached; no repeated network per scroll (CachedNetworkImage) | P | P1 |
| CC-PERF-08 | QR scanner CPU/battery | Camera stops on tab change & dispose; no background camera drain | P | P0 |
| CC-PERF-09 | Memory after 20 navigations | No monotonic growth; providers disposed | P | P1 |
| CC-PERF-10 | CSV import 1,000 rows | Batched 100/insert; progress label updates; UI not ANR | P | P0 |
| CC-PERF-11 | Rapid double-tap on every submit button | Exactly one write (loading guard) | R | P0 |
| CC-PERF-12 | APK/AAB size + Shorebird patch size | Track deltas per release | P | P2 |

### 1.7 CC-SEC

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CC-SEC-01 | Anon key scope | Anon key in `--dart-define` can't read other gyms via direct PostgREST | S | P0 |
| CC-SEC-02 | RLS on every table used (`members`, `invoices`, `payments`, `check_ins`, `leads`, `classes`, `class_enrollments`, `workout_plans`, `diet_plans`, `support_tickets`, `gyms`, `profiles`) | Cross-gym read/write denied with a captured JWT | S | P0 |
| CC-SEC-03 | `insert_checkin_secure` with foreign member id | Denied | S | P0 |
| CC-SEC-04 | `self_checkin` with another gym's token | Denied / `ok:false` | S | P0 |
| CC-SEC-05 | `setup_gym` called twice by same user | Second call rejected (no duplicate gyms) | S | P0 |
| CC-SEC-06 | `save_razorpay_keys` secret never returned | Confirm `gyms` select never exposes secret; screen shows masked | S | P0 |
| CC-SEC-07 | Member photo Worker auth | Request photo URL without Bearer token → 401/403 | S | P0 |
| CC-SEC-08 | Member photo of another gym with valid token | Worker rejects on gymId prefix mismatch | S | P0 |
| CC-SEC-09 | Invoice PDF public URL (`invoice-pdfs` bucket) | Determine if URL is guessable; PII exposure risk documented | S | P0 |
| CC-SEC-10 | Screenshot/recents obfuscation | Decide policy for member PII; currently no FLAG_SECURE | S | P2 |
| CC-SEC-11 | Logs contain no PII/token | `debugPrint` output in release build stripped/no secrets | S | P1 |
| CC-SEC-12 | Clipboard content | Copied member ID / check-in link contains no secret token beyond intended | S | P2 |
| CC-SEC-13 | Backup rules | `allowBackup` — SharedPreferences hold session + queue; verify policy | S | P1 |
| CC-SEC-14 | Rooted/emulator | App runs; no additional trust placed on client | S | P2 |
| CC-SEC-15 | Deep-link injection: `gymcrm://…//staff/settings` variations | Never bypasses the consent/auth/paywall gates | S | P0 |
| CC-SEC-16 | Certificate pinning absent → MITM proxy | Traffic readable; document accepted risk or add pinning | S | P1 |
| CC-SEC-17 | Input with SQL/HTML payload (`'; DROP`, `<script>`) in every text field | Stored/escaped safely, renders as text, PostgREST parameterised | S | P1 |
| CC-SEC-18 | 10k-char paste into notes | maxLength enforced (500 for notes) client + server | E | P1 |
| CC-SEC-19 | Camera permission denied permanently | Graceful message + settings link; no crash loop | S | P1 |
| CC-SEC-20 | `POST_NOTIFICATIONS` denied (API 33+) | OneSignal path handles denial silently | E | P1 |
| CC-SEC-21 | AD_ID permission + ads consent OFF | No Meta `logEvent` fires (`AppEvents._adsConsented` gate) | S | P0 |

### 1.8 CC-A11Y

| ID | Title | Expected | Pri |
|---|---|---|---|
| CC-A11Y-01 | TalkBack on every screen | All actionable widgets have labels; bare `GestureDetector` nav tabs announce | P1 |
| CC-A11Y-02 | Font scale 2.0 | No clipped text on nav labels (10px), stat cards, pill buttons | P1 |
| CC-A11Y-03 | Contrast | `inkHint` on `surface` ≥ 4.5:1 | P2 |
| CC-A11Y-04 | Touch targets | Nav tabs, `RoundIconButton`, pill buttons ≥ 48dp | P1 |
| CC-A11Y-05 | Focus order in bottom sheets | Logical; keyboard doesn't cover the submit button | P1 |
| CC-A11Y-06 | Reduce-motion | Showcase tour/animations respect setting | P2 |

### 1.9 CC-FMT — currency, dates, locale (`formatters.dart`)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CC-FMT-01 | Gym currency INR | `₹`, lakh compaction `₹1.20L` at ≥100000 | F | P1 |
| CC-FMT-02 | Gym currency USD | `$120K` compact path, symbol everywhere incl. sheet labels `Amount ($) *` | F | P1 |
| CC-FMT-03 | Currency changed in Settings | All screens reflect after refresh; no stale `₹` (global mutable `_currencyCode`) | R | P1 |
| CC-FMT-04 | Two accounts different currencies, switch without restart | No leak of previous gym's symbol | R | P0 |
| CC-FMT-05 | Amount 999999999 | No overflow, `FittedBox` scales | E | P2 |
| CC-FMT-06 | Amount 0 / negative (refund) | Renders sanely | E | P2 |
| CC-FMT-07 | `formatDateFromString(null / "garbage")` | `-` / echoes raw, no throw | E | P1 |
| CC-FMT-08 | `timeAgo` with future timestamp | No "-5m ago" nonsense | E | P2 |
| CC-FMT-09 | DST / timezone change mid-session | Dates stable | E | P2 |
| CC-FMT-10 | Device locale `hi-IN` | `DateFormat` output readable; no crash from missing locale data | E | P1 |

### 1.10 CC-REL — release plumbing

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CC-REL-01 | `UpdatePrompt.check()` with update live | Flexible update downloads, completes | F | P1 |
| CC-REL-02 | Sideloaded build | `check()` swallows error silently | E | P1 |
| CC-REL-03 | `ReviewPrompt.recordSuccess()` at 10th & 100th success | Play card requested once each (`review_asked_at_count`) | F | P2 |
| CC-REL-04 | Review prompt below milestone | No API call | F | P2 |
| CC-REL-05 | Shorebird patch applied | Dart-only change live after relaunch; native unchanged | R | P1 |
| CC-REL-06 | Patch containing a plugin change | Verify it is NOT shipped as patch (would crash) — `MissingPluginException` path in CSV import proves the risk | R | P0 |

---

## 2. Auth & onboarding screens

### 2.1 ONB — `onboarding_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| ONB-01 | First install | Slides shown; router forces `/onboarding` | F | P0 |
| ONB-02 | Swipe through all slides | Last slide CTA reads "Create your gym" | F | P1 |
| ONB-03 | Tap Skip on slide 1 | Goes to login; `onboarding_done=true` | F | P1 |
| ONB-04 | Relaunch after completing | Never shown again (`/onboarding` → `/login`) | R | P0 |
| ONB-05 | Logged-in user with cleared prefs | Onboarding shown once then normal (documented behaviour) | E | P1 |
| ONB-06 | Kill app mid-slides | Restarts at slide 1, flag not set | E | P2 |
| ONB-07 | Rapid double tap "Next" on last slide | Single navigation | R | P1 |
| ONB-08 | Font scale 2.0 / small screen | No overflow on slide copy | A | P2 |

### 2.2 CON — `consent_screen.dart` (DPDP gate)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CON-01 | Reached after onboarding, before login | Cannot proceed past `/consent` without agreeing | F | P0 |
| CON-02 | Default toggle states | analytics/marketing/ads default true on first view | F | P1 |
| CON-03 | Turn all off → Agree & continue | Prefs written `false`; `kConsentGiven=true` | F | P0 |
| CON-04 | Ads consent OFF | Meta `logEvent` never fires on signup/purchase (verify with Meta SDK debug) | S | P0 |
| CON-05 | Analytics consent OFF | `FirebaseAnalytics.setAnalyticsCollectionEnabled(false)` applied | S | P0 |
| CON-06 | Reopen from Settings → Privacy choices | Shows saved values; button reads "Save choices"; back works (canPop branch) | F | P1 |
| CON-07 | Privacy / Terms links | Open `/legal/*` and back returns to consent, still gated | F | P1 |
| CON-08 | Kill app on consent screen | Still gated on relaunch | E | P0 |
| CON-09 | v1→v2 migration (`dpdp_consent_v2`) | Users who consented to v1 are re-asked (ads split out) | R | P1 |
| CON-10 | Save while offline | Prefs are local — succeeds; snackbar "Privacy choices saved" | O | P2 |
| CON-11 | Double-tap Save | One write, no double navigation | R | P1 |

### 2.3 LOG — `login_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| LOG-01 | Valid staff credentials | Lands `/staff/dashboard`; `home_route` cached; `login` activity logged | F | P0 |
| LOG-02 | Valid member credentials | Lands `/portal/home` | F | P0 |
| LOG-03 | Wrong password | AuthException message shown inline, field values retained | F | P0 |
| LOG-04 | Unknown email | Generic error, no user enumeration | S | P1 |
| LOG-05 | Empty email | "…" validator fires, no network call | F | P1 |
| LOG-06 | Empty password | "Password is required" | F | P1 |
| LOG-07 | Email with spaces / uppercase | Trimmed & case-insensitive success | E | P1 |
| LOG-08 | Password visibility toggle | Obscure flips; value preserved | F | P2 |
| LOG-09 | Submit twice fast | One request (`_loading` guard) | R | P0 |
| LOG-10 | Airplane mode submit | "Something went wrong…" not a raw socket error | O | P1 |
| LOG-11 | Slow 2G | Spinner shown, button disabled, no timeout crash | P | P1 |
| LOG-12 | Google sign-in success (new user) | Router resolves → `/gym-setup` | F | P0 |
| LOG-13 | Google sign-in success (existing staff) | Dashboard | F | P0 |
| LOG-14 | Google + password button both disabled during either flow | Verified | R | P1 |
| LOG-15 | Forgot password link | Pushes `/forgot-password`, back returns | F | P1 |
| LOG-16 | Signup link | `context.go('/signup')` — back does not return to login stack | F | P2 |
| LOG-17 | Phone OTP button (currently commented out) | Absent from UI — regression check it stays hidden | R | P1 |
| LOG-18 | Autofill / password manager | Fields accept autofill | E | P2 |
| LOG-19 | Keyboard covers submit | Scrollable, button reachable | A | P1 |
| LOG-20 | Rate limit (10 wrong attempts) | Supabase rate-limit message shown, not silent failure | S | P1 |

### 2.4 SGN — `signup_screen.dart` + OTP step

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| SGN-01 | Full valid signup | signUp → signOut → OTP email; OTP step renders (handshake guard) | F | P0 |
| SGN-02 | **Handshake regression**: router must not jump to `/gym-setup` mid-handshake | Stays on signup until OTP screen | R | P0 |
| SGN-03 | First name empty | Validator blocks | F | P1 |
| SGN-04 | Invalid email format | Blocked client-side | F | P1 |
| SGN-05 | Password < 8 chars | "…at least 8" | F | P1 |
| SGN-06 | Password exactly 8 | Accepted | E | P2 |
| SGN-07 | Phone: 10-digit Indian valid (`[6-9]\d{9}`) | Accepted | F | P1 |
| SGN-08 | Phone `5123456789` | Rejected | E | P1 |
| SGN-09 | Non-India country selected via flag picker | Validation rule adapts or is documented; currency label updates | E | P1 |
| SGN-10 | Terms checkbox unchecked | Submit blocked | F | P0 |
| SGN-11 | Terms/Privacy links from checkbox | Open legal screens, return preserves form | F | P2 |
| SGN-12 | Existing email signup | Supabase error surfaced clearly | E | P1 |
| SGN-13 | OTP correct | Session created, providers invalidated, → `/gym-setup` | F | P0 |
| SGN-14 | OTP wrong | Error, fields stay, retry allowed | F | P0 |
| SGN-15 | OTP expired (>60 min) | Clear expiry message | E | P1 |
| SGN-16 | Resend before cooldown ends | Link disabled | F | P1 |
| SGN-17 | Resend after cooldown | "Code resent — check your email." | F | P1 |
| SGN-18 | Paste 6-digit code | All boxes fill; submit enables | E | P1 |
| SGN-19 | Partial code | Verify button disabled (`allFilled`) | F | P1 |
| SGN-20 | Backspace across boxes | Focus moves back correctly | E | P2 |
| SGN-21 | Kill app on OTP step | Relaunch → login (no half-session) | E | P0 |
| SGN-22 | Network drop between signUp and signInWithOtp | Guard released in `finally`; user not stuck on a frozen screen | E | P0 |
| SGN-23 | Google signup | OAuth path, no OTP step | F | P1 |
| SGN-24 | `sign_up_completed` event fires once | Firebase + Meta (if ads consent) | R | P2 |
| SGN-25 | Rapid submit | Single account created | R | P0 |

### 2.5 POTP — `phone_otp_screen.dart` (route live, entry hidden)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| POTP-01 | Route reachable only by direct nav | Confirm no UI entry point (button commented out) | R | P1 |
| POTP-02 | Send OTP to valid number | MSG91 SMS received | F | P1 |
| POTP-03 | Country picker changes dial code | Number formatted with new code | F | P2 |
| POTP-04 | Verify valid code | `verify-phone-otp` edge fn → magiclink → session | F | P0 |
| POTP-05 | Verify wrong code | Error surfaced, no session | S | P0 |
| POTP-06 | Edge function returns error/missing fields | "Phone verification failed…" | E | P1 |
| POTP-07 | Resend cooldown | Disabled until 0 | F | P2 |
| POTP-08 | Offline send | Snackbar "Could not resend code…" | O | P2 |
| POTP-09 | Reused access token replay | Edge fn rejects | S | P0 |

### 2.6 FGT — `forgot_password_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| FGT-01 | Valid email | Reset email sent, success state | F | P1 |
| FGT-02 | Unregistered email | Same generic success (no enumeration) | S | P1 |
| FGT-03 | Validator: no `@` | "Enter a valid email" | F | P1 |
| FGT-04 | `a@b` (weak validator — only checks `@`) | Documented gap; server rejects | E | P2 |
| FGT-05 | Double submit | One email (`_loading`) | R | P1 |
| FGT-06 | Offline | Error message, retryable | O | P1 |
| FGT-07 | Reset link opens app/web | Password successfully changed end to end | F | P0 |
| FGT-08 | Rate limit | Supabase message surfaced | E | P2 |

### 2.7 GYM — `gym_setup_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| GYM-01 | Complete setup | `setup_gym` RPC returns gymId; currency written to `gyms.settings`; → dashboard | F | P0 |
| GYM-02 | Gym name empty | Blocked | F | P1 |
| GYM-03 | Gym name 200+ chars / emoji | Stored or limited gracefully | E | P2 |
| GYM-04 | Country picker | Currency code + dial code update together | F | P1 |
| GYM-05 | Phone optional/invalid | Behaviour matches validator | E | P1 |
| GYM-06 | Goals multi-select none | Allowed (RPC takes list) | E | P2 |
| GYM-07 | iOS label | Button reads "Create Gym" (not "Start Free Trial") | F | P1 |
| GYM-08 | Android label + "1-day free trial" copy | Present | F | P2 |
| GYM-09 | RPC fails (PostgrestException) | Message shown, user stays, can retry | E | P0 |
| GYM-10 | Currency update fails after gym created | Gym still exists; retry doesn't create a second gym | E | P0 |
| GYM-11 | Double-tap Create (same frame) | One gym. `_submit` has no early `if (_submitting) return;` — it relies only on the UI swapping to `_buildSubmitting()`, so two taps in one frame are the risk | R | P0 |
| GYM-12 | Back/kill mid-setup | On relaunch, `_gymSetupResolvedFor` cache doesn't skip re-resolution incorrectly | R | P1 |
| GYM-13 | Offline submit | Error, no partial state | O | P0 |
| GYM-14 | `gym_setup_completed` event | Fires once | R | P2 |
| GYM-15 | After setup, `home_route` cache | Next cold start goes straight to dashboard | R | P1 |

---

## 3. Staff shell, paywall

### 3.1 SHELL — `staff_shell.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| SHELL-01 | Initial load | Blank scaffold only briefly, then content (no infinite blank) | F | P0 |
| SHELL-02 | Nav order | Home · Members · [Check-in] · Billing · More | F | P1 |
| SHELL-03 | Trainer sees 3 tabs + More | No check-in, no billing | S | P0 |
| SHELL-04 | Coach-mark tour on first launch | 3 steps (2 if no check-in), then never again | F | P1 |
| SHELL-05 | Kill app mid-tour | Not re-shown (`markSeen` upfront) | R | P1 |
| SHELL-06 | Tour throws | Caught — dashboard still usable | E | P1 |
| SHELL-07 | Plan expiry banner | Shows in-window, hidden when no expiry | F | P1 |
| SHELL-08 | More sheet header | Gym name, "First Last · Role", initials fallback when name empty | E | P2 |
| SHELL-09 | Sign out from More sheet | Confirm dialog → sign out → `/login` | F | P0 |
| SHELL-10 | Cancel sign-out | Stays, sheet closed | F | P2 |
| SHELL-11 | "More" active highlight | Lit when on any More route | F | P2 |
| SHELL-12 | Gesture nav inset devices | Bottom nav not overlapped (66+padding) | A | P1 |
| SHELL-13 | OneSignal `syncGymTags` | Fires when gym loads, once per change | R | P2 |
| SHELL-14 | Profile load error | Not a permanent blank screen | E | P0 |

### 3.2 PWL — `paywall_screen.dart` (Android/Dodo)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| PWL-01 | Shown when access false | Replaces shell content entirely | F | P0 |
| PWL-02 | Upgrade → checkout URL | Opens external browser | F | P0 |
| PWL-03 | Checkout URL fetch fails | "Could not start checkout. Please try again." | E | P0 |
| PWL-04 | Return from successful payment (`gymcrm://payment-success`) | Access restored after refresh; document if relaunch needed | F | P0 |
| PWL-05 | Return after cancelling | Still paywalled, no error loop | E | P1 |
| PWL-06 | WhatsApp support button | Opens WhatsApp; fallback snackbar if not installed | F | P1 |
| PWL-07 | Sign out from paywall | Works (only escape hatch) | F | P0 |
| PWL-08 | Double-tap upgrade | One checkout session | R | P1 |
| PWL-09 | Offline | Clear error, no blank | O | P1 |

### 3.3 IOSPWL — `ios_custom_paywall.dart` (RevenueCat)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| IOSPWL-01 | Offerings load | Annual + monthly with StoreKit-localised prices | F | P0 |
| IOSPWL-02 | Offerings fail | Retry button works | E | P1 |
| IOSPWL-03 | Purchase annual (sandbox) | Entitlement granted, shell unlocks | F | P0 |
| IOSPWL-04 | Purchase cancelled | No entitlement, button re-enabled | F | P0 |
| IOSPWL-05 | Purchase pending (Ask to Buy) | Handled, no false unlock | E | P0 |
| IOSPWL-06 | Restore purchases | Entitlement restored on fresh install | F | P0 |
| IOSPWL-07 | Restore with nothing to restore | Clear message | E | P1 |
| IOSPWL-08 | Purchase button disabled until a plan selected | Verified | F | P1 |
| IOSPWL-09 | Terms/Privacy links (App Store requirement) | Open externally | F | P0 |
| IOSPWL-10 | Trial ignored on iOS | Trial-only gym still paywalled | R | P0 |
| IOSPWL-11 | Airplane mode purchase | StoreKit error surfaced | O | P1 |

---

## 4. Staff — core screens

### 4.1 DSH — `dashboard_screen.dart` (12 parallel queries)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| DSH-01 | All KPI tiles populate | Active members, today check-ins, new this month, total check-ins, active plans, week leads, total members | F | P0 |
| DSH-02 | Revenue tiles | Today collected, pending, this month, last month — match DB | F | P0 |
| DSH-03 | Boundary: payment at 00:00 local | Counted in the correct day bucket (`startOfDay` local vs UTC) | E | P0 |
| DSH-04 | Month boundary (1st, 23:59 last day) | Month totals correct | E | P0 |
| DSH-05 | Week boundary | `startOfWeek` matches product definition (Mon vs Sun) | E | P1 |
| DSH-06 | Empty gym | All zeros + empty states ("No check-ins yet today", "No payments yet", "No enquiries yet") | F | P1 |
| DSH-07 | One query fails, others succeed | Partial render or single clear error — no whole-screen crash | E | P0 |
| DSH-08 | Pull to refresh | All 12 refetch | F | P1 |
| DSH-09 | Upcoming payments strip (next 7 days) | Only active members with `next_payment_date` in range, ordered | F | P0 |
| DSH-10 | Tap a due member → Collect sheet | Amount prefilled, method selectable | F | P0 |
| DSH-11 | Collect with empty amount | "Enter an amount" | F | P0 |
| DSH-12 | Collect with `abc` / `-100` / `0` | "Enter a valid amount" | E | P0 |
| DSH-13 | Collect: existing open invoice | Updates that invoice, does NOT create a second | R | P0 |
| DSH-14 | Collect: no open invoice | Creates invoice + payment + marks paid | F | P0 |
| DSH-15 | Collect advances `next_payment_date` by `billing_interval_months` from the **date itself** | Member leaves the due list (the advancePaymentDate bug) | R | P0 |
| DSH-16 | Collect on 31 Jan with monthly interval | Next date clamps to 28/29 Feb | E | P0 |
| DSH-17 | Collect twice rapidly | One payment row | R | P0 |
| DSH-18 | Collect fails mid-way (network drop after invoice insert) | No orphan paid invoice without payment; error surfaced | E | P0 |
| DSH-19 | Collect on a frozen/expired member | Status update behaviour correct | E | P1 |
| DSH-20 | Recent payments list (limit 4) | Newest first, member names + avatars | F | P1 |
| DSH-21 | Recent check-ins (limit 5) | Correct order and times | F | P1 |
| DSH-22 | Recent leads (limit 4) | Call button dials | F | P1 |
| DSH-23 | Call button with no dialer app | `canLaunchUrl` false → no crash | E | P1 |
| DSH-24 | Quick links navigate correctly | members / check-in / upcoming-payments / billing / settings / leads | F | P1 |
| DSH-25 | Compact currency on tiles | `₹1.20L` etc., `FittedBox` prevents overflow | E | P1 |
| DSH-26 | Very large numbers (₹99,99,999) | No clipping | E | P2 |
| DSH-27 | Offline | Error state with retry, cached nothing shown as real data | O | P0 |
| DSH-28 | Slow network | Skeletons, not frozen UI | P | P1 |
| DSH-29 | `ReviewPrompt` after collect | Counted as a success action | R | P2 |
| DSH-30 | Deleted member appears in a list | Null-safe rendering | E | P1 |

### 4.2 MEM — `members_screen.dart` (list + add sheet)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MEM-01 | List loads gym members only | Scoped by `gym_id` | S | P0 |
| MEM-02 | Search by first/last name | Debounced, correct matches | F | P0 |
| MEM-03 | Search with `%`, `_`, `'` | No PostgREST filter injection, no crash | S | P1 |
| MEM-04 | Search empty result | "No members found" | F | P1 |
| MEM-05 | Status filters (all/active/frozen/expired/cancelled) | Counts correct, persists during scroll | F | P1 |
| MEM-06 | Pull to refresh | Refetch | F | P1 |
| MEM-07 | Load error | "Could not load members. Pull to retry." | E | P1 |
| MEM-08 | Tap member | Pushes detail with correct id | F | P0 |
| MEM-09 | Actions menu → Import CSV | Opens import screen | F | P1 |
| MEM-10 | Actions menu → Upcoming payments | Navigates | F | P2 |
| MEM-11 | Add member: first name only | Saves (last name optional) | F | P0 |
| MEM-12 | Add member: blank first name | "Required" | F | P0 |
| MEM-13 | Email invalid | `validateOptionalEmail` message | F | P1 |
| MEM-14 | Email empty | Allowed | F | P1 |
| MEM-15 | Phone `12345` | "Enter a valid 10-digit mobile number" | F | P1 |
| MEM-16 | Duplicate email in same gym | Server/unique constraint error surfaced clearly | E | P0 |
| MEM-17 | Duplicate email in **other** gym | Allowed | E | P1 |
| MEM-18 | maxLength enforcement | first/last 100, custom id 50, notes 500 | E | P2 |
| MEM-19 | Joining date future | Allowed/blocked per product; date picker range respected | E | P1 |
| MEM-20 | Next payment date before joining date | Behaviour defined | E | P1 |
| MEM-21 | Billing interval selector (1/3/6/12) | Persists to `billing_interval_months` | F | P1 |
| MEM-22 | Plan selected | `memberships` row created; price prefilled | F | P0 |
| MEM-23 | "No plan" | No membership row, no invoice | F | P1 |
| MEM-24 | Recurring discount entered | Applied to invoice amount | F | P1 |
| MEM-25 | Discount > price | Blocked or clamps to 0; never negative invoice | E | P0 |
| MEM-26 | "Payment received" checkbox on | Invoice + `record_invoice_payment` RPC called | F | P0 |
| MEM-27 | Checkbox off | Invoice stays open | F | P1 |
| MEM-28 | Payment method dropdown values | cash/upi/card/bank_transfer stored verbatim | F | P2 |
| MEM-29 | Avatar from gallery | Uploads via Worker; shows immediately (cache evicted) | F | P1 |
| MEM-30 | Avatar from camera | Same | F | P1 |
| MEM-31 | Camera permission denied | Graceful | E | P1 |
| MEM-32 | 12MP photo upload | Compressed/succeeds within reasonable time; no OOM on low-end | P | P1 |
| MEM-33 | Upload fails (Worker 500) | Member still saved without avatar, or clear error | E | P1 |
| MEM-34 | Save while offline | Explicit failure, no phantom row in list | O | P0 |
| MEM-35 | Double-tap Save | One member | R | P0 |
| MEM-36 | Save then immediately back | No "setState after dispose" | E | P1 |
| MEM-37 | `first_member_added` event | Fires only for the first member of a gym | R | P2 |
| MEM-38 | 5,000 members scroll | Smooth; verify list virtualisation & query limit | P | P0 |
| MEM-39 | Trainer/staff role opens list | PII (email/phone) hidden | S | P0 |
| MEM-40 | Keyboard covers Save in sheet | Sheet scrolls; button reachable | A | P1 |

### 4.3 MDT — `member_detail_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MDT-01 | All sections load | Profile, membership, check-ins, invoices, class enrollments, workout + diet plans | F | P0 |
| MDT-02 | Member not found / other gym id | "Member not found" | S | P0 |
| MDT-03 | Call button | Dials; no dialer → silent no-op verified | F | P1 |
| MDT-04 | WhatsApp button | Opens chat with prefilled text | F | P1 |
| MDT-05 | WhatsApp not installed | Fallback message | E | P1 |
| MDT-06 | Member with no phone | Buttons disabled/handled | E | P1 |
| MDT-07 | Message templates sheet | Template swap replaces text; custom text editable | F | P1 |
| MDT-08 | Message with emoji/newlines | URL-encoded correctly | E | P1 |
| MDT-09 | Copy member ID | Clipboard + snackbar | F | P2 |
| MDT-10 | Toggle hold (freeze) | Status flips, list reflects after back | F | P0 |
| MDT-11 | Un-freeze | Restores active | F | P1 |
| MDT-12 | Switch plan | `memberships` updated; old plan closed, not duplicated | F | P0 |
| MDT-13 | Switch plan with no plans defined | Empty picker handled | E | P1 |
| MDT-14 | Edit discount | Recurring discount persisted; next invoice reflects | F | P0 |
| MDT-15 | Discount negative / >100% | Rejected | E | P0 |
| MDT-16 | Cancel plan | Membership cancelled; member status per product | F | P0 |
| MDT-17 | Send portal invite | Email sent; invalid email → "Enter a valid email address" | F | P1 |
| MDT-18 | Invite member with no email | Blocked with message | E | P1 |
| MDT-19 | Delete member | Confirm dialog; hard delete; back to list; row gone | F | P0 |
| MDT-20 | Delete failure | "Failed to delete member" | E | P1 |
| MDT-21 | Delete member with invoices/check-ins | FK behaviour defined (cascade or block), no orphans | E | P0 |
| MDT-22 | Change avatar (gallery/camera) | Re-upload to same path evicts cache and shows new photo | R | P0 |
| MDT-23 | Edit next payment date | Picker writes correct ISO date | F | P1 |
| MDT-24 | Open workout plan viewer | Shows days/exercises; edit round-trips | F | P1 |
| MDT-25 | Open diet plan viewer | Shows meals/items | F | P1 |
| MDT-26 | No plans assigned | Empty state with assign CTA | F | P1 |
| MDT-27 | Busy guard (`_busy`) | Actions disabled during any in-flight action | R | P0 |
| MDT-28 | Offline on each action | Failure messages, no local-only state drift | O | P0 |
| MDT-29 | Trainer/staff view | PII hidden, edit actions absent | S | P0 |
| MDT-30 | Very long member name / notes | No overflow | A | P2 |
| MDT-31 | Check-in history pagination | Long history performs | P | P1 |

### 4.4 CSV — `import_csv_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CSV-01 | Valid 10-row CSV | Preview shows 10 valid, 0 invalid | F | P0 |
| CSV-02 | Header case/space variants (`First Name`) | Normalised to `first_name` | E | P1 |
| CSV-03 | BOM + CRLF file (Excel export) | Parsed correctly | E | P0 |
| CSV-04 | Quoted fields with commas | Parsed as one field | E | P0 |
| CSV-05 | Escaped double quotes `""` | Single `"` in output | E | P1 |
| CSV-06 | Missing `first_name` | Row invalid, reason shown, row number = file line | F | P1 |
| CSV-07 | Missing `last_name` | Invalid (required despite being optional in the add form — confirm intent) | E | P1 |
| CSV-08 | Bad email | "Invalid or missing email" | F | P1 |
| CSV-09 | Bad status value | `Invalid status "x"` | F | P1 |
| CSV-10 | Bad `joined_at` | "use YYYY-MM-DD" | F | P1 |
| CSV-11 | Duplicate email inside file | Second flagged "Duplicate email in file" | F | P0 |
| CSV-12 | Email already in gym | Skipped at import with "Email already exists" | F | P0 |
| CSV-13 | Header-only file | "CSV is empty or has no data rows" | E | P1 |
| CSV-14 | Empty file / non-CSV renamed | Handled without crash | E | P1 |
| CSV-15 | Malformed UTF-8 bytes | `allowMalformed` — no crash, replacement chars | E | P1 |
| CSV-16 | 1,000 rows | Batches of 100; progress label; all imported | P | P0 |
| CSV-17 | Batch failure mid-import | Only that batch's rows marked "Insert failed"; others committed | E | P0 |
| CSV-18 | Plan assignment on | Memberships created; `next_payment_date` derived from each member's join date + plan months | F | P0 |
| CSV-19 | Plan with `custom` interval | Uses `billing_interval_months`, fallback 1 | E | P1 |
| CSV-20 | Plan assignment fails | Members still imported; error logged, not silently claimed successful | E | P0 |
| CSV-21 | Imported members appear in upcoming payments/reminders | Because `next_payment_date` set | R | P0 |
| CSV-22 | `MissingPluginException` (Shorebird patch without native) | "CSV import needs the latest app version…" | R | P0 |
| CSV-23 | File picker cancelled | No state change | F | P2 |
| CSV-24 | Copy template | Clipboard contains header + example | F | P2 |
| CSV-25 | Back during importing phase | No orphan half-import; result reported | E | P1 |
| CSV-26 | Offline import | "Import failed: …", phase returns to preview | O | P0 |
| CSV-27 | 5MB CSV | No OOM on low-end device (`withData: true` loads to memory) | P | P1 |
| CSV-28 | Rows exceeding plan/member limits | Server/plan cap respected | E | P1 |

### 4.5 UPY — `upcoming_payments_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| UPY-01 | 7-day / 30-day / overdue buckets | Correct membership per bucket | F | P0 |
| UPY-02 | Totals per bucket | Match sum of rows | F | P0 |
| UPY-03 | Member due today | Appears in 7-day, not overdue | E | P0 |
| UPY-04 | Member due yesterday | Overdue bucket | E | P0 |
| UPY-05 | Collect payment sheet | Same invoice reuse/creation semantics as dashboard | F | P0 |
| UPY-06 | Empty amount / invalid amount | "Enter an amount" / "Enter a valid amount" | F | P0 |
| UPY-07 | After collect, member disappears from bucket | `next_payment_date` advanced | R | P0 |
| UPY-08 | WhatsApp reminder | Opens chat; "Could not open WhatsApp" fallback | F | P1 |
| UPY-09 | Member without phone | Reminder disabled | E | P1 |
| UPY-10 | Empty bucket | Empty state | F | P1 |
| UPY-11 | Offline | Error state | O | P1 |
| UPY-12 | 500 due members | Scroll perf, totals still correct | P | P1 |
| UPY-13 | Double-tap collect | One payment | R | P0 |

### 4.6 BIL — `billing_screen.dart` (transactions, plans, invoice, WhatsApp)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| BIL-01 | Transactions list loads | Payments + invoices merged, newest first | F | P0 |
| BIL-02 | Filter All / Due / Collected | Correct subsets | F | P0 |
| BIL-03 | Collected total in dock | Matches filtered sum | F | P0 |
| BIL-04 | Due count badge | Matches open invoices | F | P1 |
| BIL-05 | Tap transaction | Opens `/invoice/:id` | F | P1 |
| BIL-06 | Record payment sheet | Method chips; save creates payment, marks invoice paid, advances member date | F | P0 |
| BIL-07 | Record with expired session | "Session expired. Please sign in again." and **no** write | S | P0 |
| BIL-08 | Record failure | "Failed to record payment. Please try again." | E | P0 |
| BIL-09 | Create invoice: no member selected | "Select a member first" | F | P0 |
| BIL-10 | Create invoice: amount 0 / negative / text | Validation blocks | E | P0 |
| BIL-11 | Due date picker + clear | Nullable due date works both ways | F | P1 |
| BIL-12 | Create invoice offline | "Error: …", nothing created | O | P0 |
| BIL-13 | Member dropdown with 5k members | Usable/searchable or paginated | P | P1 |
| BIL-14 | New plan: name empty | "Required" | F | P1 |
| BIL-15 | Plan price non-numeric / negative | Validator blocks | E | P0 |
| BIL-16 | Billing interval `custom` | Months field required and used | E | P1 |
| BIL-17 | Add/remove plan features | List persists on save | F | P2 |
| BIL-18 | Edit existing plan | Updates in place, no duplicate | R | P0 |
| BIL-19 | Deactivate plan in use | Existing memberships unaffected | E | P1 |
| BIL-20 | WhatsApp invoice share | PDF generated → uploaded to `invoice-pdfs` → link in message | F | P0 |
| BIL-21 | Member without phone | "No phone number saved for this member…" | F | P1 |
| BIL-22 | PDF generation/upload failure | "Could not generate or upload invoice PDF" | E | P1 |
| BIL-23 | WhatsApp not installed | "Could not open WhatsApp" | E | P1 |
| BIL-24 | PDF content correctness | Gym name/logo, member, amount, date, currency symbol correct | F | P0 |
| BIL-25 | PDF with very long names / unicode | Renders, no overflow (font fallback for Devanagari) | E | P1 |
| BIL-26 | Uploaded PDF URL access control | See CC-SEC-09 | S | P0 |
| BIL-27 | Pull to retry on load error | "Could not load transactions. Pull to retry." | E | P1 |
| BIL-28 | Staff role (canSeeBilling=true for `staff`) | Can view + record; confirm this is intended vs manager-only | S | P0 |
| BIL-29 | Rapid double submit on each sheet | Single write everywhere | R | P0 |

### 4.7 INV — `invoice_detail_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| INV-01 | Staff opens invoice | Full detail renders | F | P0 |
| INV-02 | Member opens own invoice from portal | Renders; can't open others' | S | P0 |
| INV-03 | Download PDF | "Saved <file>" ; file exists in Downloads | F | P1 |
| INV-04 | Download on Android 8 vs 14 | Scoped-storage differences handled | E | P1 |
| INV-05 | Download failure | "Could not download the invoice. Please try again." | E | P1 |
| INV-06 | Share PDF | Share sheet opens with attachment | F | P1 |
| INV-07 | Invalid invoice id | "Error: …" state | E | P1 |
| INV-08 | Zero/negative amount invoice | Renders | E | P2 |
| INV-09 | Offline | Error state, download blocked gracefully | O | P1 |
| INV-10 | Low storage device | Download error handled | E | P2 |

### 4.8 CHK — `check_in_screen.dart` (scan / show QR / manual / checkout)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CHK-01 | Scan valid member QR | Success card with name + avatar; `check_ins` row with `method='qr'` | F | P0 |
| CHK-02 | Scan same member twice | `23505` → "Already checked in. Check them out first." | F | P0 |
| CHK-03 | Scan non-member QR (random URL) | "Member not found" / not-a-QR message | F | P0 |
| CHK-04 | Scan another gym's member QR | "This QR code is not a member of your gym." (query filters `gym_id`) | S | P0 |
| CHK-05 | Scan frozen/expired member | "Not active (frozen). Check-in blocked." | F | P0 |
| CHK-06 | Rapid multiple frames of the same code | Single insert (`_processing` guard) | R | P0 |
| CHK-07 | Camera permission denied | Prompt/explanation, tab still usable via search | E | P0 |
| CHK-08 | Camera permission permanently denied | Link to settings, no crash loop | E | P1 |
| CHK-09 | Leaving the scan tab | Camera stops (battery) | P | P0 |
| CHK-10 | Backgrounding with camera on | Camera released; resumes on return | P | P0 |
| CHK-11 | Low light / damaged QR | No crash, keeps scanning | E | P2 |
| CHK-12 | Manual search by name | Results filtered to gym; tap = `method='manual'` check-in | F | P0 |
| CHK-13 | Search clear button | Clears field + results | F | P2 |
| CHK-14 | Search no results | "No members found" | F | P1 |
| CHK-15 | Manual banner auto-dismiss | Clears after 3s, no crash if screen left first | E | P1 |
| CHK-16 | Check out a member | `checkout_member` RPC; success message | F | P0 |
| CHK-17 | Check out already-checked-out | Error surfaced, list consistent | E | P1 |
| CHK-18 | Today's check-ins list | Accurate, refreshes after each action | F | P0 |
| CHK-19 | Empty day | "No check-ins yet today" | F | P1 |
| CHK-20 | Gym QR tab | Renders gym `registration_token` QR; "No check-in code for this gym yet." when null | F | P0 |
| CHK-21 | Copy check-in link | Clipboard + snackbar | F | P2 |
| CHK-22 | Save QR to gallery | "Saved to gallery"; visible in Photos | F | P1 |
| CHK-23 | Save QR failure | "Could not save the QR code. Please try again." | E | P1 |
| CHK-24 | Share QR | Share sheet; failure message on error | F | P1 |
| CHK-25 | Fullscreen QR view | Renders, brightness legible, back works | F | P2 |
| CHK-26 | Offline scan | Queued: "Saved offline. Will sync automatically when connected." | O | P0 |
| CHK-27 | Offline with expired session | "Session expired… to use offline check-in." nothing queued | S | P0 |
| CHK-28 | Pending-sync banner | Count accurate; tap flushes | O | P0 |
| CHK-29 | Flush partially fails | Remaining count correct | O | P1 |
| CHK-30 | History sheet: search + date presets + pagination | Prev/next arrows disable at bounds; counts correct | F | P1 |
| CHK-31 | History with 10k rows | Page loads < 2s | P | P1 |
| CHK-32 | `ReviewPrompt.recordSuccess` on check-in | Counter increments once per success | R | P2 |
| CHK-33 | Trainer role reaching this route directly | Blocked (RBAC) | S | P0 |
| CHK-34 | Clock skew on device | `queued_at` sane; server can reject far-future timestamps | E | P1 |

### 4.9 CLS — `classes_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| CLS-01 | Class list by day | Day selector filters sessions | F | P1 |
| CLS-02 | Create class | Name required; type dropdown; start<end enforced | F | P0 |
| CLS-03 | End time before start | Blocked or corrected | E | P0 |
| CLS-04 | Days-of-week multi-select | Persisted | F | P1 |
| CLS-05 | Colour picker | Saved and rendered | F | P2 |
| CLS-06 | Legacy class type not in dropdown | Doesn't throw (documented guard) | R | P0 |
| CLS-07 | Edit class | Updates in place | F | P1 |
| CLS-08 | Delete class | Confirm; "Failed to delete: …" on FK conflict | F | P1 |
| CLS-09 | Add session with date/time picker | Row created for correct datetime + timezone | F | P0 |
| CLS-10 | Add session in the past | Allowed/blocked per product | E | P1 |
| CLS-11 | Enroll member | Appears in enrolled list; capacity respected | F | P0 |
| CLS-12 | Enroll beyond capacity | Blocked with message | E | P0 |
| CLS-13 | Enroll duplicate member | Prevented | E | P1 |
| CLS-14 | Remove enrollment | Removed; "Failed to remove: …" on error | F | P1 |
| CLS-15 | Member search inside enroll sheet | Filters; "Loading members…" hint while loading | F | P1 |
| CLS-16 | No classes yet | Empty state + Add CTA | F | P1 |
| CLS-17 | Offline on each action | Error surfaced | O | P1 |
| CLS-18 | Trainer role | Can access (canSeeBatches true) | S | P1 |
| CLS-19 | Double-tap save/enroll | Single write | R | P0 |
| CLS-20 | DST transition day session | Time renders correctly | E | P2 |

### 4.10 LED — `leads_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| LED-01 | Leads list | Newest first, scoped by gym | F | P1 |
| LED-02 | Add lead | Name required; source & status dropdowns; follow-up date optional | F | P0 |
| LED-03 | Clear follow-up date | Nulls the field | F | P2 |
| LED-04 | Status change via picker | Persists; list re-sorts/filters correctly | F | P1 |
| LED-05 | Convert lead to member | Flow completes; member created once | F | P0 |
| LED-06 | Call lead | Dialer opens | F | P1 |
| LED-07 | WhatsApp lead | Opens with prefilled message | F | P1 |
| LED-08 | Lead without phone | Actions disabled | E | P1 |
| LED-09 | Invalid phone format | Handled by wa.me gracefully | E | P2 |
| LED-10 | Empty state | Shown | F | P2 |
| LED-11 | Offline add | "Error: …" | O | P1 |
| LED-12 | Trainer/staff access | Blocked (manager+) | S | P0 |
| LED-13 | Double-tap save | One lead | R | P1 |

### 4.11 RPT — `reports_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| RPT-01 | Revenue tab loads (`get_revenue_report`) | Chart + rows match DB | F | P0 |
| RPT-02 | Members tab (`get_member_stats`) | Counts match | F | P0 |
| RPT-03 | Period switch (week/month/quarter/year) | Refetch with correct params | F | P1 |
| RPT-04 | No data for period | "No revenue data for this period" / "No member data yet" | F | P1 |
| RPT-05 | RPC error/timeout | Error state with retry | E | P1 |
| RPT-06 | Chart with a single data point | Renders | E | P2 |
| RPT-07 | Chart with 365 points | Performs, labels readable | P | P1 |
| RPT-08 | Currency in report | Uses gym currency, not hardcoded ₹ | R | P1 |
| RPT-09 | Timezone boundary in aggregation | Server RPC and client agree | E | P0 |
| RPT-10 | Trainer/staff access | Blocked | S | P0 |
| RPT-11 | Offline | Error state | O | P1 |

### 4.12 SET — `settings_screen.dart` + sub-sheets

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| SET-01 | Menu renders for owner | All rows present | F | P1 |
| SET-02 | Manager vs owner rows | Owner-only items (delete account, subscription) gated correctly | S | P0 |
| SET-03 | Profile sheet: save name/phone | `profiles` updated; More sheet header reflects | F | P1 |
| SET-04 | Profile invalid phone | Validator blocks | E | P1 |
| SET-05 | Change password: mismatch | Blocked | F | P0 |
| SET-06 | Change password: weak (<8) | Blocked | F | P0 |
| SET-07 | Change password success | Old password no longer works | S | P0 |
| SET-08 | Password visibility toggles | Both fields independent | F | P2 |
| SET-09 | Gym details: name/website/currency | Saved to `gyms` / `gyms.settings.currency` | F | P0 |
| SET-10 | Currency change | All money UI updates after refresh | R | P0 |
| SET-11 | Website URL invalid | Handled (`https://` hint) | E | P2 |
| SET-12 | Gym logo upload | Uploads to `gym-logos`; renders; gallery error → "Could not open gallery: …" | F | P1 |
| SET-13 | Logo huge file | Compressed/limited, no OOM | P | P1 |
| SET-14 | Razorpay connect | `save_razorpay_keys` RPC; "Razorpay connected"; secret never echoed back | S | P0 |
| SET-15 | Razorpay disconnect | "Razorpay disconnected"; keys cleared | S | P0 |
| SET-16 | Razorpay secret visibility toggle | Masked by default | S | P1 |
| SET-17 | Invalid Razorpay key format | Server rejects, message shown | E | P1 |
| SET-18 | Support ticket submit | Row in `support_tickets`; appears in ticket list | F | P1 |
| SET-19 | Support empty title/description | Blocked | E | P2 |
| SET-20 | Ticket list empty | "No tickets yet" | F | P2 |
| SET-21 | Privacy choices row | Opens `/consent` in editable mode | F | P1 |
| SET-22 | Privacy/Terms rows | Open legal screens | F | P2 |
| SET-23 | About dialog | Version + build correct | F | P2 |
| SET-24 | Sign out | Confirm → `/login` | F | P0 |
| SET-25 | Delete account: wrong confirmation text | Delete disabled until exactly `DELETE` | S | P0 |
| SET-26 | Delete account: success | Account + gym data removed per policy; signed out; cannot log back in | S | P0 |
| SET-27 | Delete account: failure | Error surfaced, account intact | E | P0 |
| SET-28 | Delete account offline | Blocked with error | O | P0 |
| SET-29 | Staff/trainer reaching settings | Blocked | S | P0 |
| SET-30 | Double-tap on every sheet's save | Single write | R | P0 |

### 4.13 REM — `reminders_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| REM-01 | Toggle reminders on/off | `gyms` updated; state persists across reopen | F | P1 |
| REM-02 | Day-of-cycle chips | Selected days saved; disabled while `_saving` | F | P1 |
| REM-03 | Send now | Sends; success/failure snackbar with count | F | P0 |
| REM-04 | Send now with zero due members | Sensible message, no spam | E | P1 |
| REM-05 | Quota display | Free monthly quota + purchased credits accurate | F | P1 |
| REM-06 | Buy credit pack (Android/Dodo) | Checkout URL opens; failure → "Could not start checkout…" | F | P0 |
| REM-07 | Buy credits (iOS/RevenueCat) | Purchase success → "Purchase successful — credits will appear shortly." | F | P0 |
| REM-08 | iOS product unavailable | "This pack is not available right now." | E | P1 |
| REM-09 | iOS purchase error | "Purchase failed: <msg>" | E | P1 |
| REM-10 | Purchase cancelled | No credit change, button re-enabled | E | P0 |
| REM-11 | Credits exhausted mid-send | Partial send reported honestly | E | P0 |
| REM-12 | Double-tap Send now | One send (`_sendingNow`) | R | P0 |
| REM-13 | Offline | Errors surfaced | O | P1 |
| REM-14 | Non-manager access | Blocked | S | P0 |

### 4.14 COM — `communications_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| COM-01 | Due-reminders list | Members due within filter window | F | P1 |
| COM-02 | Filters 3 / 7 / all days | Correct subsets, reload each time | F | P1 |
| COM-03 | Send per-member WhatsApp | Opens WhatsApp with message | F | P1 |
| COM-04 | Member with no phone | Send disabled + "No phone number on record" | F | P1 |
| COM-05 | WhatsApp missing | "Message copied to clipboard" fallback | E | P1 |
| COM-06 | Refresh button | Re-fetches | F | P2 |
| COM-07 | Empty range | "No members due in this range" | F | P2 |
| COM-08 | Offline | Error/empty handled | O | P1 |
| COM-09 | Non-manager access | Blocked | S | P0 |

### 4.15 STF — `staff_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| STF-01 | Staff list | All gym profiles with role chips | F | P1 |
| STF-02 | Invite staff: valid email + role | "Invite sent to <email>" | F | P0 |
| STF-03 | Invite invalid email | Inline error | F | P1 |
| STF-04 | Invite existing staff email | Clear duplicate error | E | P1 |
| STF-05 | Invite with expired session | "Session expired. Please sign in again." | S | P0 |
| STF-06 | Role selection | Correct role assigned on acceptance | S | P0 |
| STF-07 | Remove staff | "Staff member removed"; list updates | F | P0 |
| STF-08 | Remove self / last owner | Blocked (must not orphan the gym) | S | P0 |
| STF-09 | Remove failure | Error snackbar | E | P1 |
| STF-10 | Empty state | "No staff members yet." | F | P2 |
| STF-11 | Manager inviting an owner | Privilege escalation blocked server-side | S | P0 |
| STF-12 | Double-tap invite | One invite | R | P1 |
| STF-13 | Offline | Errors surfaced | O | P1 |

### 4.16 WPL / DPL — workout & diet plan screens + sheets

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| WPL-01 | Member list with plan status | Assign CTA per member | F | P1 |
| WPL-02 | Search members | Filters | F | P1 |
| WPL-03 | Create plan: name empty | "Enter a plan name" | F | P1 |
| WPL-04 | Plan type switch (weekly/custom/daily) | Day list rebuilt; entered data loss warned or preserved | E | P1 |
| WPL-05 | Add/remove days & exercises | State correct after multiple adds/removes | F | P1 |
| WPL-06 | Save plan | Row in `workout_plans`; visible to member portal | F | P0 |
| WPL-07 | Edit existing plan | Updates, no duplicate | R | P0 |
| WPL-08 | Save failure | "Failed to save plan" | E | P1 |
| WPL-09 | Delete plan | Removed; "Failed to delete plan" on error | F | P1 |
| WPL-10 | 20 days × 20 exercises | No jank, save succeeds, payload size OK | P | P1 |
| WPL-11 | Empty exercise rows | Filtered out or saved as blank — define | E | P2 |
| DPL-01 | Diet plan: name required | "Enter a plan name" | F | P1 |
| DPL-02 | Goal chips | Saved | F | P2 |
| DPL-03 | Calories non-numeric | Handled | E | P1 |
| DPL-04 | Meals + food items add/remove | Order stable | F | P1 |
| DPL-05 | Meal time free text (`8:00 AM`) | Stored/rendered consistently | E | P2 |
| DPL-06 | Save/edit/delete | As WPL-06/07/09 | F | P0 |
| DPL-07 | Member sees assigned plan immediately | Portal refresh shows it | R | P1 |
| WPL/DPL-12 | Offline save | Error, no local phantom plan | O | P1 |
| WPL/DPL-13 | Double-tap save | One plan | R | P0 |
| WPL/DPL-14 | Back with unsaved edits | Confirm-discard or explicit save-required behaviour defined | E | P1 |

### 4.17 MPV — `member_plan_viewer.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MPV-01 | Workout viewer day tabs | Switch days, exercises correct | F | P1 |
| MPV-02 | Empty plan | "No exercises in this plan yet" / "No exercises for this day" | F | P1 |
| MPV-03 | Edit → save → back | `_changed` returned; parent refreshes | R | P1 |
| MPV-04 | Diet viewer meals | Renders; "No meals added yet" empty state | F | P1 |
| MPV-05 | Back without edits | Returns false; no needless refetch | F | P2 |

---

## 5. Member portal

### 5.1 PRT — `portal_home_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| PRT-01 | Home loads for A9 | Membership card, streak/check-ins, quick access | F | P0 |
| PRT-02 | Member with no membership | "No active membership" | F | P1 |
| PRT-03 | Profile fetch error | "Error loading profile" | E | P1 |
| PRT-04 | Missing member row | "Profile not found" | E | P1 |
| PRT-05 | QR icon | Pushes `/portal/qr` | F | P1 |
| PRT-06 | Sign out dialog | Cancel/confirm both correct | F | P0 |
| PRT-07 | Recent check-ins list | Times correct in local tz; empty → "No check-ins yet" | F | P1 |
| PRT-08 | Check-ins fetch error | "Failed to load check-ins" (rest of screen still usable) | E | P1 |
| PRT-09 | Quick access links | All 5 navigate | F | P1 |
| PRT-10 | Offline | Error states, no blank | O | P1 |
| PRT-11 | Member bottom nav 5 tabs | Switch preserves branch state | F | P1 |
| PRT-12 | Member on staff route via deep link | Blocked/redirected | S | P0 |
| PRT-13 | Long gym/member names | No overflow | A | P2 |

### 5.2 MQR — `qr_screen.dart` (member: show + scan)

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MQR-01 | My QR tab renders | Member token QR; "Could not load your QR code" on failure | F | P0 |
| MQR-02 | Screen brightness / legibility for scanning | QR scannable by staff device | F | P1 |
| MQR-03 | Scan gym QR: full URL `https://gymcrm.in/c/{token}` | Token extracted, `self_checkin` called | F | P0 |
| MQR-04 | Scan bare token (hex, ≥20 chars) | Accepted | E | P1 |
| MQR-05 | Scan random URL / text | "Not a gym QR code" | F | P0 |
| MQR-06 | Scan URL with `/c/` deeper in path | Extraction still correct | E | P1 |
| MQR-07 | `self_checkin` returns checkin | "Welcome, <name>!" + gym name + time | F | P0 |
| MQR-08 | Second scan → checkout | "See you, <name>!" with both timestamps | F | P0 |
| MQR-09 | `ok:false` (not a member / inactive / wrong gym) | `error`+`reason` shown | S | P0 |
| MQR-10 | Camera frozen after result | No repeat scans until "Scan again" | R | P0 |
| MQR-11 | Scan again | Camera restarts | F | P1 |
| MQR-12 | Tab switch stops camera | Verified via battery/CPU | P | P0 |
| MQR-13 | Dispose while scanning | No leaked controller / crash | E | P0 |
| MQR-14 | Camera permission denied | Handled message | E | P1 |
| MQR-15 | Offline scan | "Something went wrong" with the error; no silent success | O | P0 |
| MQR-16 | Copy/share member QR (if present) | Works; token not leaked beyond intent | S | P1 |
| MQR-17 | Replay a captured gym token from a photo | Server-side validation decides (document expected policy: is a photographed gym QR enough to check in remotely?) | S | P0 |

### 5.3 MBK — `bookings_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MBK-01 | Upcoming sessions list | Only member's gym sessions | S | P0 |
| MBK-02 | Book a class | "Class booked successfully!"; booking appears | F | P0 |
| MBK-03 | Book same class twice | Prevented (unique) with clear error | E | P0 |
| MBK-04 | Book full class | Blocked | E | P0 |
| MBK-05 | Booking error | "Error: <e>" | E | P1 |
| MBK-06 | No upcoming classes | "No upcoming classes" | F | P1 |
| MBK-07 | Cancel booking (if supported) | Status updates | F | P1 |
| MBK-08 | Offline booking | Error, no phantom booking | O | P0 |
| MBK-09 | Double-tap Book | One booking | R | P0 |
| MBK-10 | Member row missing (`.single()` throws) | Handled, not a red screen | E | P0 |

### 5.4 MBILL — `member_billing_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MBILL-01 | Invoice list | Own invoices only | S | P0 |
| MBILL-02 | Status chips | paid/open/overdue coloured correctly | F | P2 |
| MBILL-03 | Tap invoice | Opens `/invoice/:id` | F | P1 |
| MBILL-04 | No invoices | Empty state | F | P1 |
| MBILL-05 | Error | "Error: <e>" | E | P1 |
| MBILL-06 | Offline | Error state | O | P1 |

### 5.5 MWK / MDIET — member workout & diet

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MWK-01 | Assigned plan renders | Day tabs, exercise list | F | P1 |
| MWK-02 | Multiple plans | "Plan 1 / N ›" cycles | F | P1 |
| MWK-03 | No plan | Empty state | F | P1 |
| MWK-04 | Empty day | "No exercises in this plan yet" | F | P2 |
| MDIET-01 | Meals + expand/collapse | Works | F | P1 |
| MDIET-02 | Plan switcher | Cycles plans | F | P1 |
| MDIET-03 | No meals | "No meals added yet" | F | P2 |
| MWK/MDIET-04 | Plan edited by staff while open | Refresh shows update | R | P1 |
| MWK/MDIET-05 | Offline | Error state | O | P1 |

### 5.6 MHM — `heatmap_screen.dart`

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| MHM-01 | 6-month heatmap renders | Cells match `check_ins` | F | P1 |
| MHM-02 | No visits | "No visits in the last 6 months" | F | P1 |
| MHM-03 | Load error | "Failed to load attendance: <e>" | E | P1 |
| MHM-04 | Multiple check-ins same day | Intensity/count correct | E | P1 |
| MHM-05 | Timezone: late-night check-in | Lands on the correct local day | E | P1 |
| MHM-06 | DST week | No missing/duplicate column | E | P2 |
| MHM-07 | 1,000 check-ins | Renders < 1s | P | P1 |
| MHM-08 | Small screen | Grid scrolls, no overflow | A | P1 |

### 5.7 LEG — legal screens

| ID | Title | Expected | Type | Pri |
|---|---|---|---|---|
| LEG-01 | Privacy screen renders all sections | Including Android permissions section | F | P1 |
| LEG-02 | Terms screen renders | Effective date visible | F | P1 |
| LEG-03 | "Open web" button | External browser; failure handled | F | P2 |
| LEG-04 | Reachable pre-auth (from signup + consent) | No redirect loop (`/legal/*` exempt in router) | R | P0 |
| LEG-05 | Reachable from Settings post-auth | Back returns to Settings | F | P2 |
| LEG-06 | Content matches Play/App Store listing + actual SDKs (Firebase, Meta, OneSignal, RevenueCat, MSG91, Cloudflare Worker) | Compliance review | S | P0 |

---

## 6. Regression pack (run every release)

Short list; each maps to a bug the code comments record as already fixed.

| ID | Guard against | Case |
|---|---|---|
| REG-01 | Signup handshake race | SGN-02 |
| REG-02 | `home_route` stale after account switch | CC-AUTH-05, CC-FMT-04 |
| REG-03 | `advancePaymentDate` relative-to-today bug | DSH-15, DSH-16, UPY-07 |
| REG-04 | Duplicate invoice per collection | DSH-13 |
| REG-05 | Member photo cache not evicted on re-upload | MDT-22 |
| REG-06 | `member-photos` served without auth | CC-SEC-07/08 |
| REG-07 | Coach-mark tour re-showing | SHELL-05 |
| REG-08 | Legacy class type crashing dropdown | CLS-06 |
| REG-09 | `MissingPluginException` after a Shorebird patch | CSV-22, CC-REL-06 |
| REG-10 | Router 404 on custom-scheme deep links | CC-AUTH-11/12 |
| REG-11 | OutlinedButton in Row crushing sibling text | Visual sweep of all Row-embedded buttons |
| REG-12 | Redesign dropping onTap wiring | Diff every restyled screen's action handlers |
| REG-13 | Currency leaking across gyms (global `_currencyCode`) | CC-FMT-03/04 |
| REG-14 | Paywall on transient network error | CC-BILL-13 |
| REG-15 | Offline queue inserting into wrong gym | CC-OFF-07 |

---

## 7. Known gaps worth a bug ticket before test execution

1. `forgot_password_screen.dart:86` validator only checks `contains('@')` — weaker than `isValidEmail`. (FGT-04)
2. `gym_setup_screen.dart:83` `_submit()` has no re-entrancy early-return; it depends on the widget swapping to `_buildSubmitting()`. Same-frame double-tap could call `setup_gym` twice. (GYM-11)
3. `hasActiveBillingAccess(null)` returns false, so a failed profile fetch can render the paywall to a paying customer. (CC-BILL-13)
4. Billing/payment access is granted to the `staff` role (`canSeeBilling`/`canRecordPayment`), which contradicts the "manager+" comment at the top of `role_access.dart`. (BIL-28, CC-RBAC-01)
5. CSV import requires `last_name` while the add-member form treats it as optional — inconsistent contract. (CSV-07)
6. Client clock is trusted for every expiry decision; verify server enforcement on writes. (CC-BILL-10/11)
