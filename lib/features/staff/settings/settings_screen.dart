import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

/// Public base URL for member self-registration links (matches the web app).
const _registrationBaseUrl = 'https://gymcrm.in';

// Supabase project URL — hardcoded to match main.dart (required for Shorebird patch compatibility).
const _supabaseProjectUrl = 'https://orlqjhqxeyukvfzsursl.supabase.co';

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
      body: SingleChildScrollView(
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
                onTap: () => showModalBottomSheet(
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
                onTap: () => showModalBottomSheet(
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
                onTap: () => showModalBottomSheet(
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
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _RegistrationLinkSheet(),
                ),
              ),
              _SettingsRow(
                icon: Icons.payments_outlined,
                label: 'Payments (Razorpay)',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _PaymentsSheet(),
                ),
              ),
              // BIOMETRIC HIDDEN — re-enable when ready to launch
              // _SettingsRow(
              //   icon: Icons.fingerprint,
              //   label: 'Biometric Device',
              //   onTap: () => showModalBottomSheet(
              //     context: context,
              //     isScrollControlled: true,
              //     useSafeArea: true,
              //     builder: (_) => const _BiometricDeviceSheet(),
              //   ),
              // ),
            ]),

            const SizedBox(height: 20),

            // ── APP section ──────────────────────────────────────────────────
            _SectionLabel(label: 'APP'),
            _SettingsCard(items: [
              // SMS reminders send via the device's SMS (Android-only). iOS
              // can't send SMS silently, so the row is hidden there.
              if (!Platform.isIOS)
                _SettingsRow(
                  icon: Icons.sms_outlined,
                  label: 'SMS Reminders',
                  onTap: () => context.push('/staff/reminders'),
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

            const SizedBox(height: 40),
          ],
        ),
      ),
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

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.activeBg,
            child: Text(
              '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
                  .toUpperCase(),
              style: const TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName'.trim(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role[0].toUpperCase() + role.substring(1),
                  style: const TextStyle(
                    color: AppTheme.inkSoft,
                    fontSize: 13,
                  ),
                ),
                if (gym != null)
                  Text(
                    gym['name'] as String? ?? '',
                    style: const TextStyle(
                      color: AppTheme.inkSoft,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
      title: 'Edit Profile',
      child: Column(
        children: [
          if (_error != null) _ErrorBox(message: _error!),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstCtrl,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lastCtrl,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            child: _loading ? const _Spinner() : const Text('Save Changes'),
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
      title: 'Change Password',
      child: _done
          ? Column(
              children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.statusActive, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Password updated successfully!',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                TextFormField(
                  controller: _newCtrl,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
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
                      : const Text('Update Password'),
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
  File? _logoFile;
  String? _logoUrl;

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
    _initialized = true;
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 90,
    );
    if (picked != null && mounted) {
      setState(() => _logoFile = File(picked.path));
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
        if (uploadedLogoUrl != null) 'logo_url': uploadedLogoUrl,
      };
      await Supabase.instance.client.from('gyms').update({
        'name': _nameCtrl.text.trim(),
        'settings': settings,
      }).eq('id', gymId);
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
      title: 'Gym Details',
      child: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (gym) {
          if (gym == null) return const Text('Gym not found');
          if (!_initialized) _seed(gym);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) _ErrorBox(message: _error!),
              // ── Logo picker ──────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                          image: _logoFile != null
                              ? DecorationImage(
                                  image: FileImage(_logoFile!),
                                  fit: BoxFit.cover,
                                )
                              : (_logoUrl != null && _logoUrl!.isNotEmpty)
                                  ? DecorationImage(
                                      image: NetworkImage(_logoUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: (_logoFile == null &&
                                (_logoUrl == null || _logoUrl!.isEmpty))
                            ? const Icon(Icons.upload_file_outlined,
                                size: 32, color: AppTheme.inkHint)
                            : null,
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_outlined, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text('Gym Logo',
                    style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Gym name *'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration:
                    const InputDecoration(labelText: 'Address (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _websiteCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Website URL (optional)',
                  hintText: 'https://',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Description (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                readOnly: true,
                initialValue: gym['slug'] as String? ?? '',
                decoration: const InputDecoration(labelText: 'Slug (read-only)'),
                style: const TextStyle(color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 12),
              TextFormField(
                readOnly: true,
                initialValue: (() {
                  final p = gym['plan'] as String? ?? 'starter';
                  return p[0].toUpperCase() + p.substring(1);
                })(),
                decoration:
                    const InputDecoration(labelText: 'Plan (read-only)'),
                style: const TextStyle(color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed:
                    _loading ? null : () => _save(gym['id'] as String),
                child: _loading
                    ? const _Spinner()
                    : const Text('Save Changes'),
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
      title: 'Payments — Razorpay',
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
              if (_connected)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.statusActiveBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.statusActive),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.statusActive, size: 16),
                      SizedBox(width: 8),
                      Text('Razorpay is connected',
                          style: TextStyle(
                              color: AppTheme.statusActive,
                              fontWeight: FontWeight.w500,
                              fontSize: 13)),
                    ],
                  ),
                ),
              const Text(
                'Connect your Razorpay account so members can pay online from the portal.',
                style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _keyIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Key ID',
                  hintText: 'rzp_live_…',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keySecretCtrl,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  labelText: 'Key Secret',
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
                    : Text(_connected ? 'Update Keys' : 'Connect Razorpay'),
              ),
              if (_connected) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _saving ? null : _disconnect,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusDanger,
                    side: const BorderSide(color: AppTheme.statusDanger),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Disconnect'),
                ),
              ],
            ],
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Regenerate link?'),
        content: const Text('The old link will stop working immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Regenerate')),
        ],
      ),
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
      title: 'Member Registration Link',
      child: gymAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Error: $e'),
        data: (gym) {
          if (gym == null) return const Text('Gym not found');
          _seed(gym);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status + toggle
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _enabled ? AppTheme.statusActiveBg : AppTheme.statusWarnBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _enabled ? AppTheme.statusActive : AppTheme.statusWarn),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _enabled ? Icons.check_circle : Icons.warning_amber_outlined,
                            color: _enabled ? AppTheme.statusActive : AppTheme.statusWarn,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _enabled ? 'Registration is enabled' : 'Registration is disabled',
                              style: TextStyle(
                                color: _enabled ? AppTheme.statusActive : AppTheme.statusWarn,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Switch(
                    value: _enabled,
                    onChanged: _toggling ? null : (_) => _toggle(),
                  ),
                ],
              ),

              if (_enabled && _link.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Shareable Link',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    if (_formatExpiry().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _formatExpiry() == 'Expired'
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatExpiry(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _formatExpiry() == 'Expired'
                                ? const Color(0xFFC62828)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_link,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.inkSoft, fontFamily: 'monospace')),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copy link',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _link));
                          _toast('Link copied to clipboard');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Share.share(_link, subject: 'Join our gym'),
                        icon: const Icon(Icons.share_outlined, size: 16),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _regenerating ? null : _regenerate,
                        icon: _regenerating
                            ? const SizedBox(
                                height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 16),
                        label: const Text('Regenerate'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // QR code for in-person sharing
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: QrImageView(
                      data: _link,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Members can scan this to register',
                      style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
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
class _BiometricDeviceSheet extends ConsumerStatefulWidget {
  const _BiometricDeviceSheet();

  @override
  ConsumerState<_BiometricDeviceSheet> createState() => _BiometricDeviceSheetState();
}

class _BiometricDeviceSheetState extends ConsumerState<_BiometricDeviceSheet> {
  Map<String, dynamic>? _device;
  bool _loading = true;
  String? _error;
  bool _initialized = false;

  Future<void> _loadOrCreate(String gymId) async {
    try {
      var data = await Supabase.instance.client
          .from('biometric_devices')
          .select()
          .eq('gym_id', gymId)
          .maybeSingle();

      if (data == null) {
        final res = await Supabase.instance.client
            .from('biometric_devices')
            .insert({'gym_id': gymId})
            .select()
            .single();
        data = res;
      }

      if (mounted) setState(() { _device = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  String get _admsUrl {
    final token = _device?['token'] as String? ?? '';
    return '$_supabaseProjectUrl/functions/v1/biometric-adms/$token';
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
          Future.microtask(() { if (mounted) _loadOrCreate(gym['id'] as String); });
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1c1200),
                        border: Border.all(color: AppTheme.statusWarn),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.warning_amber_outlined, color: AppTheme.statusWarn, size: 16),
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

                    // ── Device status ────────────────────────────────────────
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
                          'Last seen: $_lastPing',
                          style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                        ),
                        if (_device?['device_sn'] != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· SN: ${_device!['device_sn']}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── ADMS URL ─────────────────────────────────────────────
                    const Text(
                      'Server URL',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.inkSoft),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _admsUrl,
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.inkSoft),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Copy',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _admsUrl));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Server URL copied')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Setup steps ──────────────────────────────────────────
                    const Text(
                      'How to Configure Your Device',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    ),
                    const SizedBox(height: 10),
                    ..._steps.map((s) => _SetupStep(number: s.$1, text: s.$2)),

                    const SizedBox(height: 16),

                    // ── Compatible devices ───────────────────────────────────
                    const Text(
                      'Compatible Devices',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.inkSoft),
                    ),
                    const SizedBox(height: 6),
                    const Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        _DeviceChip('ZKTeco F22'),
                        _DeviceChip('ZKTeco K40 Pro'),
                        _DeviceChip('ZKTeco SpeedFace'),
                        _DeviceChip('eSSL E9'),
                        _DeviceChip('eSSL E990'),
                        _DeviceChip('eSSL MB160'),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Member linking note ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
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
                  ],
                ),
    );
  }
}

const _steps = [
  (1, 'On the device, go to Menu → Communication → Cloud / ADMS Settings'),
  (2, 'Set Server Address to: your Supabase project domain (e.g. orlqjhqx...supabase.co)'),
  (3, 'Set Port to 443 and enable HTTPS'),
  (4, 'Set Server Path / Device Path to the path portion of the URL above (starting with /functions/...)'),
  (5, 'Save and restart the device — status will show "Last seen: Just now" when connected'),
  (6, 'Enroll each member\'s fingerprint and note the employee number assigned'),
  (7, 'Open each member\'s profile in GymCRM and enter that employee number as "Biometric Device ID"'),
];

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
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.statusDangerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.statusDanger.withOpacity(0.3)),
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
