import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/platform_info.dart' as platform_info;
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// Public base URL for member self-registration links (matches the web app).
const _registrationBaseUrl = 'https://gymcrm.in';

// Supabase project URL — hardcoded to match main.dart (required for Shorebird patch compatibility).
// Plain-HTTP bridge (biometric devices can't do TLS) — forwards to the Supabase edge function.
const _biometricBridgeHost = 'bio.gymcrm.in';
const _biometricBridgePort = '58594';

String _uuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

// ─── Gym provider ─────────────────────────────────────────────────────────────
final _gymProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  return await client.from('gyms').select().eq('id', gymId).maybeSingle();
});

// ─── Settings screen ──────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(staffProfileProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile header ───────────────────────────────────────────────
            profile.when(
              loading: () => const _ProfileShimmer(),
              error: (_, __) => const SizedBox.shrink(),
              data: (p) =>
                  p != null ? _ProfileHeader(profile: p) : const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // ── ACCOUNT section ──────────────────────────────────────────────
            _SectionLabel(label: 'ACCOUNT'),
            _SettingsCard(items: [
              _SettingsRow(
                icon: Icons.credit_card_outlined,
                label: 'Subscription',
                onTap: () => context.push('/staff/subscription'),
              ),
              _SettingsRow(
                icon: Icons.person_outline,
                label: 'Edit Profile',
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _EditProfileSheet(
                    profile: profile.value ?? {},
                    onSaved: () => ref.invalidate(staffProfileProvider),
                  ),
                ),
              ),
              _SettingsRow(
                icon: Icons.lock_outline,
                label: 'Change Password',
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _ChangePasswordSheet(),
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // ── GYM section ──────────────────────────────────────────────────
            _SectionLabel(label: 'GYM'),
            _SettingsCard(items: [
              _SettingsRow(
                icon: Icons.business_outlined,
                label: 'Gym Details',
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _GymDetailsSheet(
                    onSaved: () => ref.invalidate(_gymProvider),
                  ),
                ),
              ),
              _SettingsRow(
                icon: Icons.people_outline,
                label: 'Staff',
                onTap: () => context.push('/staff/staff'),
              ),
              _SettingsRow(
                icon: Icons.link,
                label: 'Registration Link',
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _RegistrationLinkSheet(),
                ),
              ),
              // RAZORPAY HIDDEN — re-enable when ready to launch
              // _SettingsRow(
              //   icon: Icons.payments_outlined,
              //   label: 'Payments (Razorpay)',
              //   onTap: () => showAdaptiveSheet(
              //     context: context,
              //     isScrollControlled: true,
              //     useSafeArea: true,
              //     builder: (_) => const _PaymentsSheet(),
              //   ),
              // ),
            ]),

            const SizedBox(height: 20),

            // ── APP section ──────────────────────────────────────────────────
            _SectionLabel(label: 'APP'),
            _SettingsCard(items: [
              if (!kIsWeb)
                _SettingsRow(
                  icon: Icons.share_outlined,
                  label: platform_info.isIOS ? 'Rate us on the App Store' : 'Rate us on Play Store',
                  onTap: () async {
                    final inAppReview = InAppReview.instance;
                    try {
                      await inAppReview.openStoreListing(appStoreId: '6778882176');
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not open the ${platform_info.isIOS ? 'App Store' : 'Play Store'}. Please try again.')),
                        );
                      }
                    }
                  },
                ),
              _SettingsRow(
                icon: Icons.info_outline,
                label: 'Help & Support',
                onTap: () => showAdaptiveSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _SupportTicketSheet(),
                ),
              ),
              _SettingsRow(
                icon: Icons.visibility_outlined,
                label: 'Privacy & data choices',
                onTap: () => context.push('/consent'),
              ),
              _SettingsRow(
                icon: Icons.lock_outline,
                label: 'Privacy Policy',
                onTap: () => context.push('/legal/privacy'),
              ),
              _SettingsRow(
                icon: Icons.info_outline,
                label: 'Terms of Service',
                onTap: () => context.push('/legal/terms'),
              ),
              _SettingsRow(
                icon: Icons.info_outline,
                label: 'About GymCRM',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'GymCRM',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2026 GymCRM',
                ),
              ),
            ]),

            const SizedBox(height: 28),

            // ── Sign Out ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmSignOut(context, ref),
                  icon: const Icon(Icons.logout, color: AppTheme.statusDanger),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(color: AppTheme.statusDanger),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusDanger,
                    side: const BorderSide(color: AppTheme.statusDanger),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Delete Account ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _confirmDeleteAccount(context, ref),
                  icon: const Icon(Icons.logout,
                      color: AppTheme.statusDanger, size: 18),
                  label: const Text(
                    'Delete Account',
                    style: TextStyle(
                        color: AppTheme.statusDanger, fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.statusDanger,
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      )),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authNotifierProvider.notifier).signOut();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppTheme.statusDanger),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        onDeleted: () => ref.read(authNotifierProvider.notifier).signOut(),
      ),
    );
  }
}

