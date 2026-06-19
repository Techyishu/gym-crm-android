import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────
final staffListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;
  return await client
      .from('profiles')
      .select('id, first_name, last_name, role, phone')
      .eq('gym_id', gymId)
      .order('role');
});

// ─── Role config ──────────────────────────────────────────────────────────────
const _kRoles = [
  ('manager', 'Manager', 'Members, classes, billing, communications'),
  ('trainer', 'Trainer', 'Own classes & schedule, check-in, attendance'),
  ('staff',   'Staff',   'Basic access to members and check-ins'),
];

// ─── Screen ───────────────────────────────────────────────────────────────────
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);
    final roleAsync  = ref.watch(staffRoleProvider);
    final currentId  = Supabase.instance.client.auth.currentUser?.id;
    final isOwner    = roleAsync.valueOrNull == 'owner';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Staff'),
        leading: const BackButton(),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Invite staff',
              onPressed: () => _showInviteSheet(context, ref),
            ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppTheme.inkSoft)),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _RoleGuide(),
            const SizedBox(height: 16),
            Text(
              '${list.length} team member${list.length != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('No staff members yet.',
                      style: TextStyle(color: AppTheme.inkSoft)),
                ),
              )
            else
              ...list.map((m) => _StaffCard(
                staff:    m,
                isOwner:  isOwner,
                isSelf:   m['id'] == currentId,
                onRemove: () => _confirmRemove(context, ref, m),
              )),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _InviteStaffSheet(),
    ).then((_) => ref.invalidate(staffListProvider));
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, Map<String, dynamic> member) async {
    final first = member['first_name'] as String? ?? '';
    final last  = member['last_name']  as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove staff member'),
        content: Text('Remove $first $last? They will lose access immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.statusDanger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final auth    = Supabase.instance.client.auth;
      final session = auth.currentSession ?? (await auth.refreshSession()).session;
      final token   = session?.accessToken;
      if (token == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please sign in again.')));
        }
        return;
      }
      final res = await http.delete(
        Uri.parse('https://www.gymcrm.in/api/staff'),
        headers: {
          HttpHeaders.contentTypeHeader:   'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: jsonEncode({'staffId': member['id']}),
      );
      if (!context.mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Staff member removed')));
        ref.invalidate(staffListProvider);
      } else {
        final err = (jsonDecode(res.body) as Map)['error'] ?? 'Failed to remove';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err.toString())));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ─── Role guide ───────────────────────────────────────────────────────────────
class _RoleGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Roles',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 10),
          ..._kRoles.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RoleBadge(role: r.$1),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r.$3,
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.4)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ─── Staff card ───────────────────────────────────────────────────────────────
class _StaffCard extends StatelessWidget {
  final Map<String, dynamic> staff;
  final bool isOwner;
  final bool isSelf;
  final VoidCallback onRemove;
  const _StaffCard({
    required this.staff,
    required this.isOwner,
    required this.isSelf,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final first   = staff['first_name'] as String? ?? '';
    final last    = staff['last_name']  as String? ?? '';
    final role    = staff['role']       as String? ?? 'staff';
    final phone   = staff['phone']      as String?;
    final initials =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.activeBg,
              child: Text(initials,
                  style: const TextStyle(
                      color: AppTheme.ink, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('$first $last'.trim(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                      ),
                      if (isSelf) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppTheme.surface2,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('You',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.inkSoft)),
                        ),
                      ],
                    ],
                  ),
                  if (phone != null && phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(phone,
                        style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoleBadge(role: role),
            if (isOwner && role != 'owner' && !isSelf) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.statusDangerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline, size: 17, color: AppTheme.statusDanger),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Role badge ───────────────────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (role) {
      'owner'   => (const Color(0xFFF0F0F0), const Color(0xFF111111)),
      'manager' => (const Color(0xFFFFF3E0), const Color(0xFFE65100)),
      'trainer' => (const Color(0xFFF3E8FF), const Color(0xFF7C3AED)),
      _         => (AppTheme.activeBg,       AppTheme.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ─── Invite staff sheet ───────────────────────────────────────────────────────
class _InviteStaffSheet extends StatefulWidget {
  const _InviteStaffSheet();
  @override
  State<_InviteStaffSheet> createState() => _InviteStaffSheetState();
}

class _InviteStaffSheetState extends State<_InviteStaffSheet> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  String  _role    = 'trainer';
  bool    _sending = false;
  String? _error;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final first = _firstCtrl.text.trim();
    final last  = _lastCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'First and last name are required.');
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() { _sending = true; _error = null; });
    try {
      final auth    = Supabase.instance.client.auth;
      final session = auth.currentSession ?? (await auth.refreshSession()).session;
      final token   = session?.accessToken;
      if (token == null) {
        setState(() => _error = 'Session expired. Please sign in again.');
        return;
      }
      final res = await http.post(
        Uri.parse('https://www.gymcrm.in/api/staff'),
        headers: {
          HttpHeaders.contentTypeHeader:   'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: jsonEncode({
          'first_name': first,
          'last_name':  last,
          'email':      email,
          'role':       _role,
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invite sent to $email')));
      } else {
        final body = jsonDecode(res.body) as Map;
        setState(() => _error = body['error']?.toString() ?? 'Failed to send invite');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Invite Staff Member',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Text(
            'They\'ll receive an email to set their password and log in.',
            style: TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 20),

          // Name row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First name', hintText: 'Rahul'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lastCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Last name', hintText: 'Sharma'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Email
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
                labelText: 'Email', hintText: 'staff@example.com'),
          ),
          const SizedBox(height: 16),

          // Role chips
          const Text('Role',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink)),
          const SizedBox(height: 8),
          Row(
            children: _kRoles.map((r) {
              final selected = _role == r.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _role = r.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.ink : AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: selected ? AppTheme.ink : AppTheme.border),
                    ),
                    child: Text(r.$2,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.inkSoft,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            _kRoles.firstWhere((r) => r.$1 == _role).$3,
            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.4),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: AppTheme.statusDangerBg,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.statusDanger)),
            ),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_sending ? 'Sending invite…' : 'Send Invite'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
