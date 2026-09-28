import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'advance_payment_date.dart';
import '../../l10n/app_localizations.dart';

// Editable "Payment date" and "Valid till" on the collect sheets. Both are
// pre-filled with what the server would do anyway, and are only sent to the
// RPC when staff actually change them — an untouched collect is the exact
// call older builds make.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime get today => dateOnly(DateTime.now());

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Plan length in months, with the same fallback chain the renewal RPC uses.
int renewalMonths(Map? plan, int? memberMonths) {
  final months = (plan?['billing_interval_months'] as num?)?.toInt();
  if (months != null && months > 0) return months;
  const byName = {'monthly': 1, 'quarterly': 3, 'biannual': 6, 'annual': 12};
  final named = byName[(plan?['billing_interval'] as String?)?.toLowerCase()];
  return named ?? (memberMonths != null && memberMonths > 0 ? memberMonths : 1);
}

/// What the server sets as the next due date when nothing is overridden:
/// the old due date plus one plan length.
DateTime? defaultValidTill(String? nextPaymentDate, int months) {
  if (nextPaymentDate == null) return null;
  final next = advancePaymentDate(nextPaymentDate, months: months);
  return next == null ? null : DateTime.parse(next);
}

/// RPC value for the payment date: null (server uses now) unless backdated.
/// Same test the server uses to decide whether a payment moves the plan date:
/// only the bill due on the member's current renewal date can renew them.
bool billRenewsPlan({
  required String? dueDate,
  required String? nextPaymentDate,
}) => dueDate != null && dueDate == nextPaymentDate;

/// Prefer the current renewal bill. With none, an overdue member is collected
/// as a renewal (null: nothing pinned, the server bills the renewal) — pinning
/// an old bill would settle it and leave them expired while the app says
/// "collected". An active member keeps the oldest-first old-balance behavior.
Map<String, dynamic>? preferredCollectInvoice(
  List<Map<String, dynamic>> invoices,
  String? nextPaymentDate,
) {
  if (invoices.isEmpty) return null;
  for (final invoice in invoices) {
    if (billRenewsPlan(
      dueDate: (invoice['due_at'] as String?)?.split('T').first,
      nextPaymentDate: nextPaymentDate,
    )) {
      return invoice;
    }
  }
  final npd = DateTime.tryParse(nextPaymentDate ?? '');
  if (npd != null && npd.isBefore(today)) return null;
  return invoices.first;
}

String? paidAtParam(DateTime paidAt) =>
    sameDay(paidAt, today) ? null : ymd(paidAt);

/// RPC value for valid till: null (server computes it) unless changed.
String? validTillParam(DateTime? validTill, DateTime? defaultTill) {
  if (validTill == null || defaultTill == null) return null;
  return sameDay(validTill, defaultTill) ? null : ymd(validTill);
}

/// Same rule the server enforces, checked before the network call.
///
/// An untouched valid-till (equal to [defaultTill]) is never sent to the
/// server, so it isn't checked: for a member lapsed more than one cycle the
/// default is itself in the past, and flagging it would block a normal collect.
///
/// Pass [l] for the user's language; without it the message is English.
String? paymentDatesError(
  DateTime paidAt,
  DateTime? validTill, {
  DateTime? defaultTill,
  AppLocalizations? l,
}) {
  if (paidAt.isAfter(today)) {
    return l?.paymentDateFuture ?? 'Payment date cannot be in the future';
  }
  final untouched =
      validTill != null && defaultTill != null && sameDay(validTill, defaultTill);
  if (validTill != null && !untouched && !validTill.isAfter(paidAt)) {
    return l?.validTillAfterPayment ??
        'Valid till must be after the payment date';
  }
  return null;
}

class PaymentDatesFields extends StatelessWidget {
  final DateTime paidAt;
  final ValueChanged<DateTime> onPaidAt;

  /// Null hides the valid-till row (a plain invoice, or a day pass).
  final DateTime? validTill;
  final DateTime? defaultTill;
  final ValueChanged<DateTime>? onValidTill;

  /// True when the entered amount won't clear the bill — the plan still
  /// extends now; the hint just says the rest stays as a due.
  final bool partial;

  const PaymentDatesFields({
    super.key,
    required this.paidAt,
    required this.onPaidAt,
    this.validTill,
    this.defaultTill,
    this.onValidTill,
    this.partial = false,
  });

  Future<void> _pickPaidAt(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      helpText: 'Payment date',
      initialDate: paidAt,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked != null) onPaidAt(dateOnly(picked));
  }

  Future<void> _pickValidTill(BuildContext context) async {
    final first = paidAt.add(const Duration(days: 1));
    final current = validTill!;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Valid till',
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(today.year + 5, today.month, today.day),
    );
    if (picked != null) onValidTill?.call(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final till = validTill;
    final changed =
        till != null && defaultTill != null && !sameDay(till, defaultTill!);
    final l = AppLocalizations.of(context);
    final error = paymentDatesError(
      paidAt,
      till,
      defaultTill: defaultTill,
      l: l,
    );
    // A date already gone can't reactivate anyone: the server leaves the
    // member expired, so say so instead of showing a hopeful "valid till".
    final lapsed = error == null && till != null && till.isBefore(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'Payment date',
                value: sameDay(paidAt, today) ? 'Today' : formatDate(paidAt),
                onTap: () => _pickPaidAt(context),
              ),
            ),
            if (till != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _DateTile(
                  label: 'Valid till',
                  value: formatDate(till),
                  onTap: () => _pickValidTill(context),
                ),
              ),
            ],
          ],
        ),
        if (till != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                // Shown inline, not only as a snackbar: a snackbar opens
                // behind this sheet, so Collect would look like it did nothing.
                child: Text(
                  error ??
                      (lapsed
                          ? l.validTillLapsed
                          : partial
                          ? l.validTillPartial(formatDate(till))
                          : l.validTillFull(formatDate(till))),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: error != null || lapsed ? FontWeight.w600 : null,
                    color: error != null || lapsed
                        ? AppTheme.statusDanger
                        : AppTheme.inkSoft,
                  ),
                ),
              ),
              if (changed)
                GestureDetector(
                  onTap: () => onValidTill?.call(defaultTill!),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value. Change',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(AppIcons.event, size: 18, color: AppTheme.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
