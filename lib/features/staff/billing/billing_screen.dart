import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/invoice_pdf.dart';
import '../../../shared/models/invoice.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';

final _invoicesProvider = FutureProvider.family<List<Invoice>, String>((ref, status) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  var query = client
      .from('invoices')
      .select('*, members(first_name, last_name, email, phone)')
      .eq('gym_id', gymId);

  if (status != 'all') query = query.eq('status', status);

  final data = await query.order('created_at', ascending: false);
  return (data as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
});

final _plansProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  return await client
      .from('membership_plans')
      .select()
      .eq('gym_id', gymId)
      .order('price');
});

final _membersListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  return await client
      .from('members')
      .select('id, first_name, last_name')
      .eq('gym_id', gymId)
      .eq('status', 'active')
      .order('first_name');
});

// KPI provider: this-month collected + pending dues, with counts.
final _billingKpiProvider = FutureProvider<Map<String, num>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

  final paidFuture = client
      .from('invoices')
      .select('amount')
      .eq('gym_id', gymId)
      .eq('status', 'paid')
      .gte('paid_at', startOfMonth);
  final pendingFuture = client
      .from('invoices')
      .select('amount, member_id')
      .eq('gym_id', gymId)
      .eq('status', 'open');

  final results = await Future.wait([paidFuture, pendingFuture]);
  final paid = results[0] as List;
  final pending = results[1] as List;

  final revenue = paid.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
  final pendingAmt = pending.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
  final pendingMembers = pending.map((r) => r['member_id']).toSet().length;

  return {
    'revenue': revenue,
    'pending': pendingAmt,
    'paidCount': paid.length,
    'pendingMembers': pendingMembers,
  };
});

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  static const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final kpi = ref.watch(_billingKpiProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  const Text('Payments',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.ink, letterSpacing: -0.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _PlansTab(ref: ref)),
                    ),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.sell_outlined, size: 19, color: AppTheme.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showCreateInvoiceSheet(context),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Color(0x33DF5B34), blurRadius: 10, offset: Offset(0, 3))],
                      ),
                      child: const Icon(Icons.add, size: 21, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            kpi.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (data) => _buildKpiRow(data),
            ),
            Expanded(child: _InvoicesTab(ref: ref)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow(Map<String, num> data) {
    final month = _monthsShort[DateTime.now().month - 1];
    final pendingMembers = (data['pendingMembers'] ?? 0).toInt();
    final paidCount = (data['paidCount'] ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _KpiCard(
              label: 'Pending dues',
              value: formatCurrency((data['pending'] ?? 0).toDouble()),
              valueColor: AppTheme.statusDanger,
              sub: '$pendingMembers member${pendingMembers == 1 ? '' : 's'}',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              label: 'Collected · $month',
              value: formatCurrency((data['revenue'] ?? 0).toDouble()),
              valueColor: AppTheme.statusActive,
              sub: '$paidCount payment${paidCount == 1 ? '' : 's'}',
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateInvoiceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CreateInvoiceSheet(),
    ).then((_) => ref.invalidate(_invoicesProvider('all')));
  }
}

// ── KPI Card ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String sub;
  const _KpiCard({required this.label, required this.value, required this.valueColor, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.numberStyle(fontSize: 22, color: valueColor)),
          ),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 11.5, color: AppTheme.inkHint)),
        ],
      ),
    );
  }
}

// ── Invoices Tab ──────────────────────────────────────────────────────────────

class _InvoicesTab extends StatefulWidget {
  final WidgetRef ref;
  const _InvoicesTab({required this.ref});

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final invoices = widget.ref.watch(_invoicesProvider(_filter));
    final dueCount = widget.ref.watch(_invoicesProvider('open')).valueOrNull?.length;

