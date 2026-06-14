import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

final _invoiceDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final data = await Supabase.instance.client
      .from('invoices')
      .select('*, members(first_name, last_name, email), gyms(name, settings)')
      .eq('id', id)
      .single();
  return data;
});

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_invoiceDetailProvider(invoiceId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: async.maybeWhen(
          data: (inv) => Text(_invoiceNumber(inv['id'] as String, inv['created_at'] as String)),
          orElse: () => const Text('Invoice'),
        ),
        actions: [
          if (async.hasValue)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _share(async.value!),
              tooltip: 'Share',
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.inkSoft))),
        data: (inv) => _InvoiceBody(invoice: inv),
      ),
    );
  }

  void _share(Map<String, dynamic> inv) {
    final member = inv['members'] as Map<String, dynamic>?;
    final gym = inv['gyms'] as Map<String, dynamic>?;
    final invNum = _invoiceNumber(inv['id'] as String, inv['created_at'] as String);
    final memberName = member != null
        ? '${member['first_name']} ${member['last_name']}'
        : 'Member';
    final amount = formatCurrency(inv['amount'] as num);
    final status = (inv['status'] as String).toUpperCase();
    final issued = formatDateFromString(inv['created_at'] as String?);

    Share.share(
      '${gym?['name'] ?? 'Gym'}\n'
      'Invoice: $invNum\n'
      'Issued: $issued\n'
      'Bill To: $memberName\n'
      '${inv['description'] != null ? 'Description: ${inv['description']}\n' : ''}'
      'Amount: $amount\n'
      'Status: $status',
      subject: 'Invoice $num',
    );
  }
}

// ── Invoice body ──────────────────────────────────────────────────────────────

class _InvoiceBody extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _InvoiceBody({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final gym = invoice['gyms'] as Map<String, dynamic>?;
    final member = invoice['members'] as Map<String, dynamic>?;
    final settings = (gym?['settings'] as Map<String, dynamic>?) ?? {};
    final status = invoice['status'] as String;
    final invNum = _invoiceNumber(invoice['id'] as String, invoice['created_at'] as String);
    final (statusBg, statusFg, statusLabel) = _statusInfo(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header band: gym name + invoice number + status
            _Header(
              gymName: gym?['name'] as String? ?? 'Gym',
              address: settings['address'] as String?,
              phone: settings['phone'] as String?,
              website: settings['website'] as String?,
              invNumber: invNum,
              statusBg: statusBg,
              statusFg: statusFg,
              statusLabel: statusLabel,
            ),

            // Meta row: issue date / due date / paid on
            _MetaRow(invoice: invoice),

            // Bill To
            _Section(
              label: 'Bill To',
              child: member != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${member['first_name']} ${member['last_name']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink),
                        ),
                        if ((member['email'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            member['email'] as String,
                            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                          ),
                        ],
                      ],
                    )
                  : const Text('—', style: TextStyle(color: AppTheme.inkHint)),
            ),

            // Line item
            _LineItems(invoice: invoice),

            // Total
            _Total(amount: invoice['amount'] as num),

            // Notes
            if ((invoice['notes'] as String?)?.isNotEmpty == true)
              _Section(
                label: 'Notes',
                child: Text(
                  invoice['notes'] as String,
                  style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.5),
                ),
              ),

            // Footer
            _Footer(invNumber: invNum),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String gymName;
  final String? address;
  final String? phone;
  final String? website;
  final String invNumber;
  final Color statusBg;
  final Color statusFg;
  final String statusLabel;

  const _Header({
    required this.gymName,
    required this.address,
    required this.phone,
    required this.website,
    required this.invNumber,
    required this.statusBg,
    required this.statusFg,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.ink, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: gym info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gymName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppTheme.ink,
                  ),
                ),
                if (address != null) ...[
                  const SizedBox(height: 4),
                  Text(address!, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ],
                if (phone != null) ...[
                  const SizedBox(height: 2),
                  Text(phone!, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ],
                if (website != null) ...[
                  const SizedBox(height: 2),
                  Text(website!, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: invoice label + number + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'INVOICE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppTheme.inkSoft,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                invNumber,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: statusFg,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Meta row ──────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _MetaRow({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final paidAt = invoice['paid_at'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _MetaCell(
            label: 'Issue Date',
            value: formatDateFromString(invoice['created_at'] as String?),
          ),
          const SizedBox(width: 24),
          _MetaCell(
            label: 'Due Date',
            value: invoice['due_at'] != null
                ? formatDateFromString(invoice['due_at'] as String?)
                : '—',
          ),
          if (paidAt != null) ...[
            const SizedBox(width: 24),
            _MetaCell(
              label: 'Paid On',
              value: formatDateFromString(paidAt),
              valueColor: AppTheme.statusActive,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _MetaCell({
    required this.label,
    required this.value,
    this.valueColor = AppTheme.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppTheme.inkHint,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppTheme.inkHint,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ── Line items ────────────────────────────────────────────────────────────────

class _LineItems extends StatelessWidget {
  final Map<String, dynamic> invoice;
  const _LineItems({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final description = (invoice['description'] as String?)?.isNotEmpty == true
        ? invoice['description'] as String
        : 'Membership fee';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DESCRIPTION',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppTheme.inkHint,
                  ),
                ),
              ),
              const Text(
                'AMOUNT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppTheme.inkHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  description,
                  style: const TextStyle(fontSize: 14, color: AppTheme.ink),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                formatCurrency(invoice['amount'] as num),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Total ─────────────────────────────────────────────────────────────────────

class _Total extends StatelessWidget {
  final num amount;
  const _Total({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'TOTAL DUE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppTheme.inkSoft,
            ),
          ),
          Text(
            formatCurrency(amount),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final String invNumber;
  const _Footer({required this.invNumber});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(invNumber, style: const TextStyle(fontSize: 10, color: AppTheme.inkHint)),
          const Text('Powered by GymCRM', style: TextStyle(fontSize: 10, color: AppTheme.inkHint)),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _invoiceNumber(String id, String createdAt) {
  final dt = DateTime.parse(createdAt);
  final month = '${dt.year}${dt.month.toString().padLeft(2, '0')}';
  final shortId = id.replaceAll('-', '').substring(0, 6).toUpperCase();
  return 'INV-$month-$shortId';
}

(Color, Color, String) _statusInfo(String status) => switch (status) {
      'paid'   => (const Color(0xFFE8F5E9), AppTheme.statusActive, 'PAID'),
      'open'   => (const Color(0xFFFFF3E0), AppTheme.statusWarn, 'PENDING'),
      'failed' => (const Color(0xFFFFEBEE), AppTheme.statusDanger, 'FAILED'),
      'void'   => (const Color(0xFFECEFF1), AppTheme.statusNeutral, 'VOID'),
      _        => (const Color(0xFFECEFF1), AppTheme.statusNeutral, 'DRAFT'),
    };
