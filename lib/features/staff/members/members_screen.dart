import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/access/role_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/member_photo.dart';
import 'import_csv_screen.dart';
import '../reminders/sms_reminder_service.dart';

final _membersProvider = FutureProvider.family<List<Member>, String>((ref, filter) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  var query = client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('gym_id', gymId);

  if (filter.isNotEmpty && filter != 'all') {
    query = query.eq('status', filter);
  }

  final data = await query.order('created_at', ascending: false);
  return (data as List).map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
});

// Active membership plans for the current gym — used to assign a plan when
// creating a member (matches the web add-member form).
final _memberPlansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  final data = await client
      .from('membership_plans')
      .select('id, name, price, billing_interval, billing_interval_months')
      .eq('gym_id', gymId)
      .eq('is_active', true)
      .order('price');
  return (data as List).cast<Map<String, dynamic>>();
});

String _planLabel(Map<String, dynamic> p) {
  final price = (p['price'] as num?)?.toStringAsFixed(0) ?? '0';
  final interval = p['billing_interval'] as String? ?? '';
  const short = {'monthly': 'mo', 'quarterly': 'qtr', 'biannual': '6mo', 'annual': 'yr'};
  final unit = interval == 'custom'
      ? '${p['billing_interval_months'] ?? ''}mo'
      : (short[interval] ?? interval);
  return '${p['name']} — ₹$price/$unit';
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _filter = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersProvider(_filter));
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canPii = RoleAccess.canSeeMemberPii(role);
    final canEdit = RoleAccess.canEditMembers(role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.payment_outlined),
            tooltip: 'Upcoming Payments',
            onPressed: () => context.push('/staff/upcoming-payments'),
          ),
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import CSV',
              onPressed: () => _openImportCsv(context),
            ),
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () => _showAddMemberSheet(context),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilter(),
          Expanded(
            child: members.when(
              loading: () => _MembersShimmer(),
              error: (e, _) => const Center(child: Text('Could not load members. Pull to retry.', style: TextStyle(color: Color(0xFF666666)))),
              data: (list) {
                final filtered = _search.isEmpty
                    ? list
                    : list.where((m) =>
                        m.fullName.toLowerCase().contains(_search.toLowerCase()) ||
                        (canPii && m.email.toLowerCase().contains(_search.toLowerCase()))).toList();

                if (filtered.isEmpty) return const _EmptyMembers();

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_membersProvider(_filter)),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _MemberCard(member: filtered[i], canPii: canPii),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search members...',
              prefixIcon: const Icon(Icons.search, color: AppTheme.inkHint, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppTheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.ink, width: 1.5),
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 10),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'active', 'frozen', 'expired', 'cancelled'].map((f) {
                final selected = _filter == f;
                final label = f == 'all' ? 'All' : f[0].toUpperCase() + f.substring(1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.ink : AppTheme.activeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.white : AppTheme.inkSoft,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddMemberSheet(),
    ).then((_) => ref.invalidate(_membersProvider(_filter)));
  }

  void _openImportCsv(BuildContext context) {
    Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ImportCsvScreen()))
        .then((imported) {
      if (imported == true) ref.invalidate(_membersProvider(_filter));
    });
  }
}

