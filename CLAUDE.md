# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run the app (debug)
flutter run

# Build release AAB (requires keystore + Supabase secrets)
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_ANON_KEY=<key>

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Regenerate app icon
dart run flutter_launcher_icons

# Regenerate native splash screen
dart run flutter_native_splash:create
```

**Shorebird (OTA patches — Dart-only changes):**
```bash
shorebird patch android   # publish a patch to existing users
shorebird release android # full release (bumps version first)
```
Shorebird patches only work for pure Dart changes. Any native code, plugin, or asset change requires a full store release.

## Architecture

### Tech stack
- **Flutter + Riverpod** for UI and state management
- **go_router** for navigation
- **Supabase** (Postgres + Auth + Storage) as the backend
- **Shorebird** for over-the-air Dart patches

### Dual-portal structure
The app serves two completely separate user types via a single binary:

| Portal | Routes | Shell |
|--------|--------|-------|
| **Staff** (owner / manager / trainer / staff) | `/staff/*` | `StaffShell` with bottom nav + "More" sheet |
| **Member** (gym member self-service) | `/portal/*` | `MemberShell` |

After login, `router.dart` checks `profiles` (staff) and `members` (member) tables to determine which portal to land on, then caches the result in `SharedPreferences` as `home_route` to avoid a DB round-trip on every cold start.

### Key files

| File | Purpose |
|------|---------|
| `lib/main.dart` | Supabase init |
| `lib/core/router.dart` | All routes + redirect logic. Contains `signupHandshakeInProgress` guard and `home_route` cache. |
| `lib/features/auth/providers/auth_provider.dart` | `AuthNotifier` (sign-in, sign-up OTP flow, gym setup RPC), `gymIdProvider`, `staffProfileProvider`, `staffRoleProvider` |
| `lib/core/access/role_access.dart` | RBAC — maps `owner/manager/trainer/staff` roles to feature flags |
| `lib/core/billing/billing_access.dart` | `hasActiveBillingAccess()` — gates the paywall; reads `plan`, `plan_expires_at`, `trial_ends_at`, `dodo_subscription_id` from the joined `gyms` row |
| `lib/core/theme/app_theme.dart` | Full design system (colors, typography, component styles). All screens use `AppTheme.*` constants. |
| `lib/core/services/member_photo_service.dart` | Resolves `member-photos` (private bucket) storage paths to signed URLs with 55-min in-memory cache |
| `lib/core/services/offline_checkin_queue.dart` | Persists QR check-ins to SharedPreferences when offline; flushes via `insert_checkin_secure` RPC on reconnect |

### Auth + signup flow
Signup uses a two-step OTP handshake: `signUp()` (creates instant session) → `signOut()` → `signInWithOtp()`. `signupHandshakeInProgress` (a `ValueNotifier`) prevents the router from navigating away mid-handshake.

### RBAC
`RoleAccess` (in `lib/core/access/role_access.dart`) is the single source of truth. Role hierarchy (ascending privilege): `staff < trainer < manager < owner`. The `StaffShell` bottom nav and "More" sheet filter tabs dynamically using these helpers.

### Billing gate
`StaffShell` checks `hasActiveBillingAccess(gym)` on every render. When false, it renders `PaywallScreen` instead of the shell content. The `gyms` row is always fetched as part of `staffProfileProvider` (joined via Supabase select).

### Models
Plain Dart classes in `lib/shared/models/`. All `fromJson` constructors throw `FormatException` on a missing `id` field rather than silently producing empty strings.

### Supabase security RPCs
Database operations that bypass RLS use `SECURITY DEFINER` RPCs:
- `setup_gym` — initial gym + profile creation
- `insert_checkin_secure` — QR check-in with cross-gym membership validation
- `save_razorpay_keys` — writes secret key without exposing it through the `gyms` table

Migrations live in `supabase/migrations/`. Apply with `supabase db push` or paste into the Supabase SQL editor.

### Member photos
The `member-photos` storage bucket is **private**. `avatar_url` columns store bare storage paths (e.g. `gymId/file.png`), not public URLs. Always resolve via `MemberPhotoService.signedUrl()` before rendering.

## CI/CD

`.github/workflows/build.yml` — triggers on push/PR to `main`:
1. Builds a signed release AAB using secrets: `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`
2. Uploads the AAB as a GitHub artifact (14-day retention)

The keystore file (`android/app/upload-keystore.jks`) and `android/key.properties` are required for local release builds.
