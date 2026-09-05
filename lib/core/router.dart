import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router_refresh.dart';
import 'access/gym_permissions.dart';
import 'access/permission_gate.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/welcome_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/member_login_screen.dart';
import '../features/auth/screens/member_help_screen.dart';
import '../features/auth/screens/phone_otp_screen.dart';
import '../features/auth/screens/member_signup_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/staff/gym_setup/gym_setup_screen.dart';
import '../features/staff/onboarding/first_setup_screen.dart';
import '../features/staff/dashboard/dashboard_screen.dart';
import '../features/staff/members/members_screen.dart';
import '../features/staff/members/member_detail_screen.dart';
import '../features/staff/members/upcoming_payments_screen.dart';
import '../features/staff/billing/billing_screen.dart';
import '../features/staff/paywall/paywall_screen.dart';
import '../features/staff/classes/classes_screen.dart';
import '../features/staff/check_in/check_in_screen.dart';
import '../features/staff/check_in/attendance_calendar_screen.dart';
import '../features/staff/leads/leads_screen.dart';
import '../features/staff/expenses/expenses_screen.dart';
import '../features/staff/no_access_screen.dart';
import '../features/staff/reports/reports_screen.dart';
import '../features/staff/reports/data_export_screen.dart';
import '../features/staff/settings/settings_screen.dart';
import '../features/staff/settings/invoice_settings_screen.dart';
import '../features/staff/settings/reminders_screen.dart';
import '../features/staff/communications/communications_screen.dart';
import '../features/staff/staff/staff_screen.dart';
import '../features/staff/staff/staff_permissions_screen.dart';
import '../features/staff/activity/activity_log_screen.dart';
import '../features/staff/workout/staff_workout_plans_screen.dart';
import '../features/staff/diet/staff_diet_plans_screen.dart';
import '../features/staff/notifications/notifications_screen.dart';
import '../features/member/portal/portal_home_screen.dart';
import '../features/member/billing/member_billing_screen.dart';
import '../features/member/workout/workout_screen.dart';
import '../features/member/diet/diet_screen.dart';
import '../features/member/attendance/heatmap_screen.dart';
import '../features/member/qr/qr_screen.dart';
import '../features/legal/consent_screen.dart';
import '../features/legal/privacy_policy_screen.dart';
import '../features/legal/terms_screen.dart';
import '../features/shared/invoice_detail_screen.dart';
import 'shells/staff_shell.dart';
import 'shells/member_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _staffNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'staff');
final _memberNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'member');

/// Remembers that the user-resolution lookup just decided this user belongs on
/// /gym-setup. /gym-setup isn't persisted to `home_route` (it stops being the
/// destination the moment setup completes), so GoRouter re-runs redirect for
/// /gym-setup itself — this guard stops that re-run from repeating the
/// profiles+members round trip, which is what made the post-OTP transition slow.
/// Cleared on sign-out; made moot once setup writes `home_route`.
String? _gymSetupResolvedFor;

/// Which user we've already looked up server-side consent for this session.
/// Without it a genuine first-timer — who has no row to find — would repeat
/// that query on every single navigation while sitting on /consent.
/// Cleared on sign-out, same as the guard above.
String? _consentCheckedFor;

/// Set by setupGym(), cleared when the owner leaves the first-setup wizard.
/// A plain `context.go('/staff/first-setup')` can't survive the trip: the DPDP
/// consent gate below outranks it on a first signup, and the consent screen
/// then lands on `home_route` — so the wizard was skipped every time. Storing
/// the intent means it also survives a cold start mid-setup.
const kPendingFirstSetup = 'pending_first_setup';

/// Called by setupGym() the moment a gym exists. Without this the guard above
/// outlives the condition it stands for: /staff/* skips the `home_route` fast
/// path (it needs a fresh role lookup), falls through to the guard, and bounces
/// the brand-new owner back to /gym-setup forever.
void clearGymSetupResolution() => _gymSetupResolvedFor = null;

