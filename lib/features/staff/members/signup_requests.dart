import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';

/// Pending member-app signups from non-Indian numbers (no SMS OTP for them —
/// staff approve instead). RLS only returns rows to staff who can edit
/// members, so everyone else just gets an empty list and no banner.
final signupRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final gymId = await ref.watch(gymIdProvider.future);
      final data = await Supabase.instance.client
          .from('member_signup_requests')
          .select(
            'id, phone, created_at, member_id, '
            'members(first_name, last_name, user_id)',
          )
          .eq('gym_id', gymId)
          .eq('status', 'pending')
          .order('created_at');
      return (data as List).cast<Map<String, dynamic>>();
    });

/// "2 members want app access · Review" — sits above the members list.
class SignupRequestsBanner extends ConsumerWidget {
  const SignupRequestsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(signupRequestsProvider).valueOrNull ?? const [];
    if (requests.isEmpty) return const SizedBox.shrink();
    final n = requests.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showAdaptiveSheet(
            context: context,
            builder: (_) => const _SignupRequestsSheet(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.phone_iphone,
                  size: 20,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    n == 1
                        ? '1 member wants app access'
                        : '$n members want app access',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                const Text(
                  'Review',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignupRequestsSheet extends ConsumerStatefulWidget {
  const _SignupRequestsSheet();

  @override
  ConsumerState<_SignupRequestsSheet> createState() =>
      _SignupRequestsSheetState();
}

class _SignupRequestsSheetState extends ConsumerState<_SignupRequestsSheet> {
  final _busy = <String>{};

  Future<void> _decide(String id, {required bool approve}) async {
    setState(() => _busy.add(id));
    String? error;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'approve-member-signup',
        body: {'requestId': id, 'approve': approve},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) error = '${data['error']}';
    } on FunctionException catch (e) {
      final d = e.details;
      error = d is Map && d['error'] != null
          ? '${d['error']}'
          : 'Could not update the request. Please try again.';
    } catch (_) {
      error = 'Could not update the request. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy.remove(id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (approve
                  ? 'Approved. They can log in now.'
                  : 'Request rejected.'),
        ),
      ),
    );
    ref.invalidate(signupRequestsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(signupRequestsProvider).valueOrNull ?? const [];
    if (requests.isEmpty && _busy.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'App access requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Approve only if the number really belongs to this member.',
              style: TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 12),
            for (final r in requests) _row(r),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final m = r['members'] as Map<String, dynamic>? ?? const {};
    final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
    final reset = m['user_id'] != null;
    final busy = _busy.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Member' : name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  '${r['phone']} · ${reset ? 'password reset' : 'new signup'}'
                  ' · ${timeAgo(r['created_at'] as String?)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            TextButton(
              onPressed: () => _decide(id, approve: false),
              child: const Text('Reject'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              onPressed: () => _decide(id, approve: true),
              child: const Text('Approve'),
            ),
          ],
        ],
      ),
    );
  }
}
