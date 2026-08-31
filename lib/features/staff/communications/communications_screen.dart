import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_icons.dart';

// ─── Screen ────────────────────────────────────────────────────────────────────
class CommunicationsScreen extends StatelessWidget {
  const CommunicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Messages'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: _WaDueRemindersCard(),
        ),
      ),
    );
  }
}

// ─── WhatsApp Due Reminders card ───────────────────────────────────────────────
class _WaDueRemindersCard extends ConsumerStatefulWidget {
  const _WaDueRemindersCard();
  @override
  ConsumerState<_WaDueRemindersCard> createState() =>
      _WaDueRemindersCardState();
}

class _WaDueRemindersCardState extends ConsumerState<_WaDueRemindersCard> {
  int _daysFilter = 3;
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _loading = false);
        return;
      }
      final gymId = await ref.read(gymIdProvider.future);
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      dynamic raw;
      if (_daysFilter == 0) {
        raw = await client
            .from('members')
            .select('id, first_name, last_name, phone, next_payment_date')
            .eq('gym_id', gymId)
            .eq('status', 'expired')
            .not('phone', 'is', null)
            .order('next_payment_date', ascending: false)
            .limit(50);
      } else {
        final cutoff = DateTime.now()
            .add(Duration(days: _daysFilter))
            .toIso8601String()
            .split('T')[0];
        raw = await client
            .from('members')
            .select('id, first_name, last_name, phone, next_payment_date')
            .eq('gym_id', gymId)
            .eq('status', 'active')
            .not('phone', 'is', null)
            .gte('next_payment_date', todayStr)
            .lte('next_payment_date', cutoff)
            .order('next_payment_date');
      }
      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(raw as List);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[GymCRM] Fetch members for audience error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWhatsApp(Map<String, dynamic> member) async {
    final raw = member['phone'] as String? ?? '';
    final phone = _e164(raw);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on record')),
      );
      return;
    }
    final name = '${member['first_name'] ?? ''}'.trim();
    final dateStr = member['next_payment_date'] as String?;
    final msg = _buildMsg(name, dateStr);
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard')),
        );
      }
    }
  }

  String _e164(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (d.startsWith('91') && d.length == 12) return d;
    if (d.length == 10) return '91$d';
    return d;
  }

  String _buildMsg(String name, String? dateStr) {
    final n = name.isEmpty ? 'there' : name;
    if (_daysFilter == 0) {
      return dateStr != null
          ? 'Hi $n, your gym membership expired on $dateStr. Please renew to continue accessing the gym!'
          : 'Hi $n, your gym membership has expired. Please renew to continue!';
    }
    if (dateStr != null) {
      final expiry = DateTime.tryParse(dateStr);
      if (expiry != null) {
        final left = expiry.difference(DateTime.now()).inDays;
        if (left <= 0)
          return 'Hi $n, your gym membership expires today! Please renew to keep your access.';
        return 'Hi $n, your gym membership expires in $left day${left == 1 ? '' : 's'} (on $dateStr). Please renew soon!';
      }
    }
    return 'Hi $n, your gym membership is due soon. Please renew to keep your access!';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Due reminders',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _load,
                child: const Icon(
                  AppIcons.refresh,
                  size: 18,
                  color: AppTheme.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap Send to open WhatsApp with a pre-filled reminder — you just hit send.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(
                label: '3 days',
                selected: _daysFilter == 3,
                onTap: () {
                  setState(() => _daysFilter = 3);
                  _load();
                },
              ),
              PillChip(
                label: '7 days',
                selected: _daysFilter == 7,
                onTap: () {
                  setState(() => _daysFilter = 7);
                  _load();
                },
              ),
              PillChip(
                label: 'Expired',
                selected: _daysFilter == 0,
                onTap: () {
                  setState(() => _daysFilter = 0);
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No members due in this range',
                  style: TextStyle(fontSize: 13, color: AppTheme.inkHint),
                ),
              ),
            )
          else
            CardList(
              children: List.generate(
                _members.length,
                (i) => _DueMemberRow(
                  member: _members[i],
                  daysFilter: _daysFilter,
                  onSend: () => _openWhatsApp(_members[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Due member row ────────────────────────────────────────────────────────────
class _DueMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final int daysFilter;
  final VoidCallback onSend;
  const _DueMemberRow({
    required this.member,
    required this.daysFilter,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = member['first_name'] as String? ?? '';
    final lastName = member['last_name'] as String? ?? '';
    final name = '$firstName $lastName'.trim();
    final phone = member['phone'] as String? ?? '';
    final dateStr = member['next_payment_date'] as String?;

    String badgeText = '';
    Widget badge = const SizedBox.shrink();

    if (daysFilter == 0) {
      badgeText = 'Expired';
      badge = StatusPill.danger(label: badgeText);
    } else if (dateStr != null) {
      final expiry = DateTime.tryParse(dateStr);
      if (expiry != null) {
        final left = expiry.difference(DateTime.now()).inDays;
        badgeText = left <= 0 ? 'Today' : '${left}d';
        badge = left <= 1
            ? StatusPill.danger(label: badgeText)
            : StatusPill.warn(label: badgeText);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          InitialsAvatar(name: name.isEmpty ? '?' : name, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unknown' : name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          if (badgeText.isNotEmpty) ...[badge, const SizedBox(width: 8)],
          PillButton(
            label: 'Send',
            onTap: phone.isEmpty ? null : onSend,
            filled: phone.isNotEmpty,
          ),
        ],
      ),
    );
  }
}
