import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/access/role_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'sms_reminder_service.dart';

class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

const _kBatteryDismissed = 'battery_warning_dismissed';

class _ReminderSettingsScreenState extends ConsumerState<ReminderSettingsScreen> {
  bool _enabled = false;
  int _daysBefore = 3;
  late TextEditingController _templateCtrl;
  bool _welcomeEnabled = false;
  late TextEditingController _welcomeCtrl;
  bool _loading = true;
  bool _sending = false;
  bool _batteryUnrestricted = true;
  SharedPreferences? _prefs;

  static const _daysOptions = [1, 2, 3, 5, 7, 14];

  @override
  void initState() {
    super.initState();
    _templateCtrl = TextEditingController();
    _welcomeCtrl = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    _welcomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prefs = prefs;
      _enabled = prefs.getBool(kSmsEnabled) ?? false;
      _daysBefore = prefs.getInt(kSmsDaysBefore) ?? 3;
      _templateCtrl.text = prefs.getString(kSmsTemplate) ?? kSmsDefaultTemplate;
      _welcomeEnabled = prefs.getBool(kWelcomeEnabled) ?? false;
      _welcomeCtrl.text = prefs.getString(kWelcomeTemplate) ?? kWelcomeDefaultTemplate;
      _batteryUnrestricted = prefs.getBool(_kBatteryDismissed) ?? false;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    await _prefs?.setBool(kSmsEnabled, _enabled);
    await _prefs?.setInt(kSmsDaysBefore, _daysBefore);
    await _prefs?.setString(kSmsTemplate, _templateCtrl.text.trim().isEmpty
        ? kSmsDefaultTemplate
        : _templateCtrl.text.trim());
    await _prefs?.setBool(kWelcomeEnabled, _welcomeEnabled);
    await _prefs?.setString(kWelcomeTemplate, _welcomeCtrl.text.trim().isEmpty
        ? kWelcomeDefaultTemplate
        : _welcomeCtrl.text.trim());
  }

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
          'Android blocked the SMS permission because this app was installed manually (not from the Play Store).\n\n'
          'To fix this:\n'
          '1. Go to Settings → Apps → gym_crm\n'
          '2. Tap the ⋮ menu (top-right)\n'
          '3. Tap "Allow restricted settings"\n'
          '4. Come back and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      final granted = await _ensureSmsPermission();
      if (!granted) return;
    }
    setState(() => _enabled = value);
    await _saveSettings();
    await SmsReminderService.setNativeRemindersEnabled(value);
    _showSnack(value ? 'Automatic SMS reminders enabled' : 'Automatic SMS reminders disabled');
  }

  Future<void> _sendNow() async {
    final granted = await _ensureSmsPermission();
    if (!granted) return;

    await _saveSettings();
    setState(() => _sending = true);

    try {
      final count = await SmsReminderService.sendManualReminders();
      if (mounted) {
        _showSnack(count == 0
            ? 'No members with expiring memberships found for the selected window.'
            : 'Sent $count reminder${count == 1 ? '' : 's'} successfully.');
      }
    } catch (e) {
      if (mounted) _showSnack('Error sending reminders: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resetTemplate() async {
    setState(() => _templateCtrl.text = kSmsDefaultTemplate);
    await _saveSettings();
  }

  Future<void> _toggleWelcome(bool value) async {
    if (value) {
      final granted = await _ensureSmsPermission();
      if (!granted) return;
    }
    setState(() => _welcomeEnabled = value);
    await _saveSettings();
    _showSnack(value ? 'Welcome SMS enabled' : 'Welcome SMS disabled');
  }

  Future<void> _resetWelcomeTemplate() async {
    setState(() => _welcomeCtrl.text = kWelcomeDefaultTemplate);
    await _saveSettings();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(staffRoleProvider).valueOrNull;
    if (!RoleAccess.canSeeReminders(role)) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('SMS Reminders')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: AppTheme.inkHint),
                SizedBox(height: 16),
                Text(
                  'Manager access required',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.ink),
                ),
                SizedBox(height: 8),
                Text(
                  'Only managers and owners can configure SMS reminders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.inkHint, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('SMS Reminders'),
        leading: const BackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoBanner(),
                  if (!_batteryUnrestricted) ...[
                    const SizedBox(height: 16),
                    _BatteryWarningCard(onDismiss: () async {
                      await _prefs?.setBool(_kBatteryDismissed, true);
                      setState(() => _batteryUnrestricted = true);
                    }),
                  ],
                  const SizedBox(height: 16),
                  _AutoReminderCard(
                    enabled: _enabled,
                    daysBefore: _daysBefore,
                    daysOptions: _daysOptions,
                    onToggle: _toggleEnabled,
                    onDaysChanged: (v) async {
                      setState(() => _daysBefore = v!);
                      await _saveSettings();
                    },
                  ),
                  const SizedBox(height: 16),
                  _TemplateCard(
                    controller: _templateCtrl,
                    onReset: _resetTemplate,
                    onChanged: (_) => _saveSettings(),
                  ),
                  const SizedBox(height: 16),
                  _WelcomeSmsCard(
                    enabled: _welcomeEnabled,
                    controller: _welcomeCtrl,
                    onToggle: _toggleWelcome,
                    onReset: _resetWelcomeTemplate,
                    onChanged: (_) => _saveSettings(),
                  ),
                  const SizedBox(height: 16),
                  _ManualSendCard(
                    daysBefore: _daysBefore,
                    sending: _sending,
                    onSend: _sendNow,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ─── Info banner ───────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
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
          Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'SMS reminders are sent from your own SIM card — no third-party service required. '
              'Members receive the SMS from your phone number.\n\n'
              'On Android 12+: if permission is blocked, go to Settings → Apps → gym_crm → ⋮ → Allow restricted settings, then try again.',
              style: TextStyle(fontSize: 13, color: AppTheme.ink, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Auto reminder card ────────────────────────────────────────────────────────
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
          const Text(
            'Automatic Reminders',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Runs daily in the background — no action needed.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enable auto reminders',
                style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const Divider(height: 24),
            const Text(
              'Send reminder',
              style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: daysBefore,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              ),
              items: daysOptions
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text('$d day${d == 1 ? '' : 's'} before expiry'),
                      ))
                  .toList(),
              onChanged: onDaysChanged,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Template card ─────────────────────────────────────────────────────────────
class _TemplateCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onReset;
  final ValueChanged<String> onChanged;

  const _TemplateCard({
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
              const Text(
                'Message Template',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
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
          const SizedBox(height: 8),
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
          _PlaceholderChip(label: '{name}', hint: "Member's first name"),
          const SizedBox(height: 6),
          _PlaceholderChip(label: '{days}', hint: 'Days before expiry'),
        ],
      ),
    );
  }
}

class _PlaceholderChip extends StatelessWidget {
  final String label;
  final String hint;
  const _PlaceholderChip({required this.label, required this.hint});

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
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(hint, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ],
    );
  }
}

