import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/access/role_access.dart';
import '../../../core/services/member_photo_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/member.dart';
import '../../../shared/widgets/redesign.dart';
import 'import_csv_screen.dart';

final _membersProvider = FutureProvider<List<Member>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('members')
      .select('*, memberships(*, membership_plans(*))')
      .eq('gym_id', gymId)
      .order('created_at', ascending: false);
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

  static bool _isLapsing(Member m) {
    if (m.status != 'active') return false;
    final npd = m.nextPaymentDate;
    if (npd == null || npd.isEmpty) return false;
    final due = DateTime.tryParse(npd);
    if (due == null) return false;
    final days = due.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }

  List<Member> _applyFilter(List<Member> list) => switch (_filter) {
    'all'     => list,
    'lapsing' => list.where(_isLapsing).toList(),
    _         => list.where((m) => m.status == _filter).toList(),
  };

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersProvider);
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canPii = RoleAccess.canSeeMemberPii(role);
    final canEdit = RoleAccess.canEditMembers(role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(canEdit),
            _buildSearchAndFilter(members.valueOrNull ?? const []),
            Expanded(
              child: members.when(
                loading: () => _MembersShimmer(),
                error: (e, _) => const Center(child: Text('Could not load members. Pull to retry.', style: TextStyle(color: AppTheme.inkSoft))),
                data: (list) {
                  var filtered = _applyFilter(list);
                  if (_search.isNotEmpty) {
                    final q = _search.toLowerCase();
                    filtered = filtered.where((m) =>
                        m.fullName.toLowerCase().contains(q) ||
                        (canPii && m.email.toLowerCase().contains(q))).toList();
                  }

                  if (filtered.isEmpty) return const _EmptyMembers();

                  return RefreshIndicator(
                    color: AppTheme.accent,
                    onRefresh: () async => ref.invalidate(_membersProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox.shrink(),
                      itemBuilder: (_, i) => _MemberRow(
                        member: filtered[i],
                        canPii: canPii,
                        isFirst: i == 0,
                        isLast: i == filtered.length - 1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool canEdit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          const Text('Members',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
          const Spacer(),
          if (canEdit) ...[
            GestureDetector(
              onTap: () => _showActionsMenu(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.more_horiz, size: 20, color: AppTheme.ink),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showAddMemberSheet(context),
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [BoxShadow(color: Color(0x33DF5B34), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: const Icon(Icons.add, size: 21, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showActionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: AppTheme.ink),
            title: const Text('Import members'),
            onTap: () { Navigator.pop(ctx); _openImportCsv(context); },
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined, color: AppTheme.ink),
            title: const Text('Expiring soon'),
            onTap: () { Navigator.pop(ctx); context.push('/staff/upcoming-payments'); },
          ),
        ]),
      ),
    );
  }

  Widget _buildSearchAndFilter(List<Member> all) {
    final counts = {
      'all':     all.length,
      'active':  all.where((m) => m.status == 'active').length,
      'lapsing': all.where(_isLapsing).length,
      'frozen':  all.where((m) => m.status == 'frozen').length,
      'expired': all.where((m) => m.status == 'expired').length,
    };
    const filters = [
      ('all', 'All', null, null),
      ('active', 'Active', null, null),
      ('lapsing', 'Lapsing', AppTheme.statusWarnBg, AppTheme.statusWarn),
      ('frozen', 'On hold', null, null),
      ('expired', 'Expired', null, null),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search members',
              prefixIcon: Icon(Icons.search, color: AppTheme.inkHint, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final (key, label, tintBg, tintFg) = f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(
                    label: label,
                    count: '${counts[key] ?? 0}',
                    selected: _filter == key,
                    tintBg: tintBg,
                    tintFg: tintFg,
                    onTap: () => setState(() => _filter = key),
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
    ).then((_) => ref.invalidate(_membersProvider));
  }

  void _openImportCsv(BuildContext context) {
    Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ImportCsvScreen()))
        .then((imported) {
      if (imported == true) ref.invalidate(_membersProvider);
    });
  }
}

// ── Member Row (grouped card list) ────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  final Member member;
  final bool canPii;
  final bool isFirst, isLast;
  const _MemberRow({required this.member, required this.canPii, required this.isFirst, required this.isLast});

  bool get _lapsing {
    if (member.status != 'active') return false;
    final npd = member.nextPaymentDate;
    if (npd == null || npd.isEmpty) return false;
    final due = DateTime.tryParse(npd);
    if (due == null) return false;
    final days = due.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 7;
  }

  StatusPill get _pill {
    if (_lapsing) return StatusPill.warn();
    return switch (member.status) {
      'active'    => StatusPill.active(),
      'frozen'    => StatusPill.neutral(),
      'expired'   => StatusPill.danger(),
      'cancelled' => StatusPill.neutral(label: 'Cancelled'),
      _           => StatusPill.neutral(label: member.status),
    };
  }

  String get _subtitle {
    final parts = <String>[];
    final plan = member.currentMembership?.plan?.name;
    if (plan != null && plan.isNotEmpty) parts.add(plan);
    final npd = member.nextPaymentDate;
    if (npd != null && npd.isNotEmpty) {
      parts.add(member.status == 'expired'
          ? 'Expired ${formatDateFromString(npd)}'
          : 'exp ${formatDateFromString(npd)}');
    } else if (canPii && member.email.isNotEmpty) {
      parts.add(member.email);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final expired = member.status == 'expired';
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: radius,
        border: isLast ? null : const Border(bottom: BorderSide(color: AppTheme.border, width: 0.7)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () => context.push('/staff/members/${member.id}'),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                InitialsAvatar(name: member.fullName, size: 46, photo: member.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.ink)),
                      if (_subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(_subtitle,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: expired ? AppTheme.statusDanger : AppTheme.inkSoft,
                            fontSize: 12.5,
                            fontWeight: expired ? FontWeight.w600 : FontWeight.w400,
                          )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _pill,
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  final _customIdCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _status = 'active';
  String? _joinedAt;
  String? _nextPaymentDate;
  int _billingIntervalMonths = 1;
  String? _planId;
  double _planDiscountAmount = 0;
  bool _paidToday = false;
  String _paymentMethod = 'cash';
  File? _avatarFile;
  bool _loading = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _customIdCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
    await MemberPhotoService.upload(path: filename, bytes: bytes, contentType: mime);
    // Stored value is the bare path; display resolves it via the photo Worker.
    return filename;
  }

  Future<void> _pickDate({required bool isJoined}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final s = picked.toIso8601String().split('T')[0];
      setState(() {
        if (isJoined) {
          _joinedAt = s;
        } else {
          _nextPaymentDate = s;
        }
      });
    }
  }

  String _intervalLabel(int months) {
    if (months == 1) return '1 Month';
    if (months == 12) return '1 Year';
    return '$months Months';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final avatarUrl = await _uploadAvatar(gymId);

      final inserted = await client.from('members').insert({
        'gym_id': gymId,
        'first_name': _firstCtrl.text.trim(),
        if (_lastCtrl.text.trim().isNotEmpty) 'last_name': _lastCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        if (_customIdCtrl.text.trim().isNotEmpty) 'custom_id': _customIdCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        'status': (_nextPaymentDate != null && _nextPaymentDate!.compareTo(DateTime.now().toIso8601String().split('T')[0]) < 0)
            ? 'expired'
            : _status,
        if (_joinedAt != null) 'joined_at': _joinedAt,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (_nextPaymentDate != null) 'next_payment_date': _nextPaymentDate,
        if (_nextPaymentDate != null) 'billing_interval_months': _billingIntervalMonths,
      }).select('id').single();

      // Assign the selected membership plan (open-ended, matches the web flow).
      // A DB trigger auto-creates the invoice the moment this insert commits.
      if (_planId != null) {
        await client.from('memberships').insert({
          'member_id': inserted['id'],
          'plan_id': _planId,
          'status': 'active',
          'starts_at': DateTime.now().toUtc().toIso8601String(),
          'ends_at': null,
          'discount_amount': _planDiscountAmount,
        });

        if (_paidToday) {
          final invoice = await client
              .from('invoices')
              .select('id')
              .eq('member_id', inserted['id'])
              .eq('status', 'open')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (invoice != null) {
            await client.rpc('record_invoice_payment', params: {
              'p_invoice_id': invoice['id'],
              'p_method': _paymentMethod,
            });
          }
        }
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppTheme.inkHint, width: 1.2, strokeAlign: BorderSide.strokeAlignInside),
                      ),
                      child: _avatarFile != null
                          ? ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.file(_avatarFile!, fit: BoxFit.cover))
                          : const Icon(Icons.photo_camera_outlined, size: 30, color: AppTheme.inkHint),
                    ),
                    const SizedBox(height: 8),
                    const Text('Add photo',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                  ]),
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
                  Expanded(child: TextFormField(controller: _lastCtrl, maxLength: 100, decoration: const InputDecoration(labelText: 'Last name (optional)', counterText: ''))),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)', counterText: ''),
                validator: validateOptionalEmail,
                onChanged: (_) => setState(() {}),
              ),
              if (_emailCtrl.text.trim().isEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  '⚠ Without email, the member portal won\'t be available and check-ins must be done manually.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                maxLength: 20,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)', counterText: ''),
                validator: validateOptionalPhone,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _customIdCtrl, maxLength: 50, decoration: const InputDecoration(labelText: 'Member ID (optional)', hintText: 'e.g. GYM-001', counterText: '')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(isJoined: true),
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
                    child: InkWell(
                      onTap: () => _pickDate(isJoined: false),
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Next payment date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
                        child: Text(
                          _nextPaymentDate != null ? formatDateFromString(_nextPaymentDate) : 'Optional',
                          style: TextStyle(color: _nextPaymentDate != null ? AppTheme.ink : AppTheme.inkHint),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_nextPaymentDate != null) ...[
                const SizedBox(height: 12),
                const Text('Payment Interval', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkHint, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [1, 2, 3, 6, 12].map((m) {
                    final selected = _billingIntervalMonths == m;
                    return GestureDetector(
                      onTap: () => setState(() => _billingIntervalMonths = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.ink : Colors.transparent,
                          border: Border.all(color: selected ? AppTheme.ink : AppTheme.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _intervalLabel(m),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.ink,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Invoices will be generated every ${_intervalLabel(_billingIntervalMonths).toLowerCase()} starting ${formatDateFromString(_nextPaymentDate)}.',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
                ),
              ],
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
                              onChanged: (v) => setState(() {
                                _planId = v;
                                if (v == null) _planDiscountAmount = 0;
                              }),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  );
                },
              ),
              if (_planId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Recurring discount (optional)',
                      hintText: '0',
                      prefixText: '₹ ',
                      helperText: 'Fixed amount deducted from every auto-generated invoice',
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v.trim()) ?? 0.0;
                      _planDiscountAmount = parsed < 0 ? 0 : parsed;
                    },
                  ),
                ),
              // Payment collected today — creates the invoice and marks it
              // paid in the same step, instead of two separate actions.
              if (_planId != null) ...[
                CheckboxListTile(
                  value: _paidToday,
                  onChanged: (v) => setState(() => _paidToday = v ?? false),
                  title: const Text('Payment collected today?'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_paidToday)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(labelText: 'Payment method'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                      ],
                      onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                    ),
                  ),
              ],
              TextFormField(controller: _notesCtrl, maxLines: 2, maxLength: 500, decoration: const InputDecoration(labelText: 'Notes (optional)', counterText: '')),
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

