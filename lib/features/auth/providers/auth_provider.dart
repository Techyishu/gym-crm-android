import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/activity_log_service.dart';
import '../../../core/services/offline_checkin_queue.dart';
import '../../../core/utils/formatters.dart';

const _activeGymIdPrefsKey = 'active_gym_id';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

// --dart-define=WEB_APP_BASE_URL=http://localhost:3000 to test Google
// sign-in against a local gym-crm dev server instead of production.
const _webAppBaseUrl = String.fromEnvironment(
  'WEB_APP_BASE_URL',
  defaultValue: 'https://gymcrm.in',
);

/// Canonical synthetic identity for phone-only members — must match the
/// `verify-phone-otp` edge function's member-signup path, or login won't
/// resolve to the account created there.
String memberSyntheticEmail(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final last10 = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  return '$last10@member.gymcrm.internal';
}

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

// Staff profile — 'gyms' reflects whichever branch is currently active
// (see gymIdProvider), not necessarily the staff member's primary gym_id.
final staffProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;

  final activeGymId = await ref.watch(gymIdProvider.future);

  final profile = await client
      .from('profiles')
      .select('id, role, gym_id, first_name, last_name, phone')
      .eq('id', user.id)
      .maybeSingle();
  if (profile == null) return null;

  final gym = await client
      .from('gyms')
      .select(
        'id, name, slug, member_code, plan, settings, razorpay_key_id, '
        'registration_enabled, registration_token, whatsapp_reminder_enabled, '
        'plan_expires_at, trial_ends_at, dodo_subscription_id, plan_price, status, legacy_pricing, created_at',
      )
      .eq('id', activeGymId)
      .maybeSingle();

  final settings = gym?['settings'];
  setCurrency((settings as Map<String, dynamic>?)?['currency'] as String?);
  return {...profile, 'gyms': gym};
});

// Convenience provider: just the role string for the current staff user.
final staffRoleProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(staffProfileProvider.future);
  return profile?['role'] as String?;
});

/// The gym_id every screen scopes its queries by — the staff member's
/// currently ACTIVE branch. Defaults to their primary profiles.gym_id;
/// persisted in SharedPreferences once they switch branches via
/// AuthNotifier.switchActiveGym(). Falls back to primary if the persisted
/// branch is no longer one they have access to.
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

  final primaryGymId = profile?['gym_id'] as String?;
  if (primaryGymId == null || primaryGymId.isEmpty) {
    throw Exception('No gym assigned — please complete gym setup');
  }

  final prefs = await SharedPreferences.getInstance();
  final activeGymId = prefs.getString(_activeGymIdPrefsKey);
  if (activeGymId == null || activeGymId == primaryGymId) {
    // Keep the offline check-in cache in sync with the resolved active gym
    // every time it's looked up — not just after an online check-in — so a
    // branch switch followed immediately by going offline never enqueues a
    // check-in against the wrong (stale) branch.
    await OfflineCheckInQueue.cacheGymId(primaryGymId);
    return primaryGymId;
  }

  final access = await client
      .from('staff_gym_access')
      .select('gym_id')
      .eq('profile_id', user.id)
      .eq('gym_id', activeGymId)
      .maybeSingle();
  if (access == null) {
    await prefs.remove(_activeGymIdPrefsKey);
    await OfflineCheckInQueue.cacheGymId(primaryGymId);
    return primaryGymId;
  }
  await OfflineCheckInQueue.cacheGymId(activeGymId);
  return activeGymId;
});