/// Cached SharedPreferences instance — avoids re-initialising the plugin on
/// every router redirect (the getInstance() call is async even when cached
/// internally, adding unnecessary latency to every navigation event).
SharedPreferences? _sharedPrefs;

final routerProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  );
  ref.onDispose(refreshStream.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/welcome',
    // Also refresh when the signup handshake guard flips, so the redirect is
    // re-evaluated the moment it releases.
    refreshListenable: Listenable.merge([
      refreshStream,
      signupHandshakeInProgress,
    ]),
    redirect: (context, state) async {
      // signUp() is mid create→sign-out→send-OTP handshake: ignore the transient
      // auth events it emits and keep the user on the signup screen so the OTP
      // step can render. See [signupHandshakeInProgress].
      if (signupHandshakeInProgress.value) return null;

      final prefs = _sharedPrefs ??= await SharedPreferences.getInstance();

      // External deep links (gymcrm://payment-success, io.supabase.gymcrm://
      // login-callback) get forwarded here by the Android engine as a raw
      // location string, but no GoRoute declares that path — it would 404.
      // These are already handled by dedicated listeners (app_links stream /
      // supabase_flutter's own auth callback), so just land somewhere valid.
      if (state.uri.scheme.isNotEmpty &&
          state.uri.scheme != 'http' &&
          state.uri.scheme != 'https') {
        return prefs.getString('home_route') ?? '/login';
      }

      final user = Supabase.instance.client.auth.currentUser;

      final loc = state.matchedLocation;
      final isAuthRoute =
          loc == '/welcome' ||
          loc.startsWith('/login') ||
          loc.startsWith('/signup') ||
          loc.startsWith('/forgot-password') ||
          loc.startsWith('/legal/');
      final isStaffRoute = loc.startsWith('/staff/');
      final isMemberRoute = loc.startsWith('/portal/');

      if (user == null) {
        // Stale cache from a previous account must not survive sign-out.
        if (prefs.containsKey('home_route')) await prefs.remove('home_route');
        if (prefs.containsKey(kPendingFirstSetup)) {
          await prefs.remove(kPendingFirstSetup);
        }
        // Consent is taken once, ever, and never re-cleared or re-checked —
        // not on sign-out, not on a new sign-in. This used to wipe
        // kConsentGiven every time this branch ran, which includes the
        // login screen simply sitting idle before anyone has signed out of
        // anything. That forced a live Supabase consent lookup inside
        // redirect() on literally every sign-in, racing the auth-state
        // change from the login itself and leaving the button stuck on
        // "Logging in…" — the session had actually already been created.
        _gymSetupResolvedFor = null;
        _consentCheckedFor = null;
        _sharedPrefs =
            null; // Force re-init next time so the cleared key is visible
        // /welcome (canvas "Who is signing in?") is the real landing page —
        // /login stays reachable directly for deep links and for screens
        // that already know which path the user is on (e.g. signup's
        // "Already have an account?" goes straight to owner login).
        return isAuthRoute ? null : '/welcome';
      }

      // DPDP consent gate — now sits after signup, once an account exists,
      // not before it. /legal/* stays reachable so the notice can link out.
      if (!(prefs.getBool(kConsentGiven) ?? false) &&
          !loc.startsWith('/legal/')) {
        // Consent belongs to the person, not the device: someone who already
        // agreed must not be asked again after a reinstall, on a second
        // device, or because a different user last used this one. Checked once
        // per session per user — a genuine first-timer shouldn't pay for this
        // round trip on every navigation.
        if (_consentCheckedFor != user.id) {
          _consentCheckedFor = user.id;
          if (await hydrateConsentFromServer(prefs)) return null;
        }
        return loc == '/consent' ? null : '/consent';
      }

      // A brand-new owner still owes us the one-time setup wizard. This has to
      // outrank the `home_route` fast path below — consent (or a cold start)
      // lands them on the dashboard otherwise, with no plan and no members.
      if ((prefs.getBool(kPendingFirstSetup) ?? false) &&
          !loc.startsWith('/legal/')) {
        return loc == '/staff/first-setup' ? null : '/staff/first-setup';
      }

      // Resolve where this user belongs only when it matters (leaving an auth
      // route, or guarding /gym-setup) so we don't hit the DB on every nav.
      if ((isAuthRoute && !loc.startsWith('/legal/')) ||
          loc == '/gym-setup' ||
          isStaffRoute ||
          isMemberRoute) {
        // Cold-start fast path: the destination was resolved on a previous
        // launch — skip the network round trips that made startup slow.
        final cached = prefs.getString('home_route');
        // A cached home is enough to leave auth, but route authorization still
        // needs a fresh role lookup for a directly opened portal URL.
        if (cached != null &&
            !isStaffRoute &&
            !isMemberRoute &&
            loc != '/gym-setup') {
          return cached;
        }

        // We just resolved this user to /gym-setup; this is GoRouter re-running
        // redirect for that destination. Don't repeat the lookup.
        if (_gymSetupResolvedFor == user.id) {
          return loc == '/gym-setup' ? null : '/gym-setup';
        }

        final client = Supabase.instance.client;
        List<dynamic> results;
        try {
          results = await Future.wait([
            client
                .from('profiles')
                .select('id, role')
                .eq('id', user.id)
                .maybeSingle(),
            client
                .from('members')
                .select('id')
                .eq('user_id', user.id)
                .maybeSingle(),
          ]);
        } catch (e) {
          debugPrint('[GymCRM] router redirect lookup failed: $e');
          // Network/DB hiccup — stay put; redirect re-runs on the next auth/nav event.
          return null;
        }

        if (results[0] != null) {
          await prefs.setString('home_route', '/staff/dashboard');
          // Navigation is a convenience layer, not the security boundary (RLS
          // remains authoritative), but never render a portal or hidden screen
          // merely because someone guessed its URL.
          if (isMemberRoute || loc == '/gym-setup' || isAuthRoute) {
            return '/staff/dashboard';
          }
          // Per-staff permissions are branch-specific and load through
          // Riverpod. Route builders below render a meaningful denied state;
          // Supabase RLS/RPC checks remain the security boundary.
          return null;
        }
        if (results[1] != null) {
          await prefs.setString('home_route', '/portal/home');
          if (isStaffRoute || loc == '/gym-setup' || isAuthRoute) {
            return '/portal/home';
          }
          return null;
        }

        // Brand-new owner who signed up but hasn't created a gym yet —
        // don't cache: the route changes as soon as setup_gym completes.
        _gymSetupResolvedFor = user.id;
        return loc == '/gym-setup' ? null : '/gym-setup';
      }

      return null;
    },
    routes: [
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/consent',
        builder: (_, __) => const ConsentScreen(),
      ),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/login/member',
        builder: (_, __) => const MemberLoginScreen(),
      ),
      GoRoute(
        path: '/login/member/help',
        builder: (_, __) => const MemberHelpScreen(),
      ),
      GoRoute(
        path: '/login/phone-otp',
        builder: (_, __) => const PhoneOtpScreen(),
      ),
      GoRoute(
        path: '/login/member-signup',
        builder: (_, __) => const MemberSignupScreen(),
      ),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(path: '/gym-setup', builder: (_, __) => const GymSetupScreen()),

      // Staff shell — 4 branches: Home, Members, Billing, Check-in
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => StaffShell(shell: shell),
        branches: [
          // 0 — Home/Dashboard
          StatefulShellBranch(
            navigatorKey: _staffNavigatorKey,
            routes: [
              GoRoute(
                path: '/staff/dashboard',
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),
          // 1 — Members
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/members',
                builder: (_, __) => const PermissionGate(
                  module: GymModule.members,
                  child: MembersScreen(),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => PermissionGate(
                      module: GymModule.members,
                      child: MemberDetailScreen(
                        memberId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Billing
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/billing',
                builder: (_, __) => const PermissionGate(
                  module: GymModule.payments,
                  child: BillingScreen(),
                ),
              ),
            ],
          ),
          // 3 — Check-in
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/check-in',
                builder: (_, __) => const PermissionGate(
                  module: GymModule.attendance,
                  child: CheckInScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // Non-shell staff routes (full screen)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/first-setup',
        builder: (_, __) => const FirstSetupScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/upcoming-payments',
        builder: (_, state) => PermissionGate(
          module: GymModule.payments,
          child: UpcomingPaymentsScreen(
            initialTabExpiring: state.uri.queryParameters['tab'] == 'expiring',
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/classes',
        builder: (_, __) => const PermissionGate(
          module: GymModule.batches,
          child: ClassesScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/leads',
        builder: (_, __) =>
            const PermissionGate(module: GymModule.leads, child: LeadsScreen()),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/expenses',
        builder: (_, __) => const PermissionGate(
          module: GymModule.expenses,
          child: ExpensesScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/no-access',
        builder: (_, state) => NoAccessScreen(
          feature: state.uri.queryParameters['feature'] ?? 'This area',
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/reports',
        builder: (_, __) => const PermissionGate(
          module: GymModule.reports,
          child: ReportsScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/exports',
        builder: (_, __) => const PermissionGate(
          module: GymModule.reports,
          action: GymAction.export,
          child: DataExportScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/activity-log',
        builder: (_, __) => const PermissionGate(
          module: GymModule.reports,
          child: ActivityLogScreen(),
        ),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => PermissionGate(
              module: GymModule.reports,
              child: ActivityLogDetailScreen(
                entryId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/attendance-calendar',
        builder: (_, __) => const PermissionGate(
          module: GymModule.attendance,
          child: AttendanceCalendarScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/settings',
        builder: (_, __) => const PermissionGate(
          module: GymModule.settings,
          child: SettingsScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/settings/invoices',
        builder: (_, __) => const PermissionGate(
          module: GymModule.settings,
          action: GymAction.edit,
          child: InvoiceSettingsScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/reminders',
        builder: (_, __) => const RemindersScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/communications',
        builder: (_, __) => const CommunicationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/staff',
        builder: (_, __) =>
            const PermissionGate(module: GymModule.staff, child: StaffScreen()),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/staff/permissions',
        builder: (_, __) => const PermissionGate(
          module: GymModule.staff,
          action: GymAction.edit,
          child: StaffPermissionsScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/workout-plans',
        builder: (_, __) => const PermissionGate(
          module: GymModule.pt,
          child: StaffWorkoutPlansScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/diet-plans',
        builder: (_, __) => const PermissionGate(
          module: GymModule.services,
          child: StaffDietPlansScreen(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/staff/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),

      // Member shell with bottom nav
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MemberShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _memberNavigatorKey,
            routes: [
              GoRoute(
                path: '/portal/home',
                builder: (_, __) => const PortalHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal/billing',
                builder: (_, __) => const MemberBillingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal/workout',
                builder: (_, __) => const WorkoutScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal/diet',
                builder: (_, __) => const DietScreen(),
              ),
            ],
          ),
        ],
      ),

      GoRoute(path: '/portal/qr', builder: (_, __) => const MemberQrScreen()),
      GoRoute(
        path: '/portal/heatmap',
        builder: (_, __) => const AttendanceHeatmapScreen(),
      ),

      // Invoice detail — accessible from both staff billing and member billing
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/invoice/:id',
        builder: (_, state) =>
            InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
      ),

      // Legal routes — accessible from signup + settings (no auth required)
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/legal/privacy',
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/legal/terms',
        builder: (_, __) => const TermsScreen(),
      ),
    ],
  );

  // Screen tracking. A delegate listener (not navigator observers) because
  // StatefulShellRoute branches have their own navigators the root observer
  // never sees. Firebase is only initialized on Android (see main.dart).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    String? lastScreen;
    router.routerDelegate.addListener(() {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path == lastScreen) return;
      lastScreen = path;
      FirebaseAnalytics.instance.logScreenView(screenName: path);
    });
  }

  return router;
});
