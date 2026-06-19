import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/invoice.dart';
import '../../auth/providers/auth_provider.dart';

final _invoicesProvider = FutureProvider.family<List<Invoice>, String>((ref, status) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  var query = client
      .from('invoices')
      .select('*, members(first_name, last_name, email)')
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

// KPI provider: 30-day revenue + pending amount
final _billingKpiProvider = FutureProvider<Map<String, double>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

  final paidFuture = client
      .from('invoices')
      .select('amount')
      .eq('gym_id', gymId)
      .eq('status', 'paid')
      .gte('paid_at', thirtyDaysAgo.toIso8601String());
  final pendingFuture = client
      .from('invoices')
      .select('amount')
      .eq('gym_id', gymId)
      .eq('status', 'open');

  final results = await Future.wait([paidFuture, pendingFuture]);
  final paid = results[0] as List;
  final pending = results[1] as List;

  final revenue = paid.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
  final pendingAmt = pending.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));

  return {'revenue': revenue, 'pending': pendingAmt};
});

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kpi = ref.watch(_billingKpiProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateInvoiceSheet(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Invoices'), Tab(text: 'Plans')],
        ),
      ),
      body: Column(
        children: [
          // KPI row
          kpi.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => _buildKpiRow(data),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _InvoicesTab(ref: ref),
                _PlansTab(ref: ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(Map<String, double> data) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _KpiTile(
              label: '30-Day Revenue',
              value: formatCurrency(data['revenue'] ?? 0),
              icon: Icons.trending_up,
              iconColor: AppTheme.statusActive,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiTile(
              label: 'Pending Amount',
              value: formatCurrency(data['pending'] ?? 0),
              icon: Icons.schedule,
              iconColor: AppTheme.statusWarn,
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

// ── KPI Tile ──────────────────────────────────────────────────────────────────

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  const _KpiTile({required this.label, required this.value, required this.icon, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkHint, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final invoices = widget.ref.watch(_invoicesProvider(_filter));

    return Column(
      children: [
        // Filter chips bar
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'open', 'paid', 'failed', 'void'].map((f) {
                final selected = _filter == f;
                final label = f[0].toUpperCase() + f.substring(1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.ink : AppTheme.activeBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.white : AppTheme.inkSoft,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: invoices.when(
            loading: () => _BillingShimmer(),
            error: (e, _) => const Center(child: Text('Could not load invoices. Pull to retry.', style: TextStyle(color: Color(0xFF666666)))),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text('No invoices', style: TextStyle(color: AppTheme.inkHint, fontSize: 14)),
                  )
                : RefreshIndicator(
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

class _InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;
  final VoidCallback onMarkPaid;
  const _InvoiceCard({required this.invoice, required this.onTap, required this.onMarkPaid});

  static (Color, Color) _statusColors(String status) => switch (status) {
        'paid'    => (AppTheme.statusActiveBg, AppTheme.statusActive),
        'open'    => (AppTheme.statusWarnBg, AppTheme.statusWarn),
        'pending' => (AppTheme.statusWarnBg, AppTheme.statusWarn),
        'failed'  => (AppTheme.statusDangerBg, AppTheme.statusDanger),
        'overdue' => (AppTheme.statusDangerBg, AppTheme.statusDanger),
        _         => (AppTheme.statusNeutralBg, AppTheme.statusNeutral),
      };

  @override
  Widget build(BuildContext context) {
    final (statusBg, statusFg) = _statusColors(invoice.status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: member info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.member?.fullName ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        invoice.member?.email ?? '',
                        style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12),
                      ),
                      if (invoice.description != null && invoice.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(invoice.description!, style: const TextStyle(color: AppTheme.inkHint, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right: amount + status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrency(invoice.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        invoice.status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusFg),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Created ${formatDateFromString(invoice.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                ),
                if (invoice.dueAt != null)
                  Text(
                    'Due ${formatDateFromString(invoice.dueAt)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.inkHint),
                  ),
              ],
            ),
            if (invoice.status == 'open') ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: onMarkPaid,
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.zero,
                    backgroundColor: AppTheme.ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Record Payment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
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
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Record Payment',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            // Invoice summary card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.activeBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.invoice.member?.fullName ?? 'Member',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink),
                      ),
                      if (widget.invoice.description != null)
                        Text(widget.invoice.description!,
                            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                    ],
                  ),
                  Text(
                    formatCurrency(widget.invoice.amount),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Payment method',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                        Icon(m.$3, size: 16, color: selected ? Colors.white : AppTheme.inkSoft),
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
            const SizedBox(height: 16),
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
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Payment'),
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
  final _descCtrl = TextEditingController();
  String? _selectedMemberId;
  String? _dueAt;
  String? _planHint;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
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

      await client.from('invoices').insert({
        'member_id': _selectedMemberId,
        'gym_id': gymId,
        'amount': double.parse(_amountCtrl.text.trim()),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Create Invoice',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            members.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const SizedBox.shrink(),
              data: (list) => DropdownButtonFormField<String>(
                value: _selectedMemberId,
                decoration: const InputDecoration(
                  labelText: 'Member *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹) *',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            if (_planHint != null) ...[
              const SizedBox(height: 4),
              Text('Auto-filled from active plan: $_planHint',
                  style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft)),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDueDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Due date (optional)',
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
                  : const Text('Create Invoice'),
            ),
          ],
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
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(_plansProvider),
          child: list.isEmpty
              ? const Center(child: Text('No plans yet', style: TextStyle(color: AppTheme.inkHint, fontSize: 14)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _PlanCard(
                    plan: list[i],
                    onEdit: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => _PlanFormSheet(plan: list[i]),
                    ).then((_) => ref.invalidate(_plansProvider)),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _PlanFormSheet(),
        ).then((_) => ref.invalidate(_plansProvider)),
        backgroundColor: AppTheme.ink,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Plan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
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
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                formatCurrency(plan['price'] as num),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.ink),
                              ),
                              Text(
                                ' / $intervalLabel',
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppTheme.inkSoft),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        // Active / Inactive chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.statusActiveBg : AppTheme.statusNeutralBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isActive ? 'ACTIVE' : 'INACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isActive ? AppTheme.statusActive : AppTheme.statusNeutral,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_outlined, size: 16, color: AppTheme.inkHint),
                      ],
                    ),
                  ],
                ),
                if (plan['max_classes'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Up to ${plan['max_classes']} classes',
                    style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                  ),
                ],
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.statusActive),
                            const SizedBox(width: 6),
                            Text(f, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdit ? 'Edit Plan' : 'New Plan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.ink),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Plan name *'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price (₹) *', prefixIcon: Icon(Icons.currency_rupee)),
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'Required';
                  if (double.tryParse(v!) == null) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _interval,
                decoration: const InputDecoration(labelText: 'Billing interval'),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'quarterly', child: Text('Quarterly (3 months)')),
                  DropdownMenuItem(value: 'biannual', child: Text('6 Months')),
                  DropdownMenuItem(value: 'annual', child: Text('Yearly')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom…')),
                ],
                onChanged: (v) => setState(() => _interval = v!),
              ),
              if (_interval == 'custom') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _monthsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duration (months) *'),
                  validator: (v) {
                    if (_interval != 'custom') return null;
                    if (v?.trim().isEmpty ?? true) return 'Required for custom interval';
                    if (int.tryParse(v!) == null || int.parse(v) < 1) return 'Enter a positive number';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxClassesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max classes (blank = unlimited)'),
              ),
              const SizedBox(height: 16),
              const Text('Features',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.inkSoft)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _featureCtrl,
                      decoration: const InputDecoration(labelText: 'Add feature', isDense: true),
                      onFieldSubmitted: (_) => _addFeature(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _addFeature,
                    icon: const Icon(Icons.add_circle_outline, color: AppTheme.ink),
                  ),
                ],
              ),
              if (_features.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._features.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check, size: 14, color: AppTheme.statusActive),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13, color: AppTheme.ink))),
                          IconButton(
                            icon: const Icon(Icons.close, size: 14, color: AppTheme.inkHint),
                            onPressed: () => setState(() => _features.removeAt(e.key)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeColor: AppTheme.ink,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_isEdit ? 'Save Changes' : 'Create Plan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