/// Every gym branch the current staff member is linked to (their primary
/// gym plus any added via AuthNotifier.createGymBranch()), for the branch
/// switcher UI.
final myGymBranchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final rows = await client
      .from('staff_gym_access')
      .select('gym_id, role, gyms(id, name, slug)')
      .eq('profile_id', user.id)
      .order('created_at');
  return List<Map<String, dynamic>>.from(rows as List);
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

      final profile = await _client.from('profiles').select('gym_id').eq('id', _client.auth.currentUser!.id).maybeSingle();
      final gymId = profile?['gym_id'] as String?;
      if (gymId != null) {
        ActivityLogService.logActivity(gymId: gymId, action: 'login', metadata: {'via': 'android'});
      }

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
    if (kIsWeb) {
      // Flutter web can't safely do the OAuth code exchange itself — Safari's
      // Intelligent Tracking Prevention breaks it after the cross-site
      // Google → Supabase → app redirect chain. Hand the whole flow to
      // gym-crm's server instead: /auth/dashboard-login starts it, exchanges
      // the code server-side in /auth/dashboard-callback, and redirects back
      // here with the session (see main.dart's _handleWebGoogleAuthHandoff).
      try {
        await launchUrl(
          Uri.parse('$_webAppBaseUrl/auth/dashboard-login'),
          webOnlyWindowName: '_self',
        );
        return null;
      } catch (e) {
        return 'Could not start Google sign-in. Please try again.';
      }
    }
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
    String? currency,
    required List<String> goals,
  }) async {
    try {
      final gymId = await _client.rpc('setup_gym', params: {
        'p_gym_name': gymName,
        'p_city': city,
        'p_phone': phone,
        'p_gym_type': gymType,
        'p_member_count': memberCount,
        'p_goals': goals,
      }) as String;
      // setup_gym doesn't take a currency param — set it via the same
      // gyms.settings JSONB path Settings > Gym Details uses.
      if (currency != null && currency.isNotEmpty) {
        final gym = await _client.from('gyms').select('settings').eq('id', gymId).single();
        final settings = {
          ...Map<String, dynamic>.from(gym['settings'] as Map? ?? {}),
          'currency': currency,
        };
        await _client.from('gyms').update({'settings': settings}).eq('id', gymId);
      }
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

  /// Mobile OTP login (Android only). [phone] and [msg91AccessToken] come from
  /// the MSG91 widget SDK's verifyOTP() response after the user enters the code
  /// they received by SMS. The `verify-phone-otp` edge function re-checks that
  /// access-token against MSG91 server-side, finds-or-creates the matching
  /// Supabase auth user, and returns a magiclink token — which we redeem here
  /// via the same verifyOTP() call the email flow already uses, so this ends
  /// up creating a real session exactly like `verifyEmailOtp` does.
  /// [gymId], when passed, switches the edge function to member self-serve
  /// signup: phone must match an existing `members` row for that gym.
  Future<String?> verifyPhoneOtpToken({
    required String phone,
    required String msg91AccessToken,
    String? gymId,
  }) async {
    state = const AsyncValue.loading();
    try {
      final res = await _client.functions.invoke(
        'verify-phone-otp',
        body: {
          'accessToken': msg91AccessToken,
          'phone': phone,
          if (gymId != null) 'gymId': gymId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      final email = data?['email'] as String?;
      final hashedToken = data?['hashedToken'] as String?;
      if (email == null || hashedToken == null) {
        state = AsyncValue.error('Phone verification failed', StackTrace.current);
        return (data?['error'] as String?) ?? 'Phone verification failed. Please try again.';
      }

      await _client.auth.verifyOTP(
        tokenHash: hashedToken,
        type: OtpType.magiclink,
      );
      _ref.invalidate(gymIdProvider);
      _ref.invalidate(staffProfileProvider);
      _ref.invalidate(userTypeProvider);
      _ref.invalidate(memberRecordProvider);
      state = const AsyncValue.data(null);
      return null;
    } on AuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return e.message;
    } catch (e, st) {
      debugPrint('[GymCRM] verifyPhoneOtpToken error: $e\n$st');
      state = AsyncValue.error(e, StackTrace.current);
      return 'Phone verification failed: $e';
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

  /// Sets a password on the current session. Used right after member
  /// self-serve OTP signup — the account is created with no password, so
  /// this is required before the member can log in again without OTP.
  Future<String?> setPassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('[GymCRM] setPassword error: $e');
      return 'Could not set password. Please try again.';
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('[GymCRM] signOut error: $e');
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeGymIdPrefsKey);
      _ref.invalidate(gymIdProvider);
    }
  }

  /// Switches which gym branch every screen scopes its data by. Persists
  /// across restarts until switched again or the user signs out.
  Future<void> switchActiveGym(String gymId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGymIdPrefsKey, gymId);
    _ref.invalidate(gymIdProvider);
    _ref.invalidate(staffProfileProvider);
  }

  /// Creates a new gym branch under the current owner via the `create_gym_branch`
  /// RPC and links it to their account — does not touch profiles.gym_id.
  /// Returns the new gym id on success, or an error message.
  Future<Object> createGymBranch({
    required String gymName,
    String? city,
    String? phone,
    String? gymType,
    String? memberCount,
    List<String> goals = const [],
  }) async {
    try {
      final gymId = await _client.rpc('create_gym_branch', params: {
        'p_gym_name': gymName,
        'p_city': city,
        'p_phone': phone,
        'p_gym_type': gymType,
        'p_member_count': memberCount,
        'p_goals': goals,
      }) as String;
      _ref.invalidate(myGymBranchesProvider);
      return gymId;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not create gym branch. Please try again.';
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(ref.watch(supabaseProvider), ref);
});