// ── Member Card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final Member member;
  final bool canPii;
  const _MemberCard({required this.member, required this.canPii});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => context.push('/staff/members/${member.id}'),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F0F0),
                    shape: BoxShape.circle,
                  ),
                  child: MemberPhoto(
                    stored: member.avatarUrl,
                    fallback: Center(
                      child: Text(
                        initials(member.firstName, member.lastName),
                        style: const TextStyle(
                          color: Color(0xFF111111),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.ink,
                        ),
                      ),
                      if (canPii) ...[
                        const SizedBox(height: 2),
                        Text(
                          member.email,
                          style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13),
                        ),
                      ],
                      if (member.currentMembership?.plan != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          member.currentMembership!.plan!.name,
                          style: const TextStyle(
                            color: AppTheme.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (member.nextPaymentDate != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.payment_outlined, size: 11, color: AppTheme.inkHint),
                            const SizedBox(width: 3),
                            Text(
                              'Due ${formatDateFromString(member.nextPaymentDate)}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.inkHint),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: member.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  static (Color, Color) _statusColors(String status) => switch (status) {
        'active'    => (AppTheme.statusActiveBg, AppTheme.statusActive),
        'frozen'    => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
        'expired'   => (AppTheme.statusWarnBg, AppTheme.statusWarn),
        'cancelled' => (AppTheme.statusDangerBg, AppTheme.statusDanger),
        _           => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
      };
}

// ── Shimmer Skeleton ──────────────────────────────────────────────────────────

class _MembersShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 8,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8E8E8),
        highlightColor: const Color(0xFFF5F5F5),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 78,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.people_outline, size: 64, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No members found',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink),
          ),
          SizedBox(height: 8),
          Text(
            'Add your first member to get started',
            style: TextStyle(color: AppTheme.inkHint, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── Add Member Sheet ──────────────────────────────────────────────────────────

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet();

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _ecNameCtrl = TextEditingController();
  final _ecPhoneCtrl = TextEditingController();
  final _ecRelCtrl = TextEditingController();

  String _status = 'active';
  String? _joinedAt;
  String? _planId;
  File? _avatarFile;
  bool _loading = false;
  bool _showEmergency = false;

  // Billing day input
  final _billingDayCtrl = TextEditingController();
  bool _billingForceNextMonth = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _ecNameCtrl.dispose();
    _ecPhoneCtrl.dispose();
    _ecRelCtrl.dispose();
    _billingDayCtrl.dispose();
    super.dispose();
  }

  String? _computeNextPaymentDate() {
    final day = int.tryParse(_billingDayCtrl.text.trim());
    if (day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    final useNext = _billingForceNextMonth || day < now.day;
    var year = now.year;
    var month = now.month + (useNext ? 1 : 0);
    if (month > 12) { month = 1; year++; }
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final actual = day <= daysInMonth ? day : daysInMonth;
    return '$year-${month.toString().padLeft(2, '0')}-${actual.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (picked != null && mounted) setState(() => _avatarFile = File(picked.path));
  }

  Future<String?> _uploadAvatar(String gymId) async {
    if (_avatarFile == null) return null;
    final ext = _avatarFile!.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final filename = '$gymId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await _avatarFile!.readAsBytes();
    await Supabase.instance.client.storage
        .from('member-photos')
        .uploadBinary(filename, bytes, fileOptions: FileOptions(contentType: mime));
    // Private bucket: store the path; display resolves a signed URL.
    return filename;
  }

  Future<void> _pickDate(bool isJoined) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final s = picked.toIso8601String().split('T')[0];
      setState(() => _joinedAt = s);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final avatarUrl = await _uploadAvatar(gymId);

      Map<String, dynamic>? ec;
      if (_ecNameCtrl.text.trim().isNotEmpty) {
        ec = {
          'name': _ecNameCtrl.text.trim(),
          if (_ecPhoneCtrl.text.trim().isNotEmpty) 'phone': _ecPhoneCtrl.text.trim(),
          if (_ecRelCtrl.text.trim().isNotEmpty) 'relationship': _ecRelCtrl.text.trim(),
        };
      }

      final inserted = await client.from('members').insert({
        'gym_id': gymId,
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'status': _status,
        if (_joinedAt != null) 'joined_at': _joinedAt,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (_computeNextPaymentDate() != null) 'next_payment_date': _computeNextPaymentDate(),
        if (ec != null) 'emergency_contact': ec,
      }).select('id').single();

      // Assign the selected membership plan (open-ended, matches the web flow).
      if (_planId != null) {
        await client.from('memberships').insert({
          'member_id': inserted['id'],
          'plan_id': _planId,
          'status': 'active',
          'starts_at': DateTime.now().toUtc().toIso8601String(),
          'ends_at': null,
        });
      }

      final phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        await SmsReminderService.sendWelcomeSms(
          name: _firstCtrl.text.trim(),
          phone: phone,
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[GymCRM] AddMember error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add member. Please try again.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Add Member',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 4),
              // Photo picker
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.border, width: 1.5),
                        ),
                        child: _avatarFile != null
                            ? ClipOval(child: Image.file(_avatarFile!, fit: BoxFit.cover))
                            : const Icon(Icons.person_outline, size: 38, color: AppTheme.inkHint),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: AppTheme.ink,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Basic Info',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkHint, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextFormField(controller: _firstCtrl, maxLength: 100, decoration: const InputDecoration(labelText: 'First name *', counterText: ''), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _lastCtrl, maxLength: 100, decoration: const InputDecoration(labelText: 'Last name *', counterText: ''), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email *', counterText: ''),
                validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _phoneCtrl, maxLength: 20, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)', counterText: '')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Joining date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                        child: Text(
                          _joinedAt != null ? formatDateFromString(_joinedAt) : 'Today',
                          style: TextStyle(color: _joinedAt != null ? AppTheme.ink : AppTheme.inkHint),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BillingDayField(
                      controller: _billingDayCtrl,
                      forceNextMonth: _billingForceNextMonth,
                      onForceNextMonthChanged: (v) => setState(() => _billingForceNextMonth = v),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Membership plan (optional) — assigns a plan on creation
              Consumer(
                builder: (context, ref, _) {
                  final plans = ref.watch(_memberPlansProvider);
                  return plans.maybeWhen(
                    data: (list) => list.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String?>(
                              value: _planId,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Membership plan (optional)'),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('No plan')),
                                ...list.map((p) => DropdownMenuItem<String?>(
                                      value: p['id'] as String,
                                      child: Text(_planLabel(p), overflow: TextOverflow.ellipsis),
                                    )),
                              ],
                              onChanged: (v) => setState(() => _planId = v),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  );
                },
              ),
              TextFormField(controller: _notesCtrl, maxLines: 2, maxLength: 500, decoration: const InputDecoration(labelText: 'Notes (optional)', counterText: '')),
              const SizedBox(height: 16),
              // Emergency contact toggle
              InkWell(
                onTap: () => setState(() => _showEmergency = !_showEmergency),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(_showEmergency ? Icons.expand_less : Icons.expand_more, color: AppTheme.ink, size: 20),
                      const SizedBox(width: 6),
                      const Text('Emergency Contact', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
                      const SizedBox(width: 6),
                      const Text('(optional)', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                    ],
                  ),
                ),
              ),
              if (_showEmergency) ...[
                const SizedBox(height: 8),
                TextFormField(controller: _ecNameCtrl, decoration: const InputDecoration(labelText: 'Contact name')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _ecPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _ecRelCtrl, decoration: const InputDecoration(labelText: 'Relationship'))),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Add Member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Billing Day Field ─────────────────────────────────────────────────────────

