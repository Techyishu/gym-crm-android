import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../members/registration_requests.dart';
import 'registration_share.dart';

/// Home card for member self-registration, so owners see it without digging
/// through Settings.
///   off: a promo — one tap turns it on and shows the QR to put on the desk.
///   on:  how many registrations are waiting, with Review and a QR shortcut.
class RegistrationHomeCard extends ConsumerStatefulWidget {
  final Map<String, dynamic>? gym;
  final RegistrationReviewer onReview;
  const RegistrationHomeCard({
    super.key,
    required this.gym,
    required this.onReview,
  });

  @override
  ConsumerState<RegistrationHomeCard> createState() =>
      _RegistrationHomeCardState();
}

class _RegistrationHomeCardState extends ConsumerState<RegistrationHomeCard> {
  bool _busy = false;

  Future<void> _showQr() async {
    if (_busy) return;
    setState(() => _busy = true);
    await enableAndShowRegistration(
      context,
      ref,
      gymName: '${widget.gym?['name'] ?? 'your gym'}',
    );
    if (mounted) setState(() => _busy = false);
  }

  void _review() => showRegistrationRequests(context, (p) async {
    await widget.onReview(p);
    ref.invalidate(registrationRequestsProvider);
  });

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    if (gym == null) return const SizedBox.shrink();
    final enabled = gym['registration_enabled'] == true;
    final waiting =
        ref.watch(registrationRequestsProvider).valueOrNull?.length ?? 0;

    final title = !enabled
        ? 'Let members register themselves'
        : waiting == 0
        ? 'Member registration is on'
        : waiting == 1
        ? '1 registration waiting'
        : '$waiting registrations waiting';
    final subtitle = !enabled
        ? 'Show a QR at your desk. Members fill in their own details, '
              'you just approve.'
        : waiting > 0
        ? 'Check the details, record payment and add them.'
        : 'Members scan your QR. You approve each one before they are added.';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.inkSoft,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                IconButton(
                  tooltip: 'Show QR',
                  onPressed: _busy ? null : _showQr,
                  icon: const Icon(Icons.qr_code_2, color: AppTheme.accent),
                ),
            ],
          ),
          // Buttons sit under the text, full width: beside it they squeezed
          // the title onto three lines on a phone.
          if (!enabled) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : _showQr,
              child: const Text('Show QR'),
            ),
          ] else if (waiting > 0) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _review,
              child: const Text('Review'),
            ),
          ],
        ],
      ),
    );
  }
}
