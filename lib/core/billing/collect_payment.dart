import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/formatters.dart';

const partialPaymentHint = 'Partial payment available — you can collect less than the full amount due.';

/// If [enteredAmount] is less than [dueAmount], confirms the remaining
/// balance with the user before proceeding. Returns false if they cancel.
/// Used by every "Collect Payment" screen so the confirmation reads the same
/// everywhere.
Future<bool> confirmPartialIfNeeded(
  BuildContext context, {
  required double enteredAmount,
  required double dueAmount,
}) async {
  if (enteredAmount >= dueAmount) return true;
  final remaining = dueAmount - enteredAmount;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Partial payment'),
      content: Text(
        'Collecting $currencySymbol${enteredAmount.toStringAsFixed(0)} now. '
        '$currencySymbol${remaining.toStringAsFixed(0)} will remain due.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK, collect')),
      ],
    ),
  );
  return proceed ?? false;
}

/// Sum of succeeded payments already recorded against an invoice.
Future<double> paidSoFar(String invoiceId) async {
  final rows = await Supabase.instance.client
      .from('payments')
      .select('amount')
      .eq('invoice_id', invoiceId)
      .eq('status', 'succeeded');
  return (rows as List).fold<double>(0, (sum, p) => sum + ((p as Map)['amount'] as num).toDouble());
}

/// Remaining balance on an invoice, given its total amount.
Future<double> invoiceDue(String invoiceId, double invoiceAmount) async {
  final paid = await paidSoFar(invoiceId);
  return (invoiceAmount - paid).clamp(0, invoiceAmount);
}

/// Records a (possibly partial) payment against an invoice and sets the
/// invoice's status to 'paid' once fully covered, 'partial' otherwise.
/// Every "Collect Payment" screen calls this instead of inserting the
/// payment row and updating invoice status itself, so partial-payment
/// handling lives in exactly one place.
///
/// Returns true if this payment fully settled the invoice. Callers use this
/// to decide whether to advance next_payment_date — it must only advance
/// once per invoice (when it's fully paid), not once per partial
/// installment, or a bill paid in 3 parts would push renewal forward 3
/// cycles instead of 1.
Future<bool> recordInvoicePayment({
  required String invoiceId,
  required double amount,
  required String method,
  String? referenceNo,
  String? notes,
  required String? recordedBy,
}) async {
  final client = Supabase.instance.client;

  await client.from('payments').insert({
    'invoice_id': invoiceId,
    'amount': amount,
    'method': method,
    'status': 'succeeded',
    'reference_no': referenceNo,
    'notes': notes,
    'recorded_by': recordedBy,
  });

  final invoice = await client.from('invoices').select('amount').eq('id', invoiceId).single();
  final invoiceAmount = (invoice['amount'] as num).toDouble();
  final totalPaid = await paidSoFar(invoiceId);
  final isFullyPaid = totalPaid >= invoiceAmount;

  await client.from('invoices').update({
    'status': isFullyPaid ? 'paid' : 'partial',
    if (isFullyPaid) 'paid_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', invoiceId);

  return isFullyPaid;
}

/// Total outstanding balance across a member's unpaid/partially-paid invoices.
Future<double> memberDueAmount(String memberId) async {
  final invoices = await Supabase.instance.client
      .from('invoices')
      .select('id, amount, payments(amount, status)')
      .eq('member_id', memberId)
      .inFilter('status', ['open', 'partial']);

  double due = 0;
  for (final inv in (invoices as List)) {
    final amount = ((inv as Map)['amount'] as num).toDouble();
    final payments = (inv['payments'] as List?) ?? [];
    final paid = payments
        .where((p) => (p as Map)['status'] == 'succeeded')
        .fold<double>(0, (sum, p) => sum + ((p as Map)['amount'] as num).toDouble());
    due += (amount - paid).clamp(0, amount);
  }
  return due;
}