class _BillingDayField extends StatelessWidget {
  final TextEditingController controller;
  final bool forceNextMonth;
  final ValueChanged<bool> onForceNextMonthChanged;
  final ValueChanged<String> onChanged;

  const _BillingDayField({
    required this.controller,
    required this.forceNextMonth,
    required this.onForceNextMonthChanged,
    required this.onChanged,
  });

  String? _computedDate() {
    final day = int.tryParse(controller.text.trim());
    if (day == null || day < 1 || day > 31) return null;
    final now = DateTime.now();
    final useNext = forceNextMonth || day < now.day;
    var year = now.year;
    var month = now.month + (useNext ? 1 : 0);
    if (month > 12) { month = 1; year++; }
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final actual = day <= daysInMonth ? day : daysInMonth;
    return '$year-${month.toString().padLeft(2, '0')}-${actual.toString().padLeft(2, '0')}';
  }

  String _monthName(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[d.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = int.tryParse(controller.text.trim());
    final validDay = day != null && day >= 1 && day <= 31;
    final todayDay = DateTime.now().day;
    final dayValue = day ?? 0;
    final showToggle = validDay && dayValue > todayDay;
    final computed = _computedDate();

    // Next month label for toggle
    final now = DateTime.now();
    var nm = now.month + 1; var ny = now.year;
    if (nm > 12) { nm = 1; ny++; }
    final nextMonthLabel = _monthName(DateTime(ny, nm));
    final thisMonthLabel = _monthName(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Billing day'),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 2,
            decoration: const InputDecoration.collapsed(
              hintText: 'e.g. 15',
            ),
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, color: AppTheme.ink),
          ),
        ),
        if (controller.text.isNotEmpty && !validDay)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text('Enter a day 1–31', style: TextStyle(fontSize: 11, color: AppTheme.statusDanger)),
          ),
        if (validDay && computed != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Next due: ${formatDateFromString(computed)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
              if (showToggle) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onForceNextMonthChanged(!forceNextMonth),
                  child: Text(
                    forceNextMonth
                        ? '← Back to $thisMonthLabel'
                        : '→ Start from $nextMonthLabel',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
