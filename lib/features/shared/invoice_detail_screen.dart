import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/invoice_pdf.dart';
import '../../core/utils/platform_info.dart' as platform_info;
import '../../shared/widgets/redesign.dart';

final _invoiceDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final data = await Supabase.instance.client
      .from('invoices')
      .select('*, members(first_name, last_name, email), gyms(name, settings), payments(method, status)')
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
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppTheme.ink,
        title: async.maybeWhen(
          data: (inv) => Text(invoiceNumber(inv['id'] as String, inv['created_at'] as String)),
          orElse: () => const Text('Invoice'),
        ),
        actions: [
          if (async.hasValue) ...[
            if (!kIsWeb && !platform_info.isIOS)
              IconButton(
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _downloadPdf(context, async.value!),
                tooltip: 'Download PDF',
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _sharePdf(async.value!),
              tooltip: 'Share as PDF',
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppTheme.inkSoft))),
        data: (inv) => _InvoiceBody(invoice: inv),
      ),
    );
  }

  Future<void> _sharePdf(Map<String, dynamic> inv) async {
    final invNum = invoiceNumber(inv['id'] as String, inv['created_at'] as String);
    final bytes  = await buildInvoicePdf(inv);
    await Printing.sharePdf(bytes: bytes, filename: '$invNum.pdf');
  }

  Future<void> _downloadPdf(BuildContext context, Map<String, dynamic> inv) async {
    final invNum = invoiceNumber(inv['id'] as String, inv['created_at'] as String);
    try {
      final bytes = await buildInvoicePdf(inv);
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = await File('${dir.path}/$invNum.pdf').writeAsBytes(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${file.path.split('/').last}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download the invoice. Please try again.')),
        );
      }
    }
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
    final invNum = invoiceNumber(invoice['id'] as String, invoice['created_at'] as String);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: AppTheme.cardDecoration(),
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
              status: status,
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
                          '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'.trim(),
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

            // Total (with optional discount breakdown)
            _Total(invoice: invoice),

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
            _Footer(invNumber: invNum, gymName: gym?['name'] as String? ?? 'the gym'),
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
  final String status;

  const _Header({
    required this.gymName,
    required this.address,
    required this.phone,
    required this.website,
    required this.invNumber,
    required this.status,
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
              _statusPill(status),
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
    final payments = (invoice['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final succeeded = payments.where((p) => p['status'] == 'succeeded');
    final method = succeeded.isEmpty ? null : succeeded.first['method'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          _MetaCell(
            label: 'Issue Date',
            value: formatDateFromString(invoice['created_at'] as String?),
          ),
          _MetaCell(
            label: 'Due Date',
            value: invoice['due_at'] != null
                ? formatDateFromString(invoice['due_at'] as String?)
                : '—',
          ),
          if (paidAt != null)
            _MetaCell(
              label: 'Paid On',
              value: formatDateFromString(paidAt),
              valueColor: AppTheme.statusActive,
            ),
          if (method != null && method.isNotEmpty)
            _MetaCell(
              label: 'Method',
              value: method[0].toUpperCase() + method.substring(1).replaceAll('_', ' '),
            ),
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
    final originalAmount = (invoice['original_amount'] as num?);
    final displayAmount = originalAmount ?? (invoice['amount'] as num);

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
                formatCurrency(displayAmount),
                style: AppTheme.numberStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
  final Map<String, dynamic> invoice;
  const _Total({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final amount = invoice['amount'] as num;
    final discountAmount = (invoice['discount_amount'] as num?) ?? 0;
    final hasDiscount = discountAmount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F8),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          if (hasDiscount) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'DISCOUNT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.statusActive),
                ),
                Text(
                  '− ${formatCurrency(discountAmount)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.statusActive),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 10),
          ],
          Row(
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
                style: AppTheme.numberStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final String invNumber;
  final String gymName;
  const _Footer({required this.invNumber, required this.gymName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        children: [
          Text('Thank you for being a member of $gymName',
            style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(invNumber, style: const TextStyle(fontSize: 10, color: AppTheme.inkHint)),
              const Text('Powered by GymCRM', style: TextStyle(fontSize: 10, color: AppTheme.inkHint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _statusPill(String status) => switch (status) {
      'paid'   => StatusPill.active(label: 'PAID'),
      'open'   => StatusPill.warn(label: 'PENDING'),
      'failed' => StatusPill.danger(label: 'FAILED'),
      'void'   => StatusPill.neutral(label: 'VOID'),
      _        => StatusPill.neutral(label: 'DRAFT'),
    };
