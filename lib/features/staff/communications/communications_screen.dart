import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';

// ─── Channel enum ──────────────────────────────────────────────────────────────
enum _Channel { email, push, whatsapp }

// ─── Template model ────────────────────────────────────────────────────────────
class _Template {
  final String name;
  final String subject;
  final String body;
  const _Template({required this.name, required this.subject, required this.body});
}

const _kTemplates = [
  _Template(
    name: 'Welcome',
    subject: 'Welcome to the gym!',
    body: 'Hi {name}, welcome to our gym! We\'re excited to have you on board. Your membership is now active. See you at the gym!',
  ),
  _Template(
    name: 'Dues Reminder',
    subject: 'Your membership dues are due',
    body: 'Hi {name}, this is a friendly reminder that your membership dues are due soon. Please visit reception or contact us to renew.',
  ),
  _Template(
    name: 'Renewal Due',
    subject: 'Time to renew your membership',
    body: 'Hi {name}, your membership is expiring soon! Don\'t lose your progress — renew now to keep your access.',
  ),
  _Template(
    name: 'Holiday Hours',
    subject: 'Special holiday hours this week',
    body: 'Hi {name}, just a heads up — we have special hours this holiday season. Please check our schedule before visiting.',
  ),
];

const _kAudienceFilters = ['all', 'active', 'expired', 'frozen'];
const _kAudienceLabels = {
  'all':     'All Members',
  'active':  'Active Members',
  'expired': 'Expired Members',
  'frozen':  'Frozen Members',
};

// ─── Send result ───────────────────────────────────────────────────────────────
class _SendResult {
  final int sent;
  final int failed;
  final int skipped;
  final int total;
  final String? lastError;
  const _SendResult({required this.sent, required this.failed, required this.skipped, required this.total, this.lastError});
  factory _SendResult.fromJson(Map<String, dynamic> j) => _SendResult(
    sent:      j['sent']    as int? ?? 0,
    failed:    j['failed']  as int? ?? 0,
    skipped:   j['skipped'] as int? ?? 0,
    total:     j['total']   as int? ?? 0,
    lastError: j['lastError'] as String?,
  );
}

// ─── Screen ────────────────────────────────────────────────────────────────────
class CommunicationsScreen extends StatefulWidget {
  const CommunicationsScreen({super.key});

  @override
  State<CommunicationsScreen> createState() => _CommunicationsScreenState();
}

class _CommunicationsScreenState extends State<CommunicationsScreen> {
  _Channel _channel  = _Channel.email;
  String   _audience = 'all';
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool     _sending  = false;
  _SendResult? _result;

  List<_Channel> get _channels =>
      [_Channel.email, _Channel.push, _Channel.whatsapp];

