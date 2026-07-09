import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

final _memberInvoicesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser!;

  final member = await client.from('members').select('id').eq('user_id', user.id).maybeSingle();
  if (member == null) return [];

  return await client
      .from('invoices')
      .select()
      .eq('member_id', member['id'])
      .order('created_at', ascending: false);
});

class MemberBillingScreen extends ConsumerWidget {
  const MemberBillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(_memberInvoicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Billing')),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.textSecondary),
                    SizedBox(height: 16),
                    Text('No invoices yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(_memberInvoicesProvider),
                child: Column(
                  children: [
                    _buildSummary(list),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => _InvoiceItem(
                          invoice: list[i],
                          onTap: () => ctx.push('/invoice/${list[i]['id']}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSummary(List<Map<String, dynamic>> invoices) {
    final totalPaid = invoices.where((i) => i['status'] == 'paid').fold<double>(0, (s, i) => s + (i['amount'] as num).toDouble());
    final totalDue = invoices.where((i) => i['status'] == 'open').fold<double>(0, (s, i) => s + (i['amount'] as num).toDouble());

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _SummaryTile(label: 'Total Paid', value: formatCurrency(totalPaid), color: AppTheme.primary)),
          const SizedBox(width: 12),
          Expanded(child: _SummaryTile(label: 'Amount Due', value: formatCurrency(totalDue), color: AppTheme.warning)),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
        ],
      ),
    );
  }
}

class _InvoiceItem extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;
  const _InvoiceItem({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] as String;
    final statusColors = {
      'open': (const Color(0xFFF4E8CD), AppTheme.warning),
      'paid': (AppTheme.primaryLight, AppTheme.primary),
      'failed': (const Color(0xFFF8DFD7), AppTheme.error),
      'void': (const Color(0xFFE9E6DD), AppTheme.textSecondary),
    };
    final sc = statusColors[status] ?? (const Color(0xFFE9E6DD), AppTheme.textSecondary);

    return GestureDetector(
      onTap: onTap,
      child: Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDateFromString(invoice['created_at'] as String?), style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                if (invoice['due_at'] != null) Text('Due ${formatDateFromString(invoice['due_at'] as String?)}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
            Row(
              children: [
                Text(formatCurrency(invoice['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: sc.$1, borderRadius: BorderRadius.circular(6)),
                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sc.$2)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}
