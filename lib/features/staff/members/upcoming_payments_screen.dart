import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/billing/collect_payment.dart';
import '../../../core/billing/local_payment_guard.dart';
import '../../../core/billing/payment_dates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/redesign.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_icons.dart';
import '../../../l10n/app_localizations.dart';

// The payments-due list lives in payments_due_screen.dart; this file now only
// holds the Quick Collect sheet that several screens open.

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
  DateTime _paidAt = today;
  DateTime? _validTill;
  DateTime? _defaultTill;

  /// The open bill this collect settles, and whether it is an older bill
  /// (joining bill, old due, a balance already extended) rather than the
  /// current renewal — the server settles those without moving the plan.
  String? _invoiceId;
  bool _settlingOldBill = false;

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
    // The valid-till hint switches wording when the amount won't clear the bill.
    _amountCtrl.addListener(() => setState(() {}));
    _autofill();
  }

  bool get _isPartial {
    final amount = double.tryParse(_amountCtrl.text.trim());
    return _due != null && amount != null && amount < _due!;
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
            'next_payment_date, billing_interval_months, memberships(status, discount_amount, billing_interval_days, membership_plans(price, name, billing_interval, billing_interval_months))',
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
        // A day pass never advances, so it gets no valid-till row.
        if (active?['billing_interval_days'] == null) {
          _defaultTill = defaultValidTill(
            _nextPaymentDate,
            renewalMonths(
              plan,
              (data['billing_interval_months'] as num?)?.toInt(),
            ),
          );
          _validTill = _defaultTill;
        }
      });

      // If there's already an open/partial invoice for this member, its
      // amount (not the plan price) is the real total owed — pre-fill the
      // remaining balance instead of the full plan price.
      final openInvoices =
          (await client
                      .from('invoices')
                      .select('id, amount, due_at')
                      .eq('member_id', widget.memberId)
                      .inFilter('status', ['open', 'partial'])
                      .order('created_at', ascending: true)
                  as List)
              .cast<Map<String, dynamic>>();
      final existing = preferredCollectInvoice(openInvoices, _nextPaymentDate);
      if (existing != null && mounted) {
        final invoiceAmount = (existing['amount'] as num).toDouble();
        final due = await invoiceDue(existing['id'] as String, invoiceAmount);
        if (!mounted) return;
        final dueDate = (existing['due_at'] as String?)?.split('T').first;
        setState(() {
          _due = due;
          _partlyPaid = due < invoiceAmount;
          _outstanding = due;
          _amountCtrl.text = due.toStringAsFixed(0);
          _invoiceId = existing['id'] as String;
          _settlingOldBill = !billRenewsPlan(
            dueDate: dueDate,
            nextPaymentDate: _nextPaymentDate,
          );
          if (_settlingOldBill) {
            _validTill = null;
            _defaultTill = null;
          }
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
    final l = AppLocalizations.of(context);
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterAmount)));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterValidAmount)));
      return;
    }
    final dateError = paymentDatesError(
      _paidAt,
      _validTill,
      defaultTill: _defaultTill,
      l: l,
    );
    if (dateError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(dateError)));
      return;
    }

    // Only a genuine duplicate is worth stopping. If the member still owes
    // money on an open bill, a second collection today is the rest of that
    // bill, not an accidental re-tap — warning there told owners a normal
    // instalment looked like a mistake. A backdated entry is catch-up
    // bookkeeping, not a re-tap — the server's renewal-date check already
    // stops the same period being collected twice.
    final backdated = paidAtParam(_paidAt) != null;
    final prior = _outstanding > 0 || backdated
        ? null
        : await LocalPaymentGuard.check(widget.memberId);
    if (prior != null && mounted) {
      await showInfoDialog(
        context,
        title: l.alreadyCollectedTitle,
        body: l.alreadyCollectedBody(
          '$currencySymbol${prior.amount.toStringAsFixed(0)}',
          widget.memberName,
          '${prior.at.hour.toString().padLeft(2, '0')}:${prior.at.minute.toString().padLeft(2, '0')}',
        ),
        icon: AppIcons.history,
      );
      return;
    }

    if (!mounted) return;
    final early = await confirmEarlyRenewalIfNeeded(
      context,
      nextPaymentDate: _nextPaymentDate,
      settlingPartialInvoice: _partlyPaid || _settlingOldBill,
    );
    if (!early) return;
    if (_nextPaymentDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.renewalDateMissing)));
      }
      return;
    }

    if (!mounted) return;
    final ok = await confirmPartialIfNeeded(
      context,
      enteredAmount: amount,
      dueAmount: _due ?? amount,
    );
    if (!mounted) return;
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
        // Pin the bill shown on screen so the server settles exactly it.
        invoiceId: _invoiceId,
        paidAt: paidAtParam(_paidAt),
        validTill: validTillParam(_validTill, _defaultTill),
      );

      if (!backdated) await LocalPaymentGuard.record(widget.memberId, amount);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.paymentCollected),
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
    final l = AppLocalizations.of(context);
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
                  l.collectPaymentTitle,
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
                l.autoFilled(_planHint!),
                style: const TextStyle(fontSize: 11, color: AppTheme.inkSoft),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              l.partialPaymentHint,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 16),
            PaymentDatesFields(
              paidAt: _paidAt,
              onPaidAt: (d) => setState(() => _paidAt = d),
              validTill: _validTill,
              defaultTill: _defaultTill,
              onValidTill: (d) => setState(() => _validTill = d),
              partial: _isPartial,
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
                  : Text(l.collectPaymentTitle),
            ),
          ],
        ),
      ),
    );
  }
}
