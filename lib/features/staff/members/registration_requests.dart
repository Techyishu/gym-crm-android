import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/data_refresh.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/redesign.dart' show showConfirmDialog;
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../registration/registration_share.dart';

/// What a member typed on the public `/register/:token` form, carried into the
/// Add member page so staff review, pick the plan terms, record paid / unpaid
/// and accept in the one form they already know.
class RegistrationPrefill {
  final String requestId;
  final String name;
  final String phone;
  final String? email;
  final String? dob;
  final String? bloodGroup;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? planId;
  final Uint8List? photo;
  const RegistrationPrefill({
    required this.requestId,
    required this.name,
    required this.phone,
    this.email,
    this.dob,
    this.bloodGroup,
    this.emergencyName,
    this.emergencyPhone,
    this.planId,
    this.photo,
  });
}

String _last9(Object? phone) {
  final d = '${phone ?? ''}'.replaceAll(RegExp(r'\D'), '');
  return d.length <= 9 ? d : d.substring(d.length - 9);
}

/// Whole years old on today's date, from a 'YYYY-MM-DD' date of birth.
int? _ageFromDob(String? dob) {
  final d = DateTime.tryParse(dob ?? '');
  if (d == null) return null;
  final now = DateTime.now();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
  return age;
}

/// Under 18 on the day, from a 'YYYY-MM-DD' date of birth.
bool isUnder18(String? dob) => (_ageFromDob(dob) ?? 99) < 18;

/// Pending registrations for this gym. RLS only returns rows to staff who can
/// edit members, so everyone else gets an empty list and no banner. Each row
/// carries `duplicate: true` when its phone already belongs to a member.
final registrationRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(gymDataVersionProvider);
      final gymId = await ref.watch(gymIdProvider.future);
      final client = Supabase.instance.client;
      final data = await client
          .from('member_registration_requests')
          .select(
            'id, first_name, last_name, phone, email, dob, blood_group, '
            'emergency_contact_name, emergency_contact_phone, plan_id, '
            'has_photo, created_at, membership_plans(name)',
          )
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .order('created_at');
      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return rows;

      final tails = rows.map((r) => _last9(r['phone'])).toSet();
      final existing = await client
          .from('members')
          .select('phone')
          .eq('gym_id', gymId)
          .or(tails.map((t) => 'phone.ilike.%$t').join(','));
      final have = (existing as List).map((m) => _last9(m['phone'])).toSet();
      return [
        for (final r in rows) {...r, 'duplicate': have.contains(_last9(r['phone']))},
      ];
    });

/// One request's photo, fetched on demand (the list query never carries the
/// bytes). Kept alive so going back from the review form doesn't refetch it.
final _registrationPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, id) async {
      ref.keepAlive();
      try {
        final b64 = await Supabase.instance.client.rpc(
          'get_registration_photo',
          params: {'p_request_id': id},
        );
        if (b64 is String && b64.isNotEmpty) return base64Decode(b64);
      } catch (e) {
        debugPrint('[GymCRM] registration photo fetch failed: $e');
      }
      return null;
    });

typedef RegistrationReviewer = Future<void> Function(RegistrationPrefill p);

