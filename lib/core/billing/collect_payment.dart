import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_events.dart';
import '../services/data_refresh.dart';
import '../utils/formatters.dart';
import '../../shared/widgets/redesign.dart';
import '../theme/app_icons.dart';

const partialPaymentHint =
    'Partial payment available — you can collect less than the full amount due.';

DateTime? paymentDate(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

bool isFuturePaymentDate(String? value) {
  final date = paymentDate(value);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return date?.isAfter(today) ?? false;
}

String paymentFailureMessage(Object error) =>
    error.toString().replaceFirst('Bad state: ', '');

/// Future renewals remain visible, but collecting them is an explicit advance
/// payment action instead of looking like an already-due balance.
Future<bool> confirmEarlyRenewalIfNeeded(
  BuildContext context, {
  required String? nextPaymentDate,
  bool settlingPartialInvoice = false,
}) async {
  // Finishing off a bill the member has already part-paid is not an advance,
  // even though the next renewal date is still in the future. Warning here
  // told owners they were collecting ahead of schedule while they were only
  // taking the rest of this month's fee.
  if (settlingPartialInvoice) return true;
  final date = paymentDate(nextPaymentDate);
  if (date == null || !isFuturePaymentDate(nextPaymentDate)) return true;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = date.difference(today).inDays;
  final formatted = MaterialLocalizations.of(context).formatMediumDate(date);
  final proceed = await showConfirmDialog(
    context,
    title: 'Collect renewal early?',
    body:
        'This renewal is due on $formatted (in $days day${days == 1 ? '' : 's'}). '
        'Continue only if you have received an advance payment.',
    confirmLabel: 'Collect advance',
    icon: AppIcons.schedule,
    danger: false,
  );
  return proceed ?? false;
}

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
  final proceed = await showConfirmDialog(
    context,
    title: 'Partial payment',
    body:
        'Collecting $currencySymbol${enteredAmount.toStringAsFixed(0)} now. '
        '$currencySymbol${remaining.toStringAsFixed(0)} will remain due.',
    confirmLabel: 'OK, collect',
    icon: AppIcons.payments,
    danger: false,
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
  return (rows as List).fold<double>(
    0,
    (sum, p) => sum + ((p as Map)['amount'] as num).toDouble(),
  );
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

  // The database locks the invoice and calculates the remaining balance in one
  // transaction. Never trust a client-side total for a financial write.
  final result =
      await client.rpc(
            'record_invoice_payment_atomic',
            params: {
              'p_invoice_id': invoiceId,
              'p_amount': amount,
              'p_method': method,
              'p_reference_no': referenceNo,
              'p_notes': notes,
            },
          )
          as Map;
  if (result['ok'] != true) {
    throw StateError(
      (result['error'] as String?) ?? 'Could not record payment.',
    );
  }
  unawaited(AppEvents.paymentRecorded());
  notifyGymDataChanged();
  return result['is_fully_paid'] == true;
}

/// Atomically collects the renewal currently shown on screen. The database
/// locks the member and compares [expectedNextPaymentDate] before writing, so
/// a second phone with stale data cannot collect the same renewal again.
Future<bool> collectMembershipRenewal({
  required String memberId,
  required String expectedNextPaymentDate,
  required double amount,
  required String method,
  String? referenceNo,
  String? notes,
  String? invoiceId,
}) async {
  final result =
      await Supabase.instance.client.rpc(
            'collect_membership_renewal_atomic',
            params: {
              'p_member_id': memberId,
              'p_expected_next_payment_date': expectedNextPaymentDate,
              'p_amount': amount,
              'p_method': method,
              'p_reference_no': referenceNo,
              'p_notes': notes,
              'p_invoice_id': invoiceId,
            },
          )
          as Map;
  if (result['ok'] != true) {
    throw StateError(
      (result['error'] as String?) ?? 'Could not collect this renewal.',
    );
  }
  unawaited(AppEvents.paymentRecorded());
  notifyGymDataChanged();
  return result['is_fully_paid'] == true;
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
        .fold<double>(
          0,
          (sum, p) => sum + ((p as Map)['amount'] as num).toDouble(),
        );
    due += (amount - paid).clamp(0, amount);
  }
  return due;
}
