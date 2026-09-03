import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/member_photo.dart';
import '../../../shared/widgets/responsive_content.dart';
import '../../../core/access/role_access.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../core/theme/app_icons.dart';

final _overdueProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  gymId,
) async {
  final today = DateTime.now();
  final todayStr =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final data = await Supabase.instance.client
      .from('members')
      .select(
        'id, first_name, last_name, avatar_url, next_payment_date, status, phone, email',
      )
      .eq('gym_id', gymId)
      .lte('next_payment_date', todayStr)
      .not('status', 'eq', 'cancelled')
      .order('next_payment_date', ascending: true);
  return (data as List).cast<Map<String, dynamic>>();
});

final _upcomingProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  gymId,
) async {
  final today = DateTime.now();
  final tomorrow = today.add(const Duration(days: 1));
  final tomorrowStr =
      '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
  final end = today.add(const Duration(days: 30));
  final endStr =
      '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
  final data = await Supabase.instance.client
      .from('members')
      .select(
        'id, first_name, last_name, avatar_url, next_payment_date, status, phone, email, memberships(status, membership_plans(price))',
      )
      .eq('gym_id', gymId)
      .gte('next_payment_date', tomorrowStr)
      .lte('next_payment_date', endStr)
      .not('status', 'eq', 'cancelled')
      .order('next_payment_date', ascending: true);
  return (data as List).cast<Map<String, dynamic>>();
});

class UpcomingPaymentsScreen extends ConsumerStatefulWidget {
  final bool initialTabExpiring;
  const UpcomingPaymentsScreen({super.key, this.initialTabExpiring = false});

  @override
  ConsumerState<UpcomingPaymentsScreen> createState() =>
      _UpcomingPaymentsScreenState();
}

class _UpcomingPaymentsScreenState
    extends ConsumerState<UpcomingPaymentsScreen> {
  final _overdueKey = GlobalKey();
  final _weekKey = GlobalKey();
  final _laterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialTabExpiring) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_weekKey));
    }
  }

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gymAsync = ref.watch(gymIdProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Payments Due'),
        leading: const BackButton(),
      ),
      body: ResponsiveContent(
        child: gymAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const ErrorState(what: 'renewals'),
          data: (gymId) => _RenewalQueue(
            gymId: gymId,
            overdueKey: _overdueKey,
            weekKey: _weekKey,
            laterKey: _laterKey,
          ),
        ),
      ),
    );
  }
}

// ── Payments due — every member who owes or is about to owe money, in one
// plain scroll grouped by how soon it matters. Opening from the dashboard's
// "due in 7 days" tile scrolls straight to that section.
class _RenewalQueue extends ConsumerWidget {
  final String gymId;
  final GlobalKey overdueKey;
  final GlobalKey weekKey;
  final GlobalKey laterKey;
  const _RenewalQueue({
    required this.gymId,
    required this.overdueKey,
    required this.weekKey,
    required this.laterKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(_overdueProvider(gymId));
    final upcomingAsync = ref.watch(_upcomingProvider(gymId));

    if (overdueAsync.isLoading || upcomingAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (overdueAsync.hasError || upcomingAsync.hasError) {
      return const ErrorState(what: 'renewals');
    }

    final overdue = overdueAsync.value ?? const [];
    final upcoming = upcomingAsync.value ?? const [];
    final week = upcoming.where((m) => _daysUntil(m) <= 7).toList();
    final later = upcoming.where((m) => _daysUntil(m) > 7).toList();

    if (overdue.isEmpty && week.isEmpty && later.isEmpty) {
      return const _EmptyState(
        icon: AppIcons.checkCircle,
        label: 'All caught up',
        sub: 'No overdue or upcoming renewals right now.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_overdueProvider(gymId));
        ref.invalidate(_upcomingProvider(gymId));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (overdue.isNotEmpty) ...[
            _SectionHeader(
              key: overdueKey,
              label: 'Overdue',
              count: overdue.length,
            ),
            for (final m in overdue) _DueRow(member: m, gymId: gymId),
          ],
          if (week.isNotEmpty) ...[
            _SectionHeader(
              key: weekKey,
              label: 'Due this week',
              count: week.length,
            ),
            for (final m in week) _DueRow(member: m, gymId: gymId),
          ],
          if (later.isNotEmpty) ...[
            _SectionHeader(
              key: laterKey,
              label: 'Due in the next 30 days',
              count: later.length,
            ),
            for (final m in later) _DueRow(member: m, gymId: gymId),
          ],
        ],
      ),
    );
  }

  static int _daysUntil(Map<String, dynamic> m) {
    final dateStr = m['next_payment_date'] as String?;
    if (dateStr == null) return 999;
    final due = DateTime.tryParse(dateStr);
    if (due == null) return 999;
    final today = DateTime.now();
    return DateTime(
      due.year,
      due.month,
      due.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Text(
        '$label ($count)',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.inkSoft,
        ),
      ),
    );
  }
}