    return Column(
      children: [
        // Underline tabs: Due (n) · Collected · All
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              _UnderlineTab(
                label: dueCount != null ? 'Due ($dueCount)' : 'Due',
                selected: _filter == 'open',
                onTap: () => setState(() => _filter = 'open'),
              ),
              const SizedBox(width: 20),
              _UnderlineTab(
                label: 'Collected',
                selected: _filter == 'paid',
                onTap: () => setState(() => _filter = 'paid'),
              ),
              const SizedBox(width: 20),
              _UnderlineTab(
                label: 'All',
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: invoices.when(
            loading: () => _BillingShimmer(),
            error: (e, _) => const Center(child: Text('Could not load invoices. Pull to retry.', style: TextStyle(color: AppTheme.inkSoft))),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text('No invoices', style: TextStyle(color: AppTheme.inkHint, fontSize: 14)),
                  )
                : RefreshIndicator(
                    color: AppTheme.accent,
                    onRefresh: () async => widget.ref.invalidate(_invoicesProvider(_filter)),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _InvoiceCard(
                        invoice: list[i],
                        onTap: () => context.push('/invoice/${list[i].id}'),
                        onMarkPaid: () => _showRecordPaymentSheet(context, list[i], widget.ref),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _showRecordPaymentSheet(BuildContext context, Invoice invoice, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RecordPaymentSheet(invoice: invoice),
    ).then((_) => ref.invalidate(_invoicesProvider(_filter)));
  }
}

// ── Invoice Card ──────────────────────────────────────────────────────────────

class _UnderlineTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _UnderlineTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppTheme.ink : AppTheme.inkHint,
            )),
          const SizedBox(height: 6),
          Container(
            height: 2.5,
            width: 34,
            decoration: BoxDecoration(
              color: selected ? AppTheme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;
  final VoidCallback onMarkPaid;
  const _InvoiceCard({required this.invoice, required this.onTap, required this.onMarkPaid});

  String get _subtitle {
    final parts = <String>[];
    if (invoice.description != null && invoice.description!.isNotEmpty) {
      parts.add(invoice.description!);
    }
    if (invoice.status == 'paid') {
      if (invoice.paidAt != null) parts.add('Paid ${formatDateFromString(invoice.paidAt)}');
    } else if (invoice.dueAt != null) {
      final due = DateTime.tryParse(invoice.dueAt!);
      if (due != null) {
        final days = due.difference(DateTime.now()).inDays;
        if (days < 0) {
          parts.add('${days.abs()} day${days == -1 ? '' : 's'} overdue');
        } else if (days == 0) {
          parts.add('due today');
        } else if (days == 1) {
          parts.add('due tomorrow');
        } else {
          parts.add('due in $days days');
        }
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final open = invoice.status == 'open';
    final overdue = open &&
        invoice.dueAt != null &&
        (DateTime.tryParse(invoice.dueAt!)?.isBefore(DateTime.now()) ?? false);
    final name = invoice.member?.fullName ?? 'Unknown';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            InitialsAvatar(name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppTheme.ink)),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: invoice.status == 'paid'
                            ? AppTheme.inkSoft
                            : overdue ? AppTheme.statusDanger : AppTheme.statusWarn,
                      )),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(invoice.amount),
                  style: AppTheme.numberStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (open)
                  PillButton(label: 'Collect', onTap: onMarkPaid)
                else
                  StatusPill.active(label: invoice.status[0].toUpperCase() + invoice.status.substring(1)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Record Payment Sheet ──────────────────────────────────────────────────────

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  final Invoice invoice;
  const _RecordPaymentSheet({required this.invoice});

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  bool _loading = false;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_outlined),
    ('upi', 'UPI', Icons.qr_code_outlined),
    ('bank_transfer', 'Bank Transfer', Icons.account_balance_outlined),
    ('card', 'Card', Icons.credit_card_outlined),
  ];

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // Advance a "YYYY-MM-DD" billing date by one calendar month (UTC, day-clamped).
  // Mirrors advancePaymentDate() in the web record-payment endpoint.
  String? _advancePaymentDate(String dateStr) {
    final segs = dateStr.split('T').first.split('-');
    if (segs.length < 3) return null;
    final day = int.tryParse(segs[2]);
    if (day == null || day < 1 || day > 31) return null;
    final base = DateTime.now().toUtc();
    var year = base.year;
    var month = base.month + 1; // 1-based next month
    if (month > 12) {
      month = 1;
      year += 1;
    }
    final daysInNext = DateTime.utc(year, month + 1, 0).day; // last day of `month`
    final billingDay = day < daysInNext ? day : daysInNext;
    return DateTime.utc(year, month, billingDay).toIso8601String().split('T').first;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      // currentUser can be null if the session expired mid-screen; guard it
      // so we show a clear message rather than a force-unwrap crash.
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please sign in again.')),
          );
          setState(() => _loading = false);
        }
        return;
      }
      final inv = widget.invoice;

