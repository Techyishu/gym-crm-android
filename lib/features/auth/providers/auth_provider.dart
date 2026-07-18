import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/formatters.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// True only while [AuthNotifier.signUp]'s create → sign-out → send-OTP handshake
/// is in flight. Email confirmation is OFF, so `auth.signUp()` instantly creates
/// a session and emits a `signedIn` event; the router listens to every auth
/// change, so without this guard it navigates to /gym-setup mid-handshake and
/// the OTP screen only renders intermittently. The router treats a true value as
/// "stay on the current screen". See `core/router.dart`.
final signupHandshakeInProgress = ValueNotifier<bool>(false);

// Streams auth state changes
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

// Resolves whether a logged-in user is staff, member, or a brand-new owner who
// still has to complete gym setup.
// Returns 'staff', 'member', 'setup', or null (not logged in)
final userTypeProvider = FutureProvider<String?>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;

  final profile = await client
      .from('profiles')
      .select('id, role')
      .eq('id', user.id)
      .maybeSingle();
  if (profile != null) return 'staff';

  final member = await client
      .from('members')
      .select('id')
      .eq('user_id', user.id)
      .maybeSingle();
  if (member != null) return 'member';

  return 'setup';
});

// Staff profile
final staffProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;

  final profile = await client
      .from('profiles')
      .select(
        'id, role, gym_id, first_name, last_name, phone, '
        'gyms(id, name, slug, plan, settings, razorpay_key_id, '
        'registration_enabled, registration_token, '
        'plan_expires_at, trial_ends_at, dodo_subscription_id, plan_price)',
      )
      .eq('id', user.id)
      .maybeSingle();

  final settings = (profile?['gyms'] as Map<String, dynamic>?)?['settings'];
  setCurrency((settings as Map<String, dynamic>?)?['currency'] as String?);
  return profile;
});

// Convenience provider: just the role string for the current staff user.
final staffRoleProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(staffProfileProvider.future);
  return profile?['role'] as String?;
});

/// The gym_id for the logged-in staff user.
/// Cached by Riverpod — a single DB round-trip shared across every screen.
/// All screen providers watch this instead of fetching profiles individually.
/// Invalidated on sign-out so the next login gets a fresh value.
final gymIdProvider = FutureProvider<String>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) throw Exception('Not authenticated');

  // maybeSingle() returns null instead of throwing when no row exists
  // (.single() would crash for deleted/incomplete accounts).
  final profile = await client
      .from('profiles')
      .select('gym_id')
      .eq('id', user.id)
      .maybeSingle();

  final gymId = profile?['gym_id'] as String?;
  if (gymId == null || gymId.isEmpty) {
    throw Exception('No gym assigned — please complete gym setup');
  }
  return gymId;
});

// Member record for portal users
final memberRecordProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;

  final member = await client
      .from('members')
      .select('*, memberships(*, membership_plans(*)), gyms(settings)')
      .eq('user_id', user.id)
      .maybeSingle();

  final settings = (member?['gyms'] as Map<String, dynamic>?)?['settings'];
  setCurrency((settings as Map<String, dynamic>?)?['currency'] as String?);
  return member;
});

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final SupabaseClient _client;
  final Ref _ref;

  AuthNotifier(this._client, this._ref) : super(const AsyncValue.data(null));

  Future<String?> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      // Clear any stale error states that built up before the session existed.
      _ref.invalidate(gymIdProvider);
      _ref.invalidate(staffProfileProvider);
      _ref.invalidate(userTypeProvider);
      _ref.invalidate(memberRecordProvider);
      state = const AsyncValue.data(null);
      return null;
    } on AuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return e.message;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return 'Something went wrong. Please try again.';
    }
  }

  /// Email/password signup. Mirrors the web signup form — first/last name and
  /// phone are stored in user_metadata so gym-setup can pre-fill them.
  /// "Confirm email" is OFF in Supabase so signUp() does not send any email.
  /// We call signInWithOtp() immediately after so the user gets a 6-digit code
  /// via the "Magic link or OTP" template — one email, no rate-limit clash.
  /// Returns null on success, or an error message.
  Future<String?> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    // Hold the guard across the whole handshake so the router ignores the
    // transient session that signUp() creates (and the sign-out that follows)
    // and keeps the user on the signup screen until the OTP step renders.
    signupHandshakeInProgress.value = true;
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
        },
      );
      // With "Confirm email" OFF, signUp() creates an instant session which
      // would trigger the router redirect before the OTP screen shows.
      // Sign out to clear it — the session is granted only after OTP verify.
      await _client.auth.signOut();
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );
      state = const AsyncValue.data(null);
      return null;
    } on AuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return e.message;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return 'Something went wrong. Please try again.';
    } finally {
      signupHandshakeInProgress.value = false;
    }
  }

  /// Whether signup created an active session (email confirmation disabled).
  /// When false, the user must confirm via the email link before they can sign in.
  bool get hasSession => _client.auth.currentSession != null;

  Future<String?> signUpWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.gymcrm://login-callback/',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not start Google sign-in. Please try again.';
    }
  }

  /// Creates the gym + owner profile via the `setup_gym` Postgres RPC
  /// (SECURITY DEFINER — bypasses RLS for the initial profile insert, exactly
  /// like the web `/api/gym/setup` route does with the service-role client).
  /// Returns null on success, or an error message.
  Future<String?> setupGym({
    required String gymName,
    String? city,
    String? phone,
    String? gymType,
    String? memberCount,
    required List<String> goals,
  }) async {
    try {
      await _client.rpc('setup_gym', params: {
        'p_gym_name': gymName,
        'p_city': city,
        'p_phone': phone,
        'p_gym_type': gymType,
        'p_member_count': memberCount,
        'p_goals': goals,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Setup failed. Please try again.';
    }
  }

  Future<String?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    state = const AsyncValue.loading();
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      // Clear any stale error states so the dashboard loads fresh after OTP verify.
      _ref.invalidate(gymIdProvider);
      _ref.invalidate(staffProfileProvider);
      _ref.invalidate(userTypeProvider);
      _ref.invalidate(memberRecordProvider);
      state = const AsyncValue.data(null);
      return null;
    } on AuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return e.message;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return 'Verification failed. Please try again.';
    }
  }

  Future<String?> resendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not resend code. Please try again.';
    }
  }

  Future<String?> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('[GymCRM] resetPassword error: $e');
      return 'Could not send reset email. Please try again.';
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('[GymCRM] signOut error: $e');
    } finally {
      _ref.invalidate(gymIdProvider);
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(ref.watch(supabaseProvider), ref);
});
