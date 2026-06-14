import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../reminders/sms_reminder_service.dart';

// ─── Channel enum ──────────────────────────────────────────────────────────────
enum _Channel { email, push, whatsapp, sms }

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

  List<_Channel> get _channels => Platform.isIOS
      ? [_Channel.email, _Channel.push, _Channel.whatsapp]
      : [_Channel.email, _Channel.push, _Channel.whatsapp, _Channel.sms];

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
        Uri.parse('https://gymcrm.in/api/communications'),
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
    final isSms = _channel == _Channel.sms;

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

            // ── SMS tab: full SMS panel (Android only) ────────────────────
            if (isSms)
              const _SmsPanel()
            else ...[
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
            ],

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
    _Channel.sms      => 'SMS',
  };

  IconData _icon(_Channel c) => switch (c) {
    _Channel.email    => Icons.email_outlined,
    _Channel.push     => Icons.notifications_outlined,
    _Channel.whatsapp => Icons.chat_outlined,
    _Channel.sms      => Icons.sms_outlined,
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
                channel == _Channel.email ? 'Email Broadcast'
                    : channel == _Channel.push ? 'Push Notification Broadcast'
                    : 'WhatsApp Broadcast',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Audience
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Send to',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: audience,
                isExpanded: true,
                isDense: true,
                items: _kAudienceFilters
                    .map((a) => DropdownMenuItem(value: a, child: Text(_kAudienceLabels[a] ?? a)))
                    .toList(),
                onChanged: onAudienceChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Subject / Title (email + push only)
          if (channel != _Channel.whatsapp) ...[
            TextField(
              controller: subjectCtrl,
              decoration: InputDecoration(
                labelText: channel == _Channel.email ? 'Subject' : 'Notification title',
                hintText: channel == _Channel.email
                    ? 'e.g. Important update from your gym'
                    : 'e.g. Special offer this weekend!',
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Message body
          TextField(
            controller: messageCtrl,
            maxLines: channel == _Channel.push ? 3 : 5,
            decoration: const InputDecoration(
              hintText: 'Type your message...\nUse {name} to personalise.',
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

// ─── SMS Panel (Android only — full screen with broadcast + auto-reminders) ────
class _SmsPanel extends StatefulWidget {
  const _SmsPanel();

  @override
  State<_SmsPanel> createState() => _SmsPanelState();
}

class _SmsPanelState extends State<_SmsPanel> {
  // ── Broadcast state ──────────────────────────────────────────────────────────
  String _broadcastAudience = 'all';
  final _broadcastCtrl = TextEditingController();
  bool _broadcastSending = false;
  int _broadcastSent = -1; // -1 = not sent yet

  // ── Auto-reminder state ──────────────────────────────────────────────────────
  bool _autoEnabled   = false;
  int  _daysBefore    = 3;
  late TextEditingController _templateCtrl;
  bool _reminderLoading = true;
  bool _reminderSending = false;
  SharedPreferences? _prefs;

  static const _daysOptions = [1, 2, 3, 5, 7, 14];
  static const _smsChannel  = MethodChannel('com.gymcrm/sms');

  @override
  void initState() {
    super.initState();
    _templateCtrl = TextEditingController();
    _loadReminderSettings();
    _broadcastCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _broadcastCtrl.dispose();
    _templateCtrl.dispose();
    super.dispose();
  }

  // ── Load reminder prefs ──────────────────────────────────────────────────────
  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prefs           = prefs;
      _autoEnabled     = prefs.getBool(kSmsEnabled) ?? false;
      _daysBefore      = prefs.getInt(kSmsDaysBefore) ?? 3;
      _templateCtrl.text = prefs.getString(kSmsTemplate) ?? kSmsDefaultTemplate;
      _reminderLoading = false;
    });
  }

  Future<void> _saveReminderSettings() async {
    await _prefs?.setBool(kSmsEnabled, _autoEnabled);
    await _prefs?.setInt(kSmsDaysBefore, _daysBefore);
    await _prefs?.setString(kSmsTemplate,
        _templateCtrl.text.trim().isEmpty ? kSmsDefaultTemplate : _templateCtrl.text.trim());
  }

  // ── SMS permission ───────────────────────────────────────────────────────────
  Future<bool> _ensureSmsPermission() async {
    var status = await Permission.sms.status;
    if (status.isGranted) return true;
    status = await Permission.sms.request();
    if (status.isGranted) return true;
    if (!mounted) return false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('SMS Permission Blocked'),
        content: const Text(
          'Android blocked the SMS permission.\n\n'
          'To fix this:\n'
          '1. Go to Settings → Apps → gym_crm\n'
          '2. Tap the ⋮ menu → "Allow restricted settings"\n'
          '3. Come back and try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); }, child: const Text('Open Settings')),
        ],
      ),
    );
    return false;
  }

  // ── SMS Broadcast (custom audience + message) ────────────────────────────────
  Future<void> _sendSmsBroadcast() async {
    final msg = _broadcastCtrl.text.trim();
    if (msg.isEmpty) { _showSnack('Message is required'); return; }

    final granted = await _ensureSmsPermission();
    if (!granted || !mounted) return;

    final audienceLabel = _kAudienceLabels[_broadcastAudience] ?? _broadcastAudience;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send SMS Broadcast'),
        content: Text('Send SMS to $audienceLabel using your SIM?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { _broadcastSending = true; _broadcastSent = -1; });
    try {
      final members = await _fetchMembersForAudience(_broadcastAudience);
      int sent = 0;
      for (final m in members) {
        final phone = (m['phone'] as String?)?.trim();
        if (phone == null || phone.isEmpty) continue;
        final name = m['first_name'] as String? ?? 'Member';
        final text = msg.replaceAll('{name}', name);
        try {
          await _smsChannel.invokeMethod('sendSms', {'to': phone, 'message': text});
          sent++;
        } catch (e) {
          debugPrint('[GymCRM] SMS send error to $phone: $e');
        }
      }
      setState(() => _broadcastSent = sent);
      _showSnack('Sent $sent SMS${sent == 1 ? '' : 's'} successfully');
      _broadcastCtrl.clear();
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _broadcastSending = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMembersForAudience(String audience) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final profile = await client.from('profiles').select('gym_id').eq('id', userId).maybeSingle();
    final gymId = profile?['gym_id'] as String?;
    if (gymId == null || gymId.isEmpty) return [];
    var query = client.from('members').select('id, first_name, last_name, phone')
        .eq('gym_id', gymId).not('phone', 'is', null);
    if (audience == 'active')  query = query.eq('status', 'active');
    if (audience == 'expired') query = query.eq('status', 'expired');
    if (audience == 'frozen')  query = query.eq('status', 'frozen');
    final data = await query;
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── Auto reminder toggle ─────────────────────────────────────────────────────
  Future<void> _toggleAutoReminders(bool value) async {
    if (value) {
      final granted = await _ensureSmsPermission();
      if (!granted) return;
    }
    setState(() => _autoEnabled = value);
    await _saveReminderSettings();
    _showSnack(value ? 'Auto SMS reminders enabled' : 'Auto SMS reminders disabled');
  }

  // ── Send reminders now ───────────────────────────────────────────────────────
  Future<void> _sendRemindersNow() async {
    final granted = await _ensureSmsPermission();
    if (!granted) return;
    await _saveReminderSettings();
    setState(() => _reminderSending = true);
    try {
      final count = await SmsReminderService.sendManualReminders();
      if (mounted) {
        _showSnack(count == 0
            ? 'No members with expiring memberships found.'
            : 'Sent $count reminder${count == 1 ? '' : 's'} successfully.');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _reminderSending = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_reminderLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Info banner ──────────────────────────────────────────────────────
        _SmsInfoBanner(),
        const SizedBox(height: 16),

        // ── SMS Broadcast ────────────────────────────────────────────────────
        _SmsBroadcastCard(
          audience:   _broadcastAudience,
          onAudienceChanged: (v) => setState(() { _broadcastAudience = v!; _broadcastSent = -1; }),
          messageCtrl: _broadcastCtrl,
          sending:    _broadcastSending,
          sentCount:  _broadcastSent,
          onSend:     _sendSmsBroadcast,
        ),
        const SizedBox(height: 16),

        // ── Auto-reminders ───────────────────────────────────────────────────
        _AutoReminderCard(
          enabled:    _autoEnabled,
          daysBefore: _daysBefore,
          daysOptions: _daysOptions,
          onToggle:   _toggleAutoReminders,
          onDaysChanged: (v) async {
            setState(() => _daysBefore = v!);
            await _saveReminderSettings();
          },
        ),
        const SizedBox(height: 16),

        // ── Message template ─────────────────────────────────────────────────
        _SmsTemplateCard(
          controller: _templateCtrl,
          onReset: () async {
            setState(() => _templateCtrl.text = kSmsDefaultTemplate);
            await _saveReminderSettings();
          },
          onChanged: (_) => _saveReminderSettings(),
        ),
        const SizedBox(height: 16),

        // ── Send reminders now ───────────────────────────────────────────────
        _ReminderSendNowCard(
          daysBefore: _daysBefore,
          sending:    _reminderSending,
          onSend:     _sendRemindersNow,
        ),
      ],
    );
  }
}

// ─── SMS info banner ───────────────────────────────────────────────────────────
class _SmsInfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.activeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sms_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'SMS messages are sent from your own SIM card — no third-party service needed. '
              'Members receive the SMS directly from your phone number.',
              style: TextStyle(fontSize: 13, color: AppTheme.ink, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SMS Broadcast card ────────────────────────────────────────────────────────
class _SmsBroadcastCard extends StatelessWidget {
  final String audience;
  final ValueChanged<String?> onAudienceChanged;
  final TextEditingController messageCtrl;
  final bool sending;
  final int sentCount;
  final VoidCallback onSend;

  const _SmsBroadcastCard({
    required this.audience,
    required this.onAudienceChanged,
    required this.messageCtrl,
    required this.sending,
    required this.sentCount,
    required this.onSend,
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
              const Icon(Icons.chat_outlined, size: 16, color: AppTheme.inkSoft),
              const SizedBox(width: 6),
              const Text('SMS Broadcast',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Send a custom SMS to a group of members right now.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          const SizedBox(height: 14),

          // Audience
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Send to',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: audience,
                isExpanded: true,
                isDense: true,
                items: _kAudienceFilters
                    .map((a) => DropdownMenuItem(value: a, child: Text(_kAudienceLabels[a] ?? a)))
                    .toList(),
                onChanged: onAudienceChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Message
          TextField(
            controller: messageCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Type your message...\nUse {name} to personalise.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          Text('${messageCtrl.text.length} characters',
              style: const TextStyle(fontSize: 11, color: AppTheme.inkHint)),
          const SizedBox(height: 14),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sms_outlined, size: 18),
              label: Text(sending ? 'Sending...' : 'Send SMS Now'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // Result
          if (sentCount >= 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF065F46), size: 16),
                  const SizedBox(width: 8),
                  Text('$sentCount SMS sent successfully',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF065F46), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Auto-reminder card ────────────────────────────────────────────────────────
class _AutoReminderCard extends StatelessWidget {
  final bool enabled;
  final int daysBefore;
  final List<int> daysOptions;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int?> onDaysChanged;

  const _AutoReminderCard({
    required this.enabled,
    required this.daysBefore,
    required this.daysOptions,
    required this.onToggle,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Auto Reminders',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 4),
          const Text('Runs daily in the background — sends to members whose membership is about to expire.',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.5)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Enable auto reminders',
                  style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500)),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const Divider(height: 24),
            const Text('Send reminder',
                style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: daysBefore,
                  isExpanded: true,
                  isDense: true,
                  items: daysOptions
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('$d day${d == 1 ? '' : 's'} before expiry'),
                          ))
                      .toList(),
                  onChanged: onDaysChanged,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── SMS Template card ─────────────────────────────────────────────────────────
class _SmsTemplateCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onReset;
  final ValueChanged<String> onChanged;

  const _SmsTemplateCard({
    required this.controller,
    required this.onReset,
    required this.onChanged,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Reminder Template',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Used by both auto-reminders and "Send Reminders Now".',
              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 4,
            onChanged: onChanged,
            decoration: const InputDecoration(
              hintText: 'Type your reminder message...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          _PlaceholderRow(label: '{name}', hint: "Member's first name"),
          const SizedBox(height: 6),
          _PlaceholderRow(label: '{days}', hint: 'Days before expiry (auto-reminders only)'),
        ],
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  final String label;
  final String hint;
  const _PlaceholderRow({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, fontFamily: 'monospace',
                  color: AppTheme.primary, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(hint, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft))),
      ],
    );
  }
}

// ─── Send reminders now card ───────────────────────────────────────────────────
class _ReminderSendNowCard extends StatelessWidget {
  final int daysBefore;
  final bool sending;
  final VoidCallback onSend;

  const _ReminderSendNowCard({
    required this.daysBefore,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Send Reminders Now',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 6),
          Text(
            'Manually send the reminder template to members whose membership expires in $daysBefore day${daysBefore == 1 ? '' : 's'}.',
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(sending ? 'Sending...' : 'Send Reminders Now'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36, width: 36,
            decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.check_circle_outline, color: Color(0xFF065F46), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Broadcast complete',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF065F46))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: [
                    _Chip('${result.sent} sent', const Color(0xFF065F46), const Color(0xFFD1FAE5)),
                    if (result.failed  > 0) _Chip('${result.failed} failed',  const Color(0xFF991B1B), const Color(0xFFFEE2E2)),
                    if (result.skipped > 0) _Chip('${result.skipped} skipped', AppTheme.inkSoft,       AppTheme.surface),
                  ],
                ),
                if (result.lastError != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                    child: Text(result.lastError!, style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B))),
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

class _Chip extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;
  const _Chip(this.label, this.textColor, this.bgColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
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
          const Text('Quick Templates',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
          const SizedBox(height: 12),
          ...List.generate(_kTemplates.length, (i) {
            final t = _kTemplates[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < _kTemplates.length - 1 ? 10 : 0),
              child: _TemplateTile(template: t, onTap: () => onSelect(t)),
            );
          }),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink)),
                  const SizedBox(height: 2),
                  Text(template.subject,
                      style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.copy_outlined, size: 14, color: AppTheme.inkHint),
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
              const Icon(Icons.access_time_outlined, size: 16, color: AppTheme.inkSoft),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Due Reminders',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
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
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              _WaFilterChip(label: '3 days', selected: _daysFilter == 3,
                  onTap: () { setState(() => _daysFilter = 3); _load(); }),
              const SizedBox(width: 8),
              _WaFilterChip(label: '7 days', selected: _daysFilter == 7,
                  onTap: () { setState(() => _daysFilter = 7); _load(); }),
              const SizedBox(width: 8),
              _WaFilterChip(label: 'Expired', selected: _daysFilter == 0,
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
            ...List.generate(_members.length, (i) => Padding(
              padding: EdgeInsets.only(bottom: i < _members.length - 1 ? 10 : 0),
              child: _DueMemberRow(
                member:     _members[i],
                daysFilter: _daysFilter,
                onSend:     () => _openWhatsApp(_members[i]),
              ),
            )),
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
    Color  badgeColor = AppTheme.statusWarn;
    Color  badgeBg    = AppTheme.statusWarnBg;

    if (daysFilter == 0) {
      badgeText  = 'Expired';
      badgeColor = AppTheme.statusDanger;
      badgeBg    = AppTheme.statusDangerBg;
    } else if (dateStr != null) {
      final expiry = DateTime.tryParse(dateStr);
      if (expiry != null) {
        final left = expiry.difference(DateTime.now()).inDays;
        badgeText  = left <= 0 ? 'Today' : '${left}d';
        badgeColor = left <= 1 ? AppTheme.statusDanger : AppTheme.statusWarn;
        badgeBg    = left <= 1 ? AppTheme.statusDangerBg : AppTheme.statusWarnBg;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.ink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'Unknown' : name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink),
                    overflow: TextOverflow.ellipsis),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
              ],
            ),
          ),
          if (badgeText.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
              child: Text(badgeText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor)),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: phone.isEmpty ? null : onSend,
            icon: const Icon(Icons.chat_outlined, size: 14),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── WhatsApp filter chip ──────────────────────────────────────────────────────
class _WaFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _WaFilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.ink : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppTheme.ink : AppTheme.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.inkSoft,
            )),
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
          Text('Recent Activity',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink)),
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