      // 1. Record the payment in the ledger (matches the web flow).
      await client.from('payments').insert({
        'invoice_id': inv.id,
        'amount': inv.amount,
        'method': _method,
        'status': 'succeeded',
        'reference_no': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'recorded_by': userId,
      });

      // 2. Mark the invoice paid.
      await client.from('invoices').update({
        'status': 'paid',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', inv.id);

      // 3. Advance the member's next payment date and lift any freeze.
      final memberRow = await client
          .from('members')
          .select('next_payment_date, status')
          .eq('id', inv.memberId)
          .maybeSingle();
      if (memberRow != null) {
        final updates = <String, dynamic>{};
        final npd = memberRow['next_payment_date'] as String?;
        if (npd != null) {
          final advanced = _advancePaymentDate(npd);
          if (advanced != null) updates['next_payment_date'] = advanced;
        }
        if (memberRow['status'] == 'frozen' || memberRow['status'] == 'expired') updates['status'] = 'active';
        if (updates.isNotEmpty) {
          await client.from('members').update(updates).eq('id', inv.memberId);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded'), backgroundColor: AppTheme.statusActive),
        );
      }
    } catch (e) {
      debugPrint('[GymCRM] RecordPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to record payment. Please try again.')),
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodIndex = _methods.indexWhere((m) => m.$1 == _method).clamp(0, _methods.length - 1);
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: 'Record payment',
              subtitle: '${widget.invoice.member?.fullName ?? 'Member'}'
                  '${widget.invoice.description != null ? ' · ${widget.invoice.description}' : ''}',
            ),
            const SizedBox(height: 18),
            const FieldLabel('Amount'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: AppTheme.cardDecoration(),
              child: Text(formatCurrency(widget.invoice.amount),
                  style: AppTheme.numberStyle(fontSize: 22)),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Method'),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _methods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => PillChip(
                  label: _methods[i].$2,
                  selected: methodIndex == i,
                  onTap: () => setState(() => _method = _methods[i].$1),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FieldLabel(switch (_method) {
              'upi' => 'UPI transaction ID (optional)',
              'bank_transfer' => 'UTR number (optional)',
              _ => 'Reference / receipt no. (optional)',
            }),
            TextFormField(controller: _refCtrl),
            const SizedBox(height: 14),
            const FieldLabel('Notes (optional)'),
            TextFormField(controller: _notesCtrl, maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Record ${formatCurrency(widget.invoice.amount)}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create Invoice Sheet ──────────────────────────────────────────────────────

class _CreateInvoiceSheet extends ConsumerStatefulWidget {
  const _CreateInvoiceSheet();

  @override
  ConsumerState<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends ConsumerState<_CreateInvoiceSheet> {
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedMemberId;
  String? _dueAt;
  String? _planHint;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // Pre-fill amount from the member's active plan and due date from their
  // next_payment_date — mirrors the web create-invoice dialog.
  Future<void> _autofill(String memberId) async {
    try {
      final data = await Supabase.instance.client
          .from('members')
          .select('next_payment_date, memberships(status, membership_plans(price, name))')
          .eq('id', memberId)
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
      setState(() {
        if (plan != null && plan['price'] != null) {
          final price = (plan['price'] as num).toStringAsFixed(0);
          _amountCtrl.text = price;
          _planHint = '${plan['name']} — ₹$price';
        }
        final npd = data['next_payment_date'] as String?;
        if (npd != null) _dueAt = npd.split('T').first;
      });
    } catch (e) {
      debugPrint('[GymCRM] RecordPayment autofill error: $e');
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dueAt = picked.toIso8601String().split('T')[0]);
    }
  }

  Future<void> _create() async {
    if (_selectedMemberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a member first')));
      return;
    }
    if (_amountCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      final originalAmount = double.parse(_amountCtrl.text.trim());
      final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
      final finalAmount = (originalAmount - discountAmount).clamp(0.0, double.infinity);

      await client.from('invoices').insert({
        'member_id': _selectedMemberId,
        'gym_id': gymId,
        'original_amount': originalAmount,
        'discount_amount': discountAmount,
        'amount': finalAmount,
        if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
        if (_dueAt != null) 'due_at': _dueAt,
        'status': 'open',
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_membersListProvider);

    final originalAmount = double.tryParse(_amountCtrl.text.trim());
    final discountAmount = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
    final total = originalAmount == null ? null : (originalAmount - discountAmount).clamp(0.0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Create invoice'),
            const SizedBox(height: 18),
            const FieldLabel('Member'),
            members.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (list) => DropdownButtonFormField<String>(
                value: _selectedMemberId,
                isExpanded: true,
                hint: const Text('Select member'),
                items: list.map((m) {
                  final name = '${m['first_name']} ${m['last_name']}';
                  return DropdownMenuItem(value: m['id'] as String, child: Text(name));
                }).toList(),
                onChanged: (v) {
                  setState(() => _selectedMemberId = v);
                  if (v != null) _autofill(v);
                },
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Amount'),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text('Auto-filled from active plan: $_planHint',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft)),
            ],
            const SizedBox(height: 14),
            const FieldLabel('Discount (optional)'),
            TextFormField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Description (optional)'),
            TextFormField(controller: _descCtrl),
            const SizedBox(height: 16),
            if (total != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: AppTheme.cardDecoration(),
                child: Column(children: [
                  Row(children: [
                    const Text('Amount', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                    const Spacer(),
                    Text(formatCurrency(originalAmount!), style: const TextStyle(fontSize: 13, color: AppTheme.ink)),
                  ]),
                  if (discountAmount > 0) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Discount', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                      const Spacer(),
                      Text('− ${formatCurrency(discountAmount)}', style: const TextStyle(fontSize: 13, color: AppTheme.statusActive)),
                    ]),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                    const Spacer(),
                    Text(formatCurrency(total), style: AppTheme.numberStyle(fontSize: 16)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            const FieldLabel('Due date (optional)'),
            InkWell(
              onTap: _pickDueDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: InputDecoration(
                  suffixIcon: _dueAt != null
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _dueAt = null))
                      : const Icon(Icons.calendar_today_outlined, size: 16),
                ),
                child: Text(
                  _dueAt != null ? formatDateFromString(_dueAt) : 'Select date',
                  style: TextStyle(color: _dueAt != null ? AppTheme.ink : AppTheme.inkHint),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Create & send invoice'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── WhatsApp Invoice Button ───────────────────────────────────────────────────

class _WhatsAppInvoiceButton extends StatefulWidget {
  final Invoice invoice;
  const _WhatsAppInvoiceButton({required this.invoice});

  @override
  State<_WhatsAppInvoiceButton> createState() => _WhatsAppInvoiceButtonState();
}

class _WhatsAppInvoiceButtonState extends State<_WhatsAppInvoiceButton> {
  bool _loading = false;

  Future<void> _share() async {
    final phone = widget.invoice.member?.phone ?? '';
    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this member. Add it in their profile first.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;

      // 1. Fetch full invoice data (gym header needed for PDF)
      final data = await client
          .from('invoices')
          .select('*, members(first_name, last_name, email, phone), gyms(name, settings)')
          .eq('id', widget.invoice.id)
          .single();

      // 2. Generate PDF bytes
      final bytes  = await buildInvoicePdf(data);
      final invNum = invoiceNumber(widget.invoice.id, widget.invoice.createdAt);

      // 3. Upload to Supabase Storage (upsert so same invoice never duplicates)
      await client.storage.from('invoice-pdfs').uploadBinary(
        '${widget.invoice.id}.pdf',
        bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
      );

      // 4. Get public download URL
      final downloadUrl = client.storage
          .from('invoice-pdfs')
          .getPublicUrl('${widget.invoice.id}.pdf');

      // 5. Build WhatsApp message with download link
      final name   = widget.invoice.member?.fullName ?? 'there';
      final amount = formatCurrency(widget.invoice.amount);
      final text   = widget.invoice.status == 'paid'
          ? 'Hi $name, we have received your payment of $amount for invoice $invNum. Download your receipt here: $downloadUrl'
          : 'Hi $name, your invoice $invNum for $amount is due. Download it here: $downloadUrl';

      // 6. Open WhatsApp directly to member's chat
      final clean  = phone.replaceAll(RegExp(r'\D'), '');
      final number = clean.startsWith('91') ? clean : '91$clean';
      final uri    = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open WhatsApp')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate or upload invoice PDF')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _share,
        icon: _loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF25D366)),
              )
            : const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF25D366)),
        label: const Text('WhatsApp', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF25D366),
          side: const BorderSide(color: Color(0xFF25D366)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── Billing Shimmer ───────────────────────────────────────────────────────────

class _BillingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: const Color(0xFFE8E8E8),
        highlightColor: const Color(0xFFF5F5F5),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── Plans Tab ─────────────────────────────────────────────────────────────────

class _PlansTab extends StatelessWidget {
  final WidgetRef ref;
  const _PlansTab({required this.ref});

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(_plansProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Plans & pricing'), leading: const BackButton()),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async => ref.invalidate(_plansProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No plans yet', style: TextStyle(color: AppTheme.inkHint, fontSize: 14))),
                )
              else
                CardList(
                  children: list.map((plan) => _PlanCard(
                    plan: plan,
                    onEdit: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => _PlanFormSheet(plan: plan),
                    ).then((_) => ref.invalidate(_plansProvider)),
                  )).toList(),
                ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _PlanFormSheet(),
                ).then((_) => ref.invalidate(_plansProvider)),
                child: DottedBorderBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add, size: 18, color: AppTheme.accent),
                      SizedBox(width: 6),
                      Text('Add new plan',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onEdit;
  const _PlanCard({required this.plan, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final features = List<String>.from(plan['features'] ?? []);
    final interval = plan['billing_interval'] as String;
    final months = plan['billing_interval_months'] as int?;
    final intervalLabel = interval == 'custom' && months != null ? '$months months' : interval;
    final isActive = plan['is_active'] as bool? ?? true;

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppTheme.ink),
                      ),
                      const SizedBox(height: 3),
                      if (plan['max_classes'] != null)
                        Text('Up to ${plan['max_classes']} classes',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(children: [
                    Text(formatCurrency(plan['price'] as num), style: AppTheme.numberStyle(fontSize: 15)),
                    Text(' / $intervalLabel',
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                  ]),
                  const SizedBox(height: 4),
                  isActive ? StatusPill.active() : StatusPill.neutral(label: 'Inactive'),
                ]),
              ],
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check, size: 14, color: AppTheme.statusActive),
                        const SizedBox(width: 6),
                        Text(f, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Plan Form Sheet ───────────────────────────────────────────────────────────

class _PlanFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? plan;
  const _PlanFormSheet({this.plan});

  @override
  ConsumerState<_PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends ConsumerState<_PlanFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _maxClassesCtrl;
  late final TextEditingController _monthsCtrl;
  late final TextEditingController _featureCtrl;

  String _interval = 'monthly';
  bool _isActive = true;
  List<String> _features = [];
  bool _loading = false;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _priceCtrl = TextEditingController(text: p != null ? (p['price'] as num).toString() : '');
    _maxClassesCtrl = TextEditingController(text: p?['max_classes']?.toString() ?? '');
    _monthsCtrl = TextEditingController(text: p?['billing_interval_months']?.toString() ?? '');
    _featureCtrl = TextEditingController();
    _interval = p?['billing_interval'] as String? ?? 'monthly';
    _isActive = p?['is_active'] as bool? ?? true;
    _features = List<String>.from(p?['features'] ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _priceCtrl.dispose(); _maxClassesCtrl.dispose();
    _monthsCtrl.dispose(); _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final f = _featureCtrl.text.trim();
    if (f.isEmpty) return;
    setState(() { _features.add(f); _featureCtrl.clear(); });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'billing_interval': _interval,
        if (_interval == 'custom' && _monthsCtrl.text.trim().isNotEmpty)
          'billing_interval_months': int.parse(_monthsCtrl.text.trim()),
        'features': _features,
        if (_maxClassesCtrl.text.trim().isNotEmpty)
          'max_classes': int.parse(_maxClassesCtrl.text.trim()),
        'is_active': _isActive,
      };

      if (_isEdit) {
        await client.from('membership_plans').update(data).eq('id', widget.plan!['id']);
      } else {
        data['gym_id'] = await ref.read(gymIdProvider.future);
        await client.from('membership_plans').insert(data);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title: _isEdit ? 'Edit plan' : 'New plan'),
              const SizedBox(height: 18),
              const FieldLabel('Plan name'),
              TextFormField(
                controller: _nameCtrl,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Price'),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: '₹ '),
                      validator: (v) {
                        if (v?.trim().isEmpty ?? true) return 'Required';
                        if (double.tryParse(v!) == null) return 'Enter a valid price';
                        return null;
                      },
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Duration'),
                    DropdownButtonFormField<String>(
                      value: _interval,
                      items: const [
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                        DropdownMenuItem(value: 'biannual', child: Text('6 months')),
                        DropdownMenuItem(value: 'annual', child: Text('Yearly')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom…')),
                      ],
                      onChanged: (v) => setState(() => _interval = v!),
                    ),
                  ]),
                ),
              ]),
              if (_interval == 'custom') ...[
                const SizedBox(height: 14),
                const FieldLabel('Duration (months)'),
                TextFormField(
                  controller: _monthsCtrl,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (_interval != 'custom') return null;
                    if (v?.trim().isEmpty ?? true) return 'Required for custom interval';
                    if (int.tryParse(v!) == null || int.parse(v) < 1) return 'Enter a positive number';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 14),
              const FieldLabel('Max classes (blank = unlimited)'),
              TextFormField(controller: _maxClassesCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 18),
              const FieldLabel('Includes'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _featureCtrl,
                      decoration: const InputDecoration(hintText: 'Add a feature', isDense: true),
                      onFieldSubmitted: (_) => _addFeature(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(icon: Icons.add, onTap: _addFeature, bg: AppTheme.accentSoft, fg: AppTheme.accent),
                ],
              ),
              if (_features.isNotEmpty)
                CardList(
                  children: _features.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.check, size: 15, color: AppTheme.statusActive),
                      const SizedBox(width: 10),
                      Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13.5, color: AppTheme.ink))),
                      GestureDetector(
                        onTap: () => setState(() => _features.removeAt(e.key)),
                        child: const Icon(Icons.close, size: 16, color: AppTheme.inkHint),
                      ),
                    ]),
                  )).toList(),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeColor: AppTheme.accent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