// ─── Battery warning card ──────────────────────────────────────────────────────
class _BatteryWarningCard extends StatelessWidget {
  final VoidCallback onDismiss;
  const _BatteryWarningCard({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFFFF8F00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allow background activity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'To ensure daily SMS reminders run reliably:\n\n'
                  '• Settings → Apps → GymCRM → Battery → Allow background activity\n'
                  '• Or: Settings → Battery → App battery management → GymCRM → No restrictions',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => openAppSettings(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Open Settings',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onDismiss,
                      child: const Text(
                        'Done',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5D4037)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Welcome SMS card ──────────────────────────────────────────────────────────
class _WelcomeSmsCard extends StatelessWidget {
  final bool enabled;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReset;
  final ValueChanged<String> onChanged;

  const _WelcomeSmsCard({
    required this.enabled,
    required this.controller,
    required this.onToggle,
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
          const Text(
            'Welcome SMS',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Automatically sent when a new member is added by staff.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Send welcome message',
                style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500),
              ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Message Template',
                  style: TextStyle(fontSize: 14, color: AppTheme.ink, fontWeight: FontWeight.w500),
                ),
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
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: 'Type your welcome message...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Text(
                    '{name}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text("Member's first name", style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Manual send card ──────────────────────────────────────────────────────────
class _ManualSendCard extends StatelessWidget {
  final int daysBefore;
  final bool sending;
  final VoidCallback onSend;

  const _ManualSendCard({
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
          const Text(
            'Send Now',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manually send SMS to members whose membership expires in $daysBefore day${daysBefore == 1 ? '' : 's'}.',
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
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