// ─── Delete Account dialog ────────────────────────────────────────────────────
class _DeleteAccountDialog extends StatefulWidget {
  final VoidCallback onDeleted;
  const _DeleteAccountDialog({required this.onDeleted});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_ctrl.text.trim() != 'DELETE') {
      setState(() => _error = 'Type DELETE (all caps) to confirm');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not signed in');

      final response = await http.delete(
        Uri.parse('https://www.gymcrm.in/api/account/delete'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.statusCode == 200) {
        if (mounted) Navigator.pop(context);
        widget.onDeleted();
      } else {
        setState(() {
          _error = 'Failed to delete account. Please contact support.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: AppTheme.statusDangerBg, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.delete_outline, size: 26, color: AppTheme.statusDanger),
          ),
          const SizedBox(height: 16),
          const Text('Delete gym account?', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 8),
          const Text(
            'All member records, plans and payment history will be permanently erased.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(hintText: 'Type DELETE to confirm'),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.statusDanger, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: _loading ? null : () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _loading ? null : _delete,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: AppTheme.statusDanger, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Delete', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.inkSoft,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Settings card ────────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<_SettingsRow> items;
  const _SettingsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Column(
          children: items.asMap().entries.map((e) {
            final item = e.value;
            final isLast = e.key == items.length - 1;
            return Column(
              children: [
                ListTile(
                  leading: Icon(item.icon, color: AppTheme.inkSoft, size: 20),
                  title: Text(
                    item.label,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.inkHint,
                    size: 20,
                  ),
                  onTap: item.onTap,
                  minLeadingWidth: 20,
                  horizontalTitleGap: 10,
                ),
                if (!isLast)
                  const Divider(height: 1, indent: 50, endIndent: 0),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SettingsRow {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

// ─── Profile header ───────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final firstName = profile['first_name'] as String? ?? '';
    final lastName  = profile['last_name']  as String? ?? '';
    final role      = profile['role']        as String? ?? 'staff';
    final gym       = profile['gyms']        as Map<String, dynamic>?;

    final gymName = gym?['name'] as String? ?? '$firstName $lastName'.trim();
    final gymInitials = gymName.trim().split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.darkCardDecoration(),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppTheme.darkCard2,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                gymInitials.isEmpty ? '?' : gymInitials,
                style: const TextStyle(
                  color: AppTheme.mintOnDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gymName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: AppTheme.onDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '$firstName $lastName'.trim(),
                      role[0].toUpperCase() + role.substring(1),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.onDarkSoft, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.onDarkSoft, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ProfileShimmer extends StatelessWidget {
  const _ProfileShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(height: 100, color: AppTheme.surface);
  }
}

// ─── Edit Profile sheet ───────────────────────────────────────────────────────
class _EditProfileSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onSaved;
  const _EditProfileSheet({required this.profile, required this.onSaved});

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _phoneCtrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController(
        text: widget.profile['first_name'] as String? ?? '');
    _lastCtrl  = TextEditingController(
        text: widget.profile['last_name']  as String? ?? '');
    _phoneCtrl = TextEditingController(
        text: widget.profile['phone']      as String? ?? '');
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_firstCtrl.text.trim().isEmpty || _lastCtrl.text.trim().isEmpty) {
      setState(() => _error = 'First and last name are required');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.from('profiles').update({
        'first_name': _firstCtrl.text.trim(),
        'last_name':  _lastCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      }).eq('id', user.id);

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = 'Failed to save: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Edit profile',
      child: Column(
        children: [
          if (_error != null) _ErrorBox(message: _error!),
          Row(
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const FieldLabel('First name'),
                  TextFormField(controller: _firstCtrl),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const FieldLabel('Last name'),
                  TextFormField(controller: _lastCtrl),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const FieldLabel('Phone (optional)'),
          TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            child: _loading ? const _Spinner() : const Text('Save profile'),
          ),
        ],
      ),
    );
  }
}

// ─── Change Password sheet ────────────────────────────────────────────────────
class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading        = false;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newCtrl.text),
      );
      setState(() { _done = true; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Failed: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Change password',
      child: _done
          ? Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.check, color: AppTheme.statusActive, size: 30),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Password updated',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.ink),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            )
          : Column(
              children: [
                if (_error != null) _ErrorBox(message: _error!),
                const FieldLabel('New password'),
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const FieldLabel('Confirm new password'),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const _Spinner()
                      : const Text('Update password'),
                ),
              ],
            ),
    );
  }
}

// ─── Gym Details sheet ────────────────────────────────────────────────────────
class _GymDetailsSheet extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  const _GymDetailsSheet({required this.onSaved});

  @override
  ConsumerState<_GymDetailsSheet> createState() => _GymDetailsSheetState();
}

class _GymDetailsSheetState extends ConsumerState<_GymDetailsSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _descCtrl;
  Map<String, dynamic> _settings = {};
  bool _loading     = false;
  String? _error;
  bool _initialized = false;
  String _currencyCode = 'INR';

  // ponytail: fixed shortlist; add codes here if a gym asks for one we missed
  static const _currencies = [
    'INR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'QAR', 'KWD', 'OMR', 'BHD',
    'AUD', 'CAD', 'NZD', 'SGD', 'MYR', 'PHP', 'IDR', 'THB', 'VND',
    'BDT', 'LKR', 'NPR', 'PKR', 'ZAR', 'NGN', 'KES', 'EGP', 'TRY',
    'MXN', 'BRL',
  ];
  File? _logoFile;
  String? _logoUrl;
  bool _pickingLogo = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl    = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl   = TextEditingController();
    _websiteCtrl = TextEditingController();
    _descCtrl    = TextEditingController();
  }

  // Address/phone/website/description live inside the gyms.settings JSONB
  // (same as the web app), not as top-level columns.
  void _seed(Map<String, dynamic> gym) {
    _settings = Map<String, dynamic>.from(gym['settings'] as Map? ?? {});
    _nameCtrl.text    = gym['name'] as String? ?? '';
    _addressCtrl.text = _settings['address'] as String? ?? '';
    _phoneCtrl.text   = _settings['phone'] as String? ?? '';
    _websiteCtrl.text = _settings['website'] as String? ?? '';
    _descCtrl.text    = _settings['description'] as String? ?? '';
    _logoUrl          = _settings['logo_url'] as String?;
    _currencyCode     = _settings['currency'] as String? ?? 'INR';
    _initialized = true;
  }

  Future<void> _pickLogo() async {
    if (_pickingLogo) return;
    setState(() => _pickingLogo = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        setState(() => _logoFile = File(picked.path));
      }
    } on PlatformException catch (e) {
      if (mounted && e.code != 'already_active') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gallery: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  Future<String?> _uploadLogo(String gymId) async {
    if (_logoFile == null) return null;
    final ext = _logoFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final path = '$gymId/logo.$ext';
    final bytes = await _logoFile!.readAsBytes();
    await Supabase.instance.client.storage
        .from('gym-logos')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true));
    final publicUrl = Supabase.instance.client.storage
        .from('gym-logos')
        .getPublicUrl(path);
    // Bust cache by appending a timestamp query param
    return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(String gymId) async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Gym name is required');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final uploadedLogoUrl = await _uploadLogo(gymId);
      final settings = {
        ..._settings,
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'currency': _currencyCode,
        if (uploadedLogoUrl != null) 'logo_url': uploadedLogoUrl,
      };
      await Supabase.instance.client.from('gyms').update({
        'name': _nameCtrl.text.trim(),
        'settings': settings,
      }).eq('id', gymId);
      setCurrency(_currencyCode);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = 'Failed: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(_gymProvider);
    return _SheetScaffold(
      title: 'Gym details',
      child: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (gym) {
          if (gym == null) return const Text('Gym not found');
          if (!_initialized) _seed(gym);
          final hasLogo = _logoFile != null || (_logoUrl != null && _logoUrl!.isNotEmpty);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) _ErrorBox(message: _error!),
              // ── Logo picker ──────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 84, height: 84,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppTheme.inkHint, width: 1.2),
                        image: _logoFile != null
                            ? DecorationImage(image: FileImage(_logoFile!), fit: BoxFit.cover)
                            : (hasLogo ? DecorationImage(image: NetworkImage(_logoUrl!), fit: BoxFit.cover) : null),
                      ),
                      child: hasLogo ? null : const Icon(Icons.photo_camera_outlined, size: 30, color: AppTheme.inkHint),
                    ),
                    const SizedBox(height: 8),
                    const Text('Upload logo',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              const FieldLabel('Gym name'),
              TextFormField(controller: _nameCtrl),
              const SizedBox(height: 14),
              const FieldLabel('Address (optional)'),
              TextFormField(controller: _addressCtrl),
              const SizedBox(height: 14),
              const FieldLabel('Phone (optional)'),
              TextFormField(controller: _phoneCtrl, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              const FieldLabel('Website URL (optional)'),
              TextFormField(controller: _websiteCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://')),
              const SizedBox(height: 14),
              const FieldLabel('Description (optional)'),
              TextFormField(controller: _descCtrl, maxLines: 2),
              const SizedBox(height: 14),
              const FieldLabel('Currency'),
              DropdownButtonFormField<String>(
                initialValue: _currencies.contains(_currencyCode) ? _currencyCode : 'INR',
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(
                      value: c,
                      child: Text('$c (${NumberFormat.simpleCurrency(name: c).currencySymbol})'),
                    ),
                ],
                onChanged: (v) => setState(() => _currencyCode = v ?? 'INR'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: AppTheme.cardDecoration(),
                child: Column(children: [
                  _ReadOnlyRow(label: 'Slug', value: gym['slug'] as String? ?? '—'),
                  const Divider(height: 1),
                  _ReadOnlyRow(label: 'Plan', value: (() {
                    final p = gym['plan'] as String? ?? 'starter';
                    return p[0].toUpperCase() + p.substring(1);
                  })()),
                ]),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed:
                    _loading ? null : () => _save(gym['id'] as String),
                child: _loading
                    ? const _Spinner()
                    : const Text('Save details'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Payments (Razorpay) sheet ────────────────────────────────────────────────
// Connect/disconnect a Razorpay key (saved to gyms.razorpay_key_id/secret),
// matching the web Settings → Payments tab.
class _PaymentsSheet extends ConsumerStatefulWidget {
  const _PaymentsSheet();

  @override
  ConsumerState<_PaymentsSheet> createState() => _PaymentsSheetState();
}

class _PaymentsSheetState extends ConsumerState<_PaymentsSheet> {
  final _keyIdCtrl = TextEditingController();
  final _keySecretCtrl = TextEditingController();
  String? _gymId;
  bool _connected = false;
  bool _showSecret = false;
  bool _saving = false;
  bool _seeded = false;
  String? _error;

  void _seed(Map<String, dynamic> gym) {
    if (_seeded) return;
    _seeded = true;
    _gymId = gym['id'] as String?;
    _connected = (gym['razorpay_key_id'] as String?)?.isNotEmpty ?? false;
    _keyIdCtrl.text = gym['razorpay_key_id'] as String? ?? '';
  }

  @override
  void dispose() {
    _keyIdCtrl.dispose();
    _keySecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_gymId == null) return;
    if (_keyIdCtrl.text.trim().isEmpty || _keySecretCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Both Key ID and Key Secret are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Key secret is written server-side via a SECURITY DEFINER RPC so it is
      // never exposed through the client-accessible gyms table.
      await Supabase.instance.client.rpc('save_razorpay_keys', params: {
        'p_key_id': _keyIdCtrl.text.trim(),
        'p_key_secret': _keySecretCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Razorpay connected')),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] Razorpay connect error: $e');
      setState(() {
        _error = 'Failed to connect Razorpay. Please try again.';
        _saving = false;
      });
    }
  }

  Future<void> _disconnect() async {
    if (_gymId == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('save_razorpay_keys', params: {
        'p_key_id': null,
        'p_key_secret': null,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Razorpay disconnected')),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] Razorpay disconnect error: $e');
      setState(() {
        _error = 'Failed to disconnect Razorpay. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(_gymProvider);
    return _SheetScaffold(
      title: 'Payments',
      child: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (gym) {
          if (gym == null) return const Text('Gym not found');
          _seed(gym);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) _ErrorBox(message: _error!),
              const Text(
                'Connect Razorpay to collect UPI & card payments',
                style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 14),
              if (_connected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: AppTheme.statusActive, borderRadius: BorderRadius.circular(9)),
                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Connected', style: TextStyle(color: AppTheme.statusActive, fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ]),
                ),
              const FieldLabel('Key ID'),
              TextFormField(controller: _keyIdCtrl, decoration: const InputDecoration(hintText: 'rzp_live_…')),
              const SizedBox(height: 14),
              const FieldLabel('Key secret'),
              TextFormField(
                controller: _keySecretCtrl,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  hintText: _connected ? 'Enter to update' : null,
                  suffixIcon: IconButton(
                    icon: Icon(_showSecret
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _connect,
                child: _saving
                    ? const _Spinner()
                    : Text(_connected ? 'Update keys' : 'Connect Razorpay'),
              ),
              if (_connected) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _disconnect,
                    child: const Text('Disconnect account', style: TextStyle(color: AppTheme.statusDanger)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Support ticket sheet ───────────────────────────────────────────────────
const _ticketTypes = [
  ('bug', 'Bug report'),
  ('feature_request', 'Feature request'),
  ('support', 'General help'),
];

class _SupportTicketSheet extends ConsumerStatefulWidget {
  const _SupportTicketSheet();

  @override
  ConsumerState<_SupportTicketSheet> createState() => _SupportTicketSheetState();
}

class _SupportTicketSheetState extends ConsumerState<_SupportTicketSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'support';
  bool _loading = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please describe your issue in a few words.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final email = Supabase.instance.client.auth.currentUser?.email;
      await Supabase.instance.client.from('support_tickets').insert({
        'gym_id': gymId,
        'reporter_email': email,
        'type': _type,
        'title': title,
        'description': _descCtrl.text.trim(),
      });
      ref.invalidate(_myTicketsProvider);
      if (mounted) setState(() { _submitted = true; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not submit — please try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Help & Support',
      child: _submitted
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.accent, size: 40),
                  const SizedBox(height: 12),
                  const Text('Ticket submitted',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.ink)),
                  const SizedBox(height: 6),
                  Text('We\'ll get back to you at ${Supabase.instance.client.auth.currentUser?.email ?? 'your email'}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => showAdaptiveSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const _MyTicketsSheet(),
                    ),
                    child: const Text('View past tickets'),
                  ),
                ),
                if (_error != null) _ErrorBox(message: _error!),
                const FieldLabel('What\'s this about?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ticketTypes.map((t) {
                    return PillChip(
                      label: t.$2,
                      selected: _type == t.$1,
                      onTap: () => setState(() => _type = t.$1),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Title'),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(hintText: 'Short summary of the issue'),
                ),
                const SizedBox(height: 14),
                const FieldLabel('Details (optional)'),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Anything that helps us understand it'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading ? const _Spinner() : const Text('Submit ticket'),
                ),
              ],
            ),
    );
  }
}

final _myTicketsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final rows = await Supabase.instance.client
      .from('support_tickets')
      .select('id, type, title, description, status, created_at')
      .eq('gym_id', gymId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

StatusPill _ticketStatusPill(String status) {
  switch (status) {
    case 'in_progress':
      return StatusPill.warn(label: 'In progress');
    case 'fixed':
      return StatusPill.active(label: 'Fixed');
    case 'closed':
      return StatusPill.neutral(label: 'Closed');
    default:
      return StatusPill.neutral(label: 'New');
  }
}

class _MyTicketsSheet extends ConsumerWidget {
  const _MyTicketsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(_myTicketsProvider);
    return _SheetScaffold(
      title: 'My tickets',
      child: tickets.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Could not load tickets: $e'),
        data: (rows) {
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No tickets yet', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows.map((t) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t['title'] as String? ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                        ),
                        _ticketStatusPill(t['status'] as String? ?? 'new'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(formatDateFromString(t['created_at'] as String?),
                        style: const TextStyle(fontSize: 12, color: AppTheme.inkHint)),
                    if ((t['description'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(t['description'] as String,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ─── Registration Link sheet ──────────────────────────────────────────────────
// Full parity with the web RegistrationLinkBanner: enable/disable toggle,
// regenerate token, copy and share the link, plus a QR code for in-person sharing.
class _RegistrationLinkSheet extends ConsumerStatefulWidget {
  const _RegistrationLinkSheet();

  @override
  ConsumerState<_RegistrationLinkSheet> createState() => _RegistrationLinkSheetState();
}

class _RegistrationLinkSheetState extends ConsumerState<_RegistrationLinkSheet> {
  String? _gymId;
  bool _enabled = false;
  String _token = '';
  String? _expiresAt;
  bool _toggling = false;
  bool _regenerating = false;
  bool _seeded = false;

  void _seed(Map<String, dynamic> gym) {
    if (_seeded) return;
    _seeded = true;
    _gymId = gym['id'] as String?;
    _enabled = gym['registration_enabled'] as bool? ?? false;
    _token = gym['registration_token'] as String? ?? '';
    _expiresAt = gym['registration_token_expires_at'] as String?;
  }

  String _formatExpiry() {
    if (_expiresAt == null) return '';
    final expiry = DateTime.tryParse(_expiresAt!);
    if (expiry == null) return '';
    final diff = expiry.toUtc().difference(DateTime.now().toUtc());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours >= 24) return 'Expires in ${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'Expires in ${diff.inMinutes}m';
  }

  String get _link => _token.isEmpty ? '' : '$_registrationBaseUrl/register/$_token';

  Future<void> _toggle() async {
    if (_gymId == null) return;
    setState(() => _toggling = true);
    try {
      await Supabase.instance.client
          .from('gyms')
          .update({'registration_enabled': !_enabled}).eq('id', _gymId!);
      if (mounted) setState(() => _enabled = !_enabled);
      _toast(_enabled ? 'Registration link enabled' : 'Registration link disabled');
    } catch (e) {
      debugPrint('[GymCRM] Toggle registration error: $e');
      _toast('Failed to update setting');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _regenerate() async {
    if (_gymId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Regenerate link?',
      body: 'The old link will stop working immediately.',
      confirmLabel: 'Regenerate',
      icon: Icons.refresh,
      danger: false,
    );
    if (ok != true) return;
    setState(() => _regenerating = true);
    try {
      final next = _uuidV4();
      final nextExpiry = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
      await Supabase.instance.client.from('gyms').update({
        'registration_token': next,
        'registration_token_expires_at': nextExpiry,
      }).eq('id', _gymId!);
      if (mounted) setState(() { _token = next; _expiresAt = nextExpiry; });
      _toast('New registration link generated');
    } catch (e) {
      debugPrint('[GymCRM] Regenerate link error: $e');
      _toast('Failed to regenerate link');
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(_gymProvider);
    return _SheetScaffold(
      title: 'Self-registration link',
      child: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (gym) {
          if (gym == null) return const Text('Gym not found');
          _seed(gym);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text('Share so new members can sign up themselves',
                    style: TextStyle(fontSize: 13.5, color: AppTheme.inkSoft)),
                ),
                Switch(
                  value: _enabled,
                  activeThumbColor: AppTheme.accent,
                  onChanged: _toggling ? null : (_) => _toggle(),
                ),
              ]),

              if (_enabled && _link.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppTheme.cardDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_link,
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, fontFamily: 'monospace')),
                      ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _link));
                          _toast('Link copied to clipboard');
                        },
                        child: const Text('Copy',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatExpiry().isNotEmpty
                      ? '${_formatExpiry()} · Regenerate anytime'
                      : 'Regenerate anytime',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                ),
                const SizedBox(height: 16),
                // QR code for in-person sharing
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(
                      data: _link,
                      version: QrVersions.auto,
                      size: 160,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    Share.share(
                      _link,
                      subject: 'Join our gym',
                      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
                    );
                  },
                  child: const Text('Share link'),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _regenerating ? null : _regenerate,
                    icon: _regenerating
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 16),
                    label: const Text('Regenerate link'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'Enable self-registration to get a shareable link and QR code for new members.',
                  style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Biometric Device sheet ───────────────────────────────────────────────────
class BiometricDeviceSheet extends ConsumerStatefulWidget {
  const BiometricDeviceSheet({super.key});

  @override
  ConsumerState<BiometricDeviceSheet> createState() => BiometricDeviceSheetState();
}

class BiometricDeviceSheetState extends ConsumerState<BiometricDeviceSheet> {
  Map<String, dynamic>? _device;
  bool _loading = true;
  String? _error;
  bool _initialized = false;
  String? _gymId;

  final _snCtrl = TextEditingController();
  bool _pairing = false;
  String? _pairError;

  @override
  void dispose() {
    _snCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String gymId) async {
    try {
      final data = await Supabase.instance.client
          .from('biometric_devices')
          .select()
          .eq('gym_id', gymId)
          .maybeSingle();

      if (mounted) setState(() { _device = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _pairDevice() async {
    // Uppercase so a case mismatch between what staff types and what the
    // device actually sends in its SN parameter can never break the match.
    final sn = _snCtrl.text.trim().toUpperCase();
    if (sn.isEmpty || _gymId == null) return;

    setState(() { _pairing = true; _pairError = null; });

    try {
      final data = await Supabase.instance.client
          .from('biometric_devices')
          .upsert({'gym_id': _gymId, 'device_sn': sn}, onConflict: 'gym_id')
          .select()
          .single();
      if (mounted) {
        setState(() { _device = data; _pairing = false; });
        _snCtrl.clear();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _pairing = false;
          _pairError = e.code == '23505'
              ? 'This device is already paired to another gym. Double-check the serial number.'
              : 'Could not pair device: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _pairing = false; _pairError = '$e'; });
    }
  }

  String get _lastPing {
    final raw = _device?['last_ping_at'] as String?;
    if (raw == null) return 'Never connected';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return 'Unknown';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      ref.watch(_gymProvider).whenData((gym) {
        if (gym != null) {
          _initialized = true;
          _gymId = gym['id'] as String;
          Future.microtask(() { if (mounted) _load(_gymId!); });
        }
      });
    }
    return _SheetScaffold(
      title: 'Biometric Device',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBox(message: _error!)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Beta disclaimer ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.statusWarnBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.info_outline, color: AppTheme.statusWarn, size: 16),
                            SizedBox(width: 6),
                            Text('Beta Feature', style: TextStyle(color: AppTheme.statusWarn, fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                          SizedBox(height: 6),
                          Text(
                            'Designed for ZKTeco & eSSL devices (F22, K40, E9, E990). '
                            'Other models may work but are untested. '
                            'If your device behaves differently, contact support.',
                            style: TextStyle(color: AppTheme.statusWarn, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Before you begin ─────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.cardDecoration(),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppTheme.inkHint),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You will need a LAN cable (or WiFi for MB-series devices), '
                              'a router, and a phone or laptop on the same network.',
                              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text('Steps', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                    const SizedBox(height: 10),

                    const _SetupStep(number: 1, text: 'Connect the device to your router — plug a LAN cable into the device '
                        'and a free port on the router. For MB-series WiFi models, connect via the device\'s WiFi settings instead.'),
                    const _SetupStep(number: 2, text: 'Find your router\'s Gateway IP — '
                        'Android: Settings → WiFi → tap the ⓘ icon next to your network → look for "Gateway". '
                        'iPhone: Settings → WiFi → tap the ⓘ icon → look for "Router". '
                        'Usually looks like 192.168.1.1 or 192.168.0.1.'),
                    const _SetupStep(number: 3, text: 'On the device, go to Menu → Comm → Ethernet and set: DHCP OFF, '
                        'Gateway = the IP from step 2, IP Address = same network with a unique last number (e.g. 192.168.1.201), '
                        'Subnet Mask = 255.255.255.0, DNS = 8.8.8.8.'),
                    _SetupStep(number: 4, text: 'On the device, go to Menu → Comm → Cloud Server and set: '
                        'Server Mode = ADMS, Server Address = $_biometricBridgeHost, Port = $_biometricBridgePort, HTTPS = OFF.'),
                    const _SetupStep(number: 5, text: 'Restart the device.'),

                    const SizedBox(height: 12),
                    _CopyField(label: 'Server Address', value: _biometricBridgeHost),
                    const SizedBox(height: 12),
                    _CopyField(label: 'Port', value: _biometricBridgePort),

                    const SizedBox(height: 20),

                    // ── Connect a Device ──────────────────────────────────────
                    const Text('Connect a Device', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink)),
                    const SizedBox(height: 6),
                    const Text(
                      'Enter the serial number printed on the back of the device to pair it with this gym.',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _snCtrl,
                            decoration: const InputDecoration(hintText: 'e.g. AAKL251200123'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _pairing ? null : _pairDevice,
                          child: _pairing
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Pair'),
                        ),
                      ],
                    ),
                    if (_pairError != null) ...[
                      const SizedBox(height: 8),
                      Text(_pairError!, style: const TextStyle(fontSize: 12, color: AppTheme.statusDanger)),
                    ],

                    const SizedBox(height: 16),

                    // ── Device status ────────────────────────────────────────
                    if (_device?['device_sn'] != null)
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (_device?['last_ping_at'] != null)
                                  ? AppTheme.statusActive
                                  : AppTheme.inkHint,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Paired: ${_device!['device_sn']} · Last seen: $_lastPing',
                            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                          ),
                        ],
                      ),

                    const SizedBox(height: 20),

                    // ── Supported devices ─────────────────────────────────────
                    const Text('Supported Devices', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
                    const SizedBox(height: 4),
                    const Text(
                      'Any eSSL/ZKTeco device that supports the ADMS (push data) protocol. '
                      'Not individually tested against real hardware yet — if your device behaves differently, contact support.',
                      style: TextStyle(fontSize: 11, color: AppTheme.inkHint),
                    ),
                    const SizedBox(height: 10),
                    const Text('Fingerprint devices', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
                    const SizedBox(height: 6),
                    const Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        _DeviceChip('ZKTeco F22'),
                        _DeviceChip('ZKTeco K40 Pro'),
                        _DeviceChip('eSSL K90 Pro'),
                        _DeviceChip('eSSL X990 / iClock990'),
                        _DeviceChip('eSSL K30 / K40'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('Multi-biometric (fingerprint + face)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
                    const SizedBox(height: 6),
                    const Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        _DeviceChip('ZKTeco SpeedFace'),
                        _DeviceChip('eSSL MB20 / MB160 / MB460'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Member linking note ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: AppTheme.cardDecoration(),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppTheme.inkHint),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'After enrolling a member\'s finger on the device, open their profile '
                              '(Members → tap member → Edit) and set their Biometric Device ID '
                              'to match the employee number on the machine.',
                              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Need help ─────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _launchExternal('https://gymcrm.in/docs/biometric-attendance'),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text('View full setup guide'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _launchExternal('https://wa.me/917541004076?text=${Uri.encodeComponent("Hi, I'm having trouble setting up my biometric device on GymCRM.")}'),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('Contact us on WhatsApp'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _launchExternal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _CopyField extends StatelessWidget {
  final String label;
  final String value;
  const _CopyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: AppTheme.cardDecoration(),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppTheme.inkSoft),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied')),
                  );
                },
                child: const Text('Copy',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accent)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetupStep extends StatelessWidget {
  final int number;
  final String text;
  const _SetupStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(color: AppTheme.activeBg, shape: BoxShape.circle),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.ink),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String label;
  const _DeviceChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.activeBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────
class _SheetScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(title: title),
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.statusDangerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.statusDanger, fontSize: 13),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.ink)),
      ]),
    );
  }
}