// One row for both overdue and upcoming members — plain card, same shape as
// the Money > Dues list, so the whole app reads as one consistent style
// instead of a special screen with its own look.
class _DueRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final String gymId;
  const _DueRow({required this.member, required this.gymId});

  @override
  Widget build(BuildContext context) {
    final dateStr = member['next_payment_date'] as String?;
    final isFrozen = (member['status'] as String?) == 'frozen';
    int days = 0;
    if (dateStr != null) {
      final due = DateTime.tryParse(dateStr);
      if (due != null) {
        final today = DateTime.now();
        days = DateTime(
          due.year,
          due.month,
          due.day,
        ).difference(DateTime(today.year, today.month, today.day)).inDays;
      }
    }
    final overdue = days <= 0;
    final subtitle = overdue
        ? (days == 0
              ? 'Due today'
              : '${-days} day${-days == 1 ? '' : 's'} overdue')
        : 'Due in $days day${days == 1 ? '' : 's'}';
    final subtitleColor = overdue ? AppTheme.statusDanger : AppTheme.inkSoft;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isFrozen ? const Color(0xFFFFF5F5) : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/staff/members/${member['id']}'),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          _Avatar(member: member),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _name(member),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: AppTheme.ink,
                                        ),
                                      ),
                                    ),
                                    if (isFrozen) ...[
                                      const SizedBox(width: 6),
                                      _Badge(
                                        label: 'Hold',
                                        bg: const Color(0xFFFFCDD2),
                                        fg: const Color(0xFFB71C1C),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr != null
                                      ? '$subtitle · ${formatDateFromString(dateStr)}'
                                      : subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            AppIcons.chevronRight,
                            size: 16,
                            color: AppTheme.inkHint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if ((member['phone'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                _WhatsAppButton(member: member, isReminder: !overdue),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _CollectButton(
            memberId: member['id'] as String,
            memberName: _name(member),
            gymId: gymId,
            nextPaymentDate: dateStr,
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────────

String _name(Map<String, dynamic> m) {
  final first = m['first_name'] as String? ?? '';
  final last = m['last_name'] as String? ?? '';
  return '$first $last'.trim();
}

class _Avatar extends StatelessWidget {
  final Map<String, dynamic> member;
  const _Avatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final url = member['avatar_url'] as String?;
    final first = member['first_name'] as String? ?? '';
    final last = member['last_name'] as String? ?? '';
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        shape: BoxShape.circle,
      ),
      child: MemberPhoto(
        stored: url,
        fallback: _Initials(first: first, last: last),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String first;
  final String last;
  const _Initials({required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials(first, last),
        style: const TextStyle(
          color: AppTheme.ink,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isReminder;
  const _WhatsAppButton({required this.member, this.isReminder = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: () => _launch(context),
        icon: const Icon(AppIcons.chat, size: 16),
        tooltip: 'WhatsApp',
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFF25D366),
          backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final phone = member['phone'] as String? ?? '';
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final number = clean.startsWith('91') ? clean : '91$clean';
    final name = _name(member);
    final dateStr = member['next_payment_date'] as String?;
    final dueDateFormatted = dateStr != null
        ? formatDateFromString(dateStr)
        : '';

    final text = isReminder
        ? 'Hi $name, this is a reminder that your gym membership payment is due on $dueDateFormatted. Please make the payment at the earliest. Thank you!'
        : 'Hi $name, ';

    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }
}

class _CollectButton extends ConsumerWidget {
  final String memberId;
  final String memberName;
  final String gymId;
  final String? nextPaymentDate;
  const _CollectButton({
    required this.memberId,
    required this.memberName,
    required this.gymId,
    required this.nextPaymentDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(staffRoleProvider).valueOrNull;
    if (!RoleAccess.canRecordPayment(role)) return const SizedBox.shrink();
    return WideActionButton(
      label: isFuturePaymentDate(nextPaymentDate) ? 'Collect early' : 'Collect',
      onTap: () {
        showAdaptiveSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              QuickCollectSheet(memberId: memberId, memberName: memberName),
        ).then((success) {
          if (success == true) {
            ref.invalidate(_overdueProvider(gymId));
            ref.invalidate(_upcomingProvider(gymId));
          }
        });
      },
    );
  }
}

// ── Quick Collect Sheet ────────────────────────────────────────────────────────

class QuickCollectSheet extends ConsumerStatefulWidget {
  final String memberId;
  final String memberName;
  const QuickCollectSheet({
    super.key,
    required this.memberId,
    required this.memberName,
  });

  @override
  ConsumerState<QuickCollectSheet> createState() => QuickCollectSheetState();
}

class QuickCollectSheetState extends ConsumerState<QuickCollectSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;
  String? _planHint;
  String? _nextPaymentDate;
  double? _due;
  bool _partlyPaid = false;

  /// Balance still owed on a real open/partial invoice — 0 when there is no
  /// such invoice. Deliberately not `_due`, which falls back to the plan price
  /// when nothing is invoiced yet; that fallback would disable the duplicate
  /// guard on the very retry it exists to catch.
  double _outstanding = 0;

  static const _methods = [
    ('cash', 'Cash', AppIcons.payments),
    ('upi', 'UPI', AppIcons.qrCode),
    ('bank_transfer', 'Bank Transfer', AppIcons.accountBalance),
    ('card', 'Card', AppIcons.creditCard),
  ];

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _autofill() async {
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('members')
          .select(
            'next_payment_date, memberships(status, discount_amount, membership_plans(price, name))',
          )
          .eq('id', widget.memberId)
          .maybeSingle();
      if (data == null || !mounted) return;
      final memberships = (data['memberships'] as List?) ?? [];
      Map<String, dynamic>? active;
      for (final m in memberships) {
        if ((m as Map)['status'] == 'active') {
          active = m.cast<String, dynamic>();
          break;
        }
      }
      final plan = active?['membership_plans'] as Map?;
      final discount = (active?['discount_amount'] as num?)?.toDouble() ?? 0;
      double? finalPrice;
      setState(() {
        if (plan != null && plan['price'] != null) {
          final listPrice = (plan['price'] as num).toDouble();
          finalPrice = (listPrice - discount).clamp(0, listPrice);
          _amountCtrl.text = finalPrice!.toStringAsFixed(0);
          _planHint = discount > 0
              ? '${plan['name']} — $currencySymbol${listPrice.toStringAsFixed(0)} − $currencySymbol${discount.toStringAsFixed(0)} discount'
              : '${plan['name']} — $currencySymbol${listPrice.toStringAsFixed(0)}';
        }
        final npd = data['next_payment_date'] as String?;
        if (npd != null) _nextPaymentDate = npd.split('T').first;
      });

      // If there's already an open/partial invoice for this member, its
      // amount (not the plan price) is the real total owed — pre-fill the
      // remaining balance instead of the full plan price.
      final existing = await client
          .from('invoices')
          .select('id, amount')
          .eq('member_id', widget.memberId)
          .inFilter('status', ['open', 'partial'])
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      if (existing != null && mounted) {
        final invoiceAmount = (existing['amount'] as num).toDouble();
        final due = await invoiceDue(existing['id'] as String, invoiceAmount);
        if (!mounted) return;
        setState(() {
          _due = due;
          _partlyPaid = due < invoiceAmount;
          _outstanding = due;
          _amountCtrl.text = due.toStringAsFixed(0);
        });
      } else {
        _due = finalPrice;
        _outstanding = 0;
      }
    } catch (e) {
      debugPrint('[GymCRM] Autofill error: $e');
    }
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    // Only a genuine duplicate is worth stopping. If the member still owes
    // money on an open bill, a second collection today is the rest of that
    // bill, not an accidental re-tap — warning there told owners a normal
    // instalment looked like a mistake.
    final prior = _outstanding > 0
        ? null
        : await LocalPaymentGuard.check(widget.memberId);
    if (prior != null && mounted) {
      await showInfoDialog(
        context,
        title: 'Already collected today',
        body:
            '$currencySymbol${prior.amount.toStringAsFixed(0)} was already collected '
            'from ${widget.memberName} today at '
            '${prior.at.hour.toString().padLeft(2, '0')}:${prior.at.minute.toString().padLeft(2, '0')}. '
            'Refresh the member before collecting another renewal.',
        icon: AppIcons.history,
      );
      return;
    }

    if (!mounted) return;
    final early = await confirmEarlyRenewalIfNeeded(
      context,
      nextPaymentDate: _nextPaymentDate,
      settlingPartialInvoice: _partlyPaid,
    );
    if (!early) return;
    if (_nextPaymentDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renewal date is missing. Refresh and try again.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final ok = await confirmPartialIfNeeded(
      context,
      enteredAmount: amount,
      dueAmount: _due ?? amount,
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      await collectMembershipRenewal(
        memberId: widget.memberId,
        expectedNextPaymentDate: _nextPaymentDate!,
        amount: amount,
        method: _method,
        referenceNo: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      await LocalPaymentGuard.record(widget.memberId, amount);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment collected'),
            backgroundColor: AppTheme.statusActive,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(paymentFailureMessage(e))));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Collect Payment',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.activeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.person,
                    size: 16,
                    color: AppTheme.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.memberName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount ($currencySymbol) *',
                prefixText: '$currencySymbol ',
              ),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text(
                'Auto-filled: $_planHint',
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              partialPaymentHint,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment method',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.map((m) {
                final selected = _method == m.$1;
                return GestureDetector(
                  onTap: () => setState(() => _method = m.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.ink : AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppTheme.ink : AppTheme.border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m.$3,
                          size: 16,
                          color: selected ? Colors.white : AppTheme.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: switch (_method) {
                  'upi' => 'UPI Transaction ID (optional)',
                  'bank_transfer' => 'UTR number (optional)',
                  _ => 'Reference / Receipt no. (optional)',
                },
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Collect Payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  const _EmptyState({
    required this.icon,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppTheme.inkHint),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(color: AppTheme.inkHint, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
