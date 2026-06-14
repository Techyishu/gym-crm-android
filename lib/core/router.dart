import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'router_refresh.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/staff/gym_setup/gym_setup_screen.dart';
import '../features/staff/dashboard/dashboard_screen.dart';
import '../features/staff/members/members_screen.dart';
import '../features/staff/members/member_detail_screen.dart';
import '../features/staff/members/upcoming_payments_screen.dart';
import '../features/staff/billing/billing_screen.dart';
import '../features/staff/paywall/paywall_screen.dart';
import '../features/staff/classes/classes_screen.dart';
import '../features/staff/check_in/check_in_screen.dart';
import '../features/staff/leads/leads_screen.dart';
import '../features/staff/reports/reports_screen.dart';
import '../features/staff/settings/settings_screen.dart';
import '../features/staff/communications/communications_screen.dart';
import '../features/staff/staff/staff_screen.dart';
import '../features/staff/reminders/reminder_settings_screen.dart';
import '../features/member/portal/portal_home_screen.dart';
import '../features/member/bookings/bookings_screen.dart';
import '../features/member/billing/member_billing_screen.dart';
import '../features/member/workout/workout_screen.dart';
import '../features/member/attendance/heatmap_screen.dart';
import '../features/member/qr/qr_screen.dart';
import '../features/legal/privacy_policy_screen.dart';
import '../features/legal/terms_screen.dart';
import '../features/shared/invoice_detail_screen.dart';
import 'shells/staff_shell.dart';
import 'shells/member_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _staffNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'staff');
final _memberNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'member');

/// Remembers that the user-resolution lookup just decided this user belongs on
/// /gym-setup. /gym-setup isn't persisted to `home_route` (it stops being the
/// destination the moment setup completes), so GoRouter re-runs redirect for
/// /gym-setup itself — this guard stops that re-run from repeating the
/// profiles+members round trip, which is what made the post-OTP transition slow.
/// Cleared on sign-out; made moot once setup writes `home_route`.
String? _gymSetupResolvedFor;

/// Cached SharedPreferences instance — avoids re-initialising the plugin on
/// every router redirect (the getInstance() call is async even when cached
/// internally, adding unnecessary latency to every navigation event).
SharedPreferences? _sharedPrefs;

final routerProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  );
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/onboarding',
    // Also refresh when the signup handshake guard flips, so the redirect is
    // re-evaluated the moment it releases.
    refreshListenable: Listenable.merge([refreshStream, signupHandshakeInProgress]),
    redirect: (context, state) async {
      // signUp() is mid create→sign-out→send-OTP handshake: ignore the transient
      // auth events it emits and keep the user on the signup screen so the OTP
      // step can render. See [signupHandshakeInProgress].
      if (signupHandshakeInProgress.value) return null;

      final prefs = _sharedPrefs ??= await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      final user = Supabase.instance.client.auth.currentUser;

      // Show onboarding only if not done AND not already logged in.
      // If user is logged in but flag is missing (e.g. app data cleared),
      // mark it done and continue so they don't get stuck on onboarding.
      if (!onboardingDone) {
        // First install — always show the intro slides.
        return state.matchedLocation == '/onboarding' ? null : '/onboarding';
      } else if (state.matchedLocation == '/onboarding') {
        // Already done — never show again.
        return '/login';
      }
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/login') ||
          loc.startsWith('/signup') ||
          loc.startsWith('/forgot-password') ||
          loc == '/onboarding';

      if (user == null) {
        // Stale cache from a previous account must not survive sign-out.
        if (prefs.containsKey('home_route')) await prefs.remove('home_route');
        _gymSetupResolvedFor = null;
        _sharedPrefs = null; // Force re-init next time so the cleared key is visible
        return isAuthRoute ? null : '/login';
      }

      // Resolve where this user belongs only when it matters (leaving an auth
      // route, or guarding /gym-setup) so we don't hit the DB on every nav.
      if (isAuthRoute || loc == '/gym-setup') {
        // Cold-start fast path: the destination was resolved on a previous
        // launch — skip the network round trips that made startup slow.
        final cached = prefs.getString('home_route');
        if (cached != null) return cached;

        // We just resolved this user to /gym-setup; this is GoRouter re-running
        // redirect for that destination. Don't repeat the lookup.
        if (_gymSetupResolvedFor == user.id) {
          return loc == '/gym-setup' ? null : '/gym-setup';
        }

        final client = Supabase.instance.client;
        final results = await Future.wait([
          client.from('profiles').select('id').eq('id', user.id).maybeSingle(),
          client.from('members').select('id').eq('user_id', user.id).maybeSingle(),
        ]);

        if (results[0] != null) {
          await prefs.setString('home_route', '/staff/dashboard');
          return '/staff/dashboard';
        }
        if (results[1] != null) {
          await prefs.setString('home_route', '/portal/home');
          return '/portal/home';
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
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/gym-setup',
        builder: (_, __) => const GymSetupScreen(),
      ),

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
                builder: (_, __) => const MembersScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => MemberDetailScreen(memberId: state.pathParameters['id']!),
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
                builder: (_, __) => const BillingScreen(),
              ),
            ],
          ),
          // 3 — Check-in
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/staff/check-in',
                builder: (_, __) => const CheckInScreen(),
              ),
            ],
          ),
        ],
      ),

      // Non-shell staff routes (full screen)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/staff/upcoming-payments',
        builder: (_, __) => const UpcomingPaymentsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/staff/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
      GoRoute(path: '/staff/classes', builder: (_, __) => const ClassesScreen()),
      GoRoute(path: '/staff/leads', builder: (_, __) => const LeadsScreen()),
      GoRoute(path: '/staff/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/staff/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/staff/communications', builder: (_, __) => const CommunicationsScreen()),
      GoRoute(path: '/staff/staff', builder: (_, __) => const StaffScreen()),
      GoRoute(path: '/staff/reminders', builder: (_, __) => const ReminderSettingsScreen()),

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
                path: '/portal/bookings',
                builder: (_, __) => const BookingsScreen(),
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
        ],
      ),

      GoRoute(
        path: '/portal/qr',
        builder: (_, __) => const MemberQrScreen(),
      ),
      GoRoute(
        path: '/portal/heatmap',
        builder: (_, __) => const AttendanceHeatmapScreen(),
      ),

      // Invoice detail — accessible from both staff billing and member billing
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/invoice/:id',
        builder: (_, state) => InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
      ),

      // Legal routes — accessible from signup + settings (no auth required)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/legal/privacy',
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/legal/terms',
        builder: (_, __) => const TermsScreen(),
      ),
    ],
  );
});