  @override
  void initState() {
    super.initState();
    _subjectCtrl.addListener(() => setState(() {}));
    _messageCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(_Template t) {
    setState(() {
      _subjectCtrl.text = t.subject;
      _messageCtrl.text = t.body;
    });
    FocusScope.of(context).unfocus();
  }

  void _switchChannel(_Channel c) => setState(() { _channel = c; _result = null; });

  // ── Email / Push broadcast ───────────────────────────────────────────────────
  Future<void> _sendBroadcast() async {
    final msg     = _messageCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();
    if (msg.isEmpty)     { _showSnack('Message is required'); return; }
    if (subject.isEmpty) {
      _showSnack(_channel == _Channel.email ? 'Subject is required' : 'Notification title is required');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Send ${_channel == _Channel.email ? 'Email' : 'Push'}'),
        content: Text('Send to ${_kAudienceLabels[_audience]}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { _sending = true; _result = null; });
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) { _showSnack('Session expired — please sign in again'); return; }

      final res = await http.post(
        Uri.parse('https://www.gymcrm.in/api/communications'),
        headers: {
          HttpHeaders.contentTypeHeader:   'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: jsonEncode({
          'channel': _channel == _Channel.email ? 'email' : 'push',
          'subject': subject,
          'message': msg,
          'filter':  _audience,
        }),
      );

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) { _showSnack(json['error'] as String? ?? 'Failed to send'); return; }

      setState(() {
        _result = _SendResult.fromJson(json);
        _subjectCtrl.clear();
        _messageCtrl.clear();
      });
      _showSnack('Sent to ${_result!.sent} members');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _copyMessage() {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) { _showSnack('Nothing to copy.'); return; }
    Clipboard.setData(ClipboardData(text: msg));
    _showSnack('Message copied to clipboard');
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Messages'), leading: const BackButton()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChannelSelector(channels: _channels, selected: _channel, onChanged: _switchChannel),
            const SizedBox(height: 16),

            // ── WhatsApp: Due Reminders only ──────────────────────────────
            if (_channel == _Channel.whatsapp)
              const _WaDueRemindersCard()
            else ...[
              // ── Email / Push composer ───────────────────────────────────
              _ComposerCard(
                channel:    _channel,
                audience:   _audience,
                onAudienceChanged: (v) => setState(() { _audience = v!; _result = null; }),
                subjectCtrl: _subjectCtrl,
                messageCtrl: _messageCtrl,
                sending:    _sending,
                onSend:     _sendBroadcast,
                onCopy:     _copyMessage,
              ),

              if (_result != null) ...[
                const SizedBox(height: 12),
                _ResultCard(result: _result!),
              ],

              const SizedBox(height: 16),
              _TemplatesCard(onSelect: _applyTemplate),
            ],

            const SizedBox(height: 16),
            _RecentActivityCard(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Channel selector ──────────────────────────────────────────────────────────
class _ChannelSelector extends StatelessWidget {
  final List<_Channel> channels;
  final _Channel selected;
  final ValueChanged<_Channel> onChanged;
  const _ChannelSelector({required this.channels, required this.selected, required this.onChanged});

  String _label(_Channel c) => switch (c) {
    _Channel.email    => 'Email',
    _Channel.push     => 'Push',
    _Channel.whatsapp => 'WhatsApp',
  };

  IconData _icon(_Channel c) => switch (c) {
    _Channel.email    => Icons.email_outlined,
    _Channel.push     => Icons.notifications_outlined,
    _Channel.whatsapp => Icons.chat_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
      ),
      child: Row(
        children: channels.map((c) {
          final isSelected = c == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(c), size: 16, color: isSelected ? Colors.white : AppTheme.inkSoft),
                    const SizedBox(height: 3),
                    Text(
                      _label(c),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Composer card (Email / Push / WhatsApp) ───────────────────────────────────
class _ComposerCard extends StatelessWidget {
  final _Channel channel;
  final String audience;
  final ValueChanged<String?> onAudienceChanged;
  final TextEditingController subjectCtrl;
  final TextEditingController messageCtrl;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onCopy;

  const _ComposerCard({
    required this.channel,
    required this.audience,
    required this.onAudienceChanged,
    required this.subjectCtrl,
    required this.messageCtrl,
    required this.sending,
    required this.onSend,
    required this.onCopy,
  });

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
              Icon(
                channel == _Channel.email ? Icons.email_outlined
                    : channel == _Channel.push ? Icons.notifications_outlined
                    : Icons.chat_outlined,
                size: 16, color: AppTheme.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                channel == _Channel.email ? 'Email broadcast'
                    : channel == _Channel.push ? 'Push notification broadcast'
                    : 'WhatsApp broadcast',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Audience
          const FieldLabel('Send to'),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kAudienceFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final a = _kAudienceFilters[i];
                return PillChip(
                  label: _kAudienceLabels[a] ?? a,
                  selected: audience == a,
                  onTap: () => onAudienceChanged(a),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Subject / Title (email + push only)
          if (channel != _Channel.whatsapp) ...[
            FieldLabel(channel == _Channel.email ? 'Subject' : 'Notification title'),
            TextField(
              controller: subjectCtrl,
              decoration: InputDecoration(
                hintText: channel == _Channel.email
                    ? 'e.g. Important update from your gym'
                    : 'e.g. Special offer this weekend!',
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Message body
          const FieldLabel('Message'),
          TextField(
            controller: messageCtrl,
            maxLines: channel == _Channel.push ? 3 : 5,
            decoration: const InputDecoration(
              hintText: 'Type your message…\nUse {name} to personalise.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${messageCtrl.text.length} characters',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
              if (channel == _Channel.push)
                const Text('  ·  keep it short',
                    style: TextStyle(fontSize: 11, color: AppTheme.inkHint)),
            ],
          ),
          const SizedBox(height: 14),

          // Buttons
          if (channel == _Channel.whatsapp)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: sending ? null : onSend,
                    icon: sending
                        ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ink))
                        : const Icon(Icons.chat_outlined, size: 17),
                    label: const Text('WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.ink,
                      side: const BorderSide(color: AppTheme.border),
                      minimumSize: const Size(0, 46),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Copy'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(channel == _Channel.email ? Icons.send_outlined : Icons.notifications_outlined, size: 18),
                label: Text(sending ? 'Sending...' : channel == _Channel.email ? 'Send Email' : 'Send Push'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Result card ───────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final _SendResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.statusActiveBg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40, width: 40,
            decoration: BoxDecoration(color: AppTheme.statusActive, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.check, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Broadcast complete',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppTheme.statusActive)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    StatusPill.active(label: '${result.sent} sent'),
                    if (result.failed  > 0) StatusPill.danger(label: '${result.failed} failed'),
                    if (result.skipped > 0) StatusPill.neutral(label: '${result.skipped} skipped'),
                  ],
                ),
                if (result.lastError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppTheme.statusDangerBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(result.lastError!, style: const TextStyle(fontSize: 11.5, color: AppTheme.statusDanger)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick templates card ──────────────────────────────────────────────────────
class _TemplatesCard extends StatelessWidget {
  final ValueChanged<_Template> onSelect;
  const _TemplatesCard({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Templates',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          const SizedBox(height: 10),
          CardList(
            children: List.generate(_kTemplates.length, (i) {
              final t = _kTemplates[i];
              return _TemplateTile(template: t, onTap: () => onSelect(t));
            }),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  final _Template template;
  final VoidCallback onTap;
  const _TemplateTile({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  const SizedBox(height: 2),
                  Text(template.subject,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppTheme.inkHint),
          ],
        ),
      ),
    );
  }
}

// ─── WhatsApp Due Reminders card ───────────────────────────────────────────────
class _WaDueRemindersCard extends StatefulWidget {
  const _WaDueRemindersCard();
  @override
  State<_WaDueRemindersCard> createState() => _WaDueRemindersCardState();
}

class _WaDueRemindersCardState extends State<_WaDueRemindersCard> {
  int  _daysFilter = 3;
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
      final profile = await client.from('profiles')
          .select('gym_id').eq('id', userId).maybeSingle();
      final gymId = profile?['gym_id'] as String?;
      if (gymId == null || gymId.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      dynamic raw;
      if (_daysFilter == 0) {
        raw = await client.from('members')
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
        raw = await client.from('members')
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
    final raw   = member['phone'] as String? ?? '';
    final phone = _e164(raw);
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No phone number on record')));
      return;
    }
    final name    = '${member['first_name'] ?? ''}'.trim();
    final dateStr = member['next_payment_date'] as String?;
    final msg     = _buildMsg(name, dateStr);
    final uri     = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Message copied to clipboard')));
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
        if (left <= 0) return 'Hi $n, your gym membership expires today! Please renew to keep your access.';
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
                child: Text('Due reminders',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              ),
              GestureDetector(
                onTap: _load,
                child: const Icon(Icons.refresh, size: 18, color: AppTheme.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap Send to open WhatsApp with a pre-filled reminder — you just hit send.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(label: '3 days', selected: _daysFilter == 3,
                  onTap: () { setState(() => _daysFilter = 3); _load(); }),
              PillChip(label: '7 days', selected: _daysFilter == 7,
                  onTap: () { setState(() => _daysFilter = 7); _load(); }),
              PillChip(label: 'Expired', selected: _daysFilter == 0,
                  onTap: () { setState(() => _daysFilter = 0); _load(); }),
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
                child: Text('No members due in this range',
                    style: TextStyle(fontSize: 13, color: AppTheme.inkHint)),
              ),
            )
          else
            CardList(
              children: List.generate(_members.length, (i) => _DueMemberRow(
                member:     _members[i],
                daysFilter: _daysFilter,
                onSend:     () => _openWhatsApp(_members[i]),
              )),
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
  const _DueMemberRow({required this.member, required this.daysFilter, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final firstName = member['first_name'] as String? ?? '';
    final lastName  = member['last_name']  as String? ?? '';
    final name      = '$firstName $lastName'.trim();
    final phone     = member['phone'] as String? ?? '';
    final dateStr   = member['next_payment_date'] as String?;

    String badgeText  = '';
    Widget badge = const SizedBox.shrink();

    if (daysFilter == 0) {
      badgeText = 'Expired';
      badge = StatusPill.danger(label: badgeText);
    } else if (dateStr != null) {
      final expiry = DateTime.tryParse(dateStr);
      if (expiry != null) {
        final left = expiry.difference(DateTime.now()).inDays;
        badgeText = left <= 0 ? 'Today' : '${left}d';
        badge = left <= 1 ? StatusPill.danger(label: badgeText) : StatusPill.warn(label: badgeText);
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
                Text(name.isEmpty ? 'Unknown' : name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.ink),
                    overflow: TextOverflow.ellipsis),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          if (badgeText.isNotEmpty) ...[
            badge,
            const SizedBox(width: 8),
          ],
          PillButton(label: 'Send', onTap: phone.isEmpty ? null : onSend, filled: phone.isNotEmpty),
        ],
      ),
    );
  }
}

// ─── Recent activity card ──────────────────────────────────────────────────────
class _RecentActivityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Recent broadcasts',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.ink)),
          SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(Icons.mark_chat_unread_outlined, size: 40, color: AppTheme.inkHint),
                SizedBox(height: 10),
                Text('No messages sent yet',
                    style: TextStyle(color: AppTheme.inkHint, fontSize: 14)),
              ],
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}
