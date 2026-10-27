import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/responsive_content.dart';
import 'paywall_screen.dart' show kBillingApiBase, kSupportWhatsAppUrl;

/// The app's own cancel flow (Android / web — iPhone cancels through Apple):
/// reason → save offer → confirm, plus "keep my subscription" once a cancel
/// is scheduled. Talks to gym-crm /api/billing/mobile/subscription, which
/// updates the Dodo subscription and logs the reason.
///
/// Pops `true` when anything changed, so the caller refreshes the paywall.
class CancelSubscriptionScreen extends StatefulWidget {
  const CancelSubscriptionScreen({super.key});

  @override
  State<CancelSubscriptionScreen> createState() =>
      _CancelSubscriptionScreenState();
}

enum _Step { reason, offer, confirm }

const _reasons = [
  ('too_expensive', "It's too expensive"),
  ('not_using', "I'm not using it enough"),
  ('missing_feature', 'A feature I need is missing'),
  ('switching', 'Switching to another app'),
  ('closing_gym', 'Closing or selling my gym'),
  ('other', 'Something else'),
];

class _CancelSubscriptionScreenState extends State<CancelSubscriptionScreen> {
  Map<String, dynamic>? _status;
  String? _loadError;
  bool _busy = false;
  _Step _step = _Step.reason;
  String? _reason;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? body,
  ]) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final uri = Uri.parse('$kBillingApiBase/api/billing/mobile/subscription');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final res = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(body));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Something went wrong.');
    }
    return data;
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final status = await _call('GET');
      if (mounted) setState(() => _status = status);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  /// Runs an action, shows [done], and closes the screen reporting a change.
  Future<void> _act(
    Map<String, dynamic> body,
    String Function(Map<String, dynamic>) done,
  ) async {
    setState(() => _busy = true);
    try {
      final result = await _call('POST', body);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(done(result))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? 'the end of your billing period' : formatDate(d);
  }

  bool get _offerFreeMonth =>
      _status?['free_month_available'] == true &&
      ((_status?['free_month_reasons'] as List?) ?? const []).contains(_reason);

  bool get _offerChat => _reason == 'missing_feature' || _reason == 'other';

  void _continueFromReason() {
    setState(
      () =>
          _step = (_offerFreeMonth || _offerChat) ? _Step.offer : _Step.confirm,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Cancel subscription'),
          leading: const BackButton(),
        ),
        body: ResponsiveContent(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: _body(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Column(
        children: [
          Text(_loadError!, style: _soft),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }
    final status = _status;
    if (status == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (status['subscribed'] != true) {
      return Text('You have no active subscription to cancel.', style: _soft);
    }
    final ends = _date(status['next_billing_date'] as String?);
    if (status['cancel_at_period_end'] == true) return _scheduled(ends);

    return switch (_step) {
      _Step.reason => _reasonStep(),
      _Step.offer => _offerStep(status),
      _Step.confirm => _confirmStep(ends),
    };
  }

  // ── Already cancelling: offer to undo ─────────────────────────────────────
  Widget _scheduled(String ends) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Your subscription is set to end', style: _title),
      const SizedBox(height: 8),
      Text(
        'You keep full access until $ends. After that your gym moves to the free plan — your members and data stay.',
        style: _soft,
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: _busy
            ? null
            : () => _act({
                'action': 'undo',
              }, (_) => 'Great — your subscription continues.'),
        child: const Text('Keep my subscription'),
      ),
    ],
  );

  // ── Step 1: why ───────────────────────────────────────────────────────────
  Widget _reasonStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Why do you want to cancel?', style: _title),
      const SizedBox(height: 6),
      Text('Your answer helps us make GymCRM better.', style: _soft),
      const SizedBox(height: 16),
      Container(
        decoration: AppTheme.cardDecoration(),
        child: RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v),
          child: Column(
            children: [
              for (final (value, label) in _reasons)
                RadioListTile<String>(value: value, title: Text(label)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _note,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Anything else you want to tell us? (optional)',
        ),
      ),
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: _reason == null ? null : _continueFromReason,
        child: const Text('Continue'),
      ),
    ],
  );

  // ── Step 2: save offer ────────────────────────────────────────────────────
  Widget _offerStep(Map<String, dynamic> status) {
    final nextBill = DateTime.tryParse(
      status['next_billing_date'] as String? ?? '',
    );
    final moved = nextBill == null
        ? null
        : formatDate(nextBill.add(const Duration(days: 30)).toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: _offerFreeMonth
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stay — your next month is on us', style: _title),
                    const SizedBox(height: 8),
                    Text(
                      moved == null
                          ? 'Your next payment moves one month later. Nothing is charged for that month.'
                          : 'Your next payment moves to $moved. Nothing is charged for that month.',
                      style: _soft,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              {'action': 'free_month', 'reason': _reason},
                              (r) =>
                                  'Done — your next payment is on ${_date(r['next_billing_date'] as String?)}.',
                            ),
                      child: const Text('Take my free month'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tell us what you need', style: _title),
                    const SizedBox(height: 8),
                    Text(
                      'We add features gyms ask for all the time. Message us — it might already be on the way.',
                      style: _soft,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => launchUrl(
                        Uri.parse(kSupportWhatsAppUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('Chat on WhatsApp'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = _Step.confirm),
          child: const Text('No thanks, continue to cancel'),
        ),
      ],
    );
  }

  // ── Step 3: confirm ───────────────────────────────────────────────────────
  Widget _confirmStep(String ends) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Cancel your subscription?', style: _title),
      const SizedBox(height: 8),
      Text(
        'You keep full access until $ends. You won\'t be charged again. Your members and data stay — you can subscribe again any time.',
        style: _soft,
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.error,
          foregroundColor: Colors.white,
        ),
        onPressed: _busy
            ? null
            : () => _act(
                {
                  'action': 'cancel',
                  'reason': _reason,
                  'note': _note.text.trim(),
                },
                (r) =>
                    'Subscription cancelled. Access continues until ${_date(r['ends_at'] as String?)}.',
              ),
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Cancel subscription'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Keep my subscription'),
      ),
    ],
  );

  static const _title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppTheme.ink,
  );
  static const _soft = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: AppTheme.inkSoft,
  );
}