/// "3 new member registrations · Review" — sits above the members list.
class RegistrationRequestsBanner extends ConsumerWidget {
  final RegistrationReviewer onReview;
  const RegistrationRequestsBanner({super.key, required this.onReview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(registrationRequestsProvider).valueOrNull?.length ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showRegistrationRequests(context, onReview),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg, size: 20, color: AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    n == 1
                        ? '1 new member registration'
                        : '$n new member registrations',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                const Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the full-page review list (above the shell, so the bottom bar isn't
/// in the way while working through several requests).
Future<void> showRegistrationRequests(
  BuildContext context,
  RegistrationReviewer onReview,
) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute(builder: (_) => RegistrationRequestsScreen(onReview: onReview)),
);

class RegistrationRequestsScreen extends ConsumerStatefulWidget {
  final RegistrationReviewer onReview;
  const RegistrationRequestsScreen({super.key, required this.onReview});

  @override
  ConsumerState<RegistrationRequestsScreen> createState() =>
      _RegistrationRequestsScreenState();
}

class _RegistrationRequestsScreenState
    extends ConsumerState<RegistrationRequestsScreen> {
  final _busy = <String>{};

  Future<void> _review(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    setState(() => _busy.add(id));
    Uint8List? photo;
    if (r['has_photo'] == true) {
      photo = await ref.read(_registrationPhotoProvider(id).future);
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    await widget.onReview(
      RegistrationPrefill(
        requestId: id,
        name: name,
        phone: '${r['phone']}',
        email: r['email'] as String?,
        dob: r['dob'] as String?,
        bloodGroup: r['blood_group'] as String?,
        emergencyName: r['emergency_contact_name'] as String?,
        emergencyPhone: r['emergency_contact_phone'] as String?,
        planId: r['plan_id'] as String?,
        photo: photo,
      ),
    );
    ref.invalidate(registrationRequestsProvider);
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    final ok = await showConfirmDialog(
      context,
      title: 'Reject registration?',
      body:
          '${name.isEmpty ? 'This request' : name} will be removed. '
          'They can register again with the link.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Reject',
    );
    if (ok != true || !mounted) return;
    final id = r['id'] as String;
    setState(() => _busy.add(id));
    String? error;
    try {
      await Supabase.instance.client.rpc(
        'decide_member_registration',
        params: {'p_id': id, 'p_approve': false},
      );
    } catch (e) {
      debugPrint('[GymCRM] reject registration failed: $e');
      error = 'Could not reject the request. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
    ref.invalidate(registrationRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(registrationRequestsProvider);
    final requests = async.valueOrNull ?? const <Map<String, dynamic>>[];
    final n = requests.length;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(n == 0 ? 'Member registrations' : 'Registrations · $n'),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveContent(
          child: RefreshIndicator(
            color: AppTheme.accent,
            onRefresh: () async => ref.invalidate(registrationRequestsProvider),
            child: async.isLoading && requests.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : requests.isEmpty
                ? _empty()
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(2, 0, 2, 12),
                        child: Text(
                          'Members who filled in their own details. Check '
                          'them, record payment and add them.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.inkSoft,
                            height: 1.35,
                          ),
                        ),
                      ),
                      for (final r in requests) ...[
                        _RequestCard(
                          request: r,
                          busy: _busy.contains(r['id']),
                          onReview: () => _review(r),
                          onReject: () => _reject(r),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final gymName =
        '${(ref.watch(staffProfileProvider).valueOrNull?['gyms'] as Map?)?['name'] ?? 'your gym'}';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 80, 28, 24),
      children: [
        const Icon(Icons.how_to_reg_outlined, size: 56, color: AppTheme.inkHint),
        const SizedBox(height: 16),
        const Text(
          'No registrations waiting',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'When a member scans your QR and fills in their details, '
          'they will show up here.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppTheme.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () =>
              enableAndShowRegistration(context, ref, gymName: gymName),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Show registration QR'),
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onReview;
  final VoidCallback onReject;
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onReview,
    required this.onReject,
  });

  Widget _chip(String text, Color bg, Color fg) => Container(
    margin: const EdgeInsets.only(right: 6, top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
    ),
  );

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.inkHint),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final id = r['id'] as String;
    final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
    final plan = (r['membership_plans'] as Map?)?['name'] as String?;
    final dob = r['dob'] as String?;
    final age = _ageFromDob(dob);
    final blood = r['blood_group'] as String?;
    final email = r['email'] as String?;
    final emName = r['emergency_contact_name'] as String?;
    final emPhone = r['emergency_contact_phone'] as String?;
    final photo = r['has_photo'] == true
        ? ref.watch(_registrationPhotoProvider(id)).valueOrNull
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: photo != null
                    ? Image.memory(photo, width: 60, height: 60, fit: BoxFit.cover)
                    : Text(
                        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.inkSoft,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'New member' : name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r['phone']}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                    Wrap(
                      children: [
                        if (plan != null)
                          _chip(
                            plan,
                            AppTheme.accent.withValues(alpha: 0.1),
                            AppTheme.accent,
                          ),
                        if (r['duplicate'] == true)
                          _chip(
                            'Already a member',
                            AppTheme.statusDangerBg,
                            AppTheme.statusDanger,
                          ),
                        if (isUnder18(dob))
                          _chip('Under 18', AppTheme.statusWarnBg, AppTheme.ink),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                timeAgo(r['created_at'] as String?),
                style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
              ),
            ],
          ),
          if (dob != null || blood != null || email != null || emName != null || emPhone != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 6),
            if (dob != null)
              _line(
                Icons.cake_outlined,
                '${formatDateFromString(dob)}${age != null ? ' · $age years' : ''}',
              ),
            if (blood != null) _line(Icons.water_drop_outlined, 'Blood group $blood'),
            if (email != null) _line(Icons.mail_outline, email),
            if (emName != null || emPhone != null)
              _line(
                Icons.emergency_outlined,
                'Emergency: ${[?emName, ?emPhone].join(' · ')}',
              ),
          ],
          const SizedBox(height: 14),
          if (busy)
            const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    // Local minimumSize: the theme's full-width default would
                    // squeeze the sibling button in this Row.
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: onReview,
                      child: const Text('Review & add'),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
