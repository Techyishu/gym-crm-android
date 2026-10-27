import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access/gym_permissions.dart';
import '../../core/services/data_refresh.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/l10n.dart';
import '../../shared/widgets/adaptive_sheet.dart';
import '../../shared/widgets/redesign.dart';

/// Void or delete an invoice, offering only what the database will accept
/// (see supabase/migrations/20261027120000_void_delete_invoice.sql):
///  * void   — open/partial invoices; keeps the number, drops it from dues.
///  * delete — an unpaid invoice, or a paid one only when another paid invoice
///             for the same bill stays behind (a true duplicate).
/// A paid invoice that is the only bill can be neither; the owner is told why.
///
/// Returns 'void', 'delete', or null when nothing changed.
Future<String?> removeInvoice(BuildContext context, String invoiceId) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final canEdit = container.read(
    gymPermissionProvider((GymModule.payments, GymAction.edit)),
  );
  final canDelete = container.read(
    gymPermissionProvider((GymModule.payments, GymAction.delete)),
  );
  final client = Supabase.instance.client;

  try {
    final inv = await client
        .from('invoices')
        .select('status, payments(amount, status)')
        .eq('id', invoiceId)
        .single();
    final status = inv['status'] as String? ?? '';
    final payments = (inv['payments'] as List?) ?? const [];
    final received = payments
        .where((p) => p['status'] == 'succeeded')
        .fold<double>(0, (s, p) => s + ((p['amount'] as num?) ?? 0).toDouble());
    final hasMoney =
        status == 'paid' || status == 'partial' || payments.isNotEmpty;
    final hasPaidTwin = hasMoney
        ? (await client.rpc(
                'invoice_has_paid_twin',
                params: {'p_invoice_id': invoiceId},
              ))
              as bool
        : false;

    final canVoid =
        canEdit &&
        const {'draft', 'open', 'partial', 'failed'}.contains(status);
    final canErase = canDelete && (!hasMoney || hasPaidTwin);

    if (!canVoid && !canErase) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            hasMoney && !hasPaidTwin
                ? l.invoiceOnlyBillCantRemove
                : l.invoiceNotAllowed,
          ),
        ),
      );
      return null;
    }
    if (!context.mounted) return null;

    final choice = await showAdaptiveSheet<String>(
      context: context,
      builder: (_) => _RemoveSheet(canVoid: canVoid, canErase: canErase),
    );
    if (choice == null || !context.mounted) return null;

    if (choice == 'void') {
      final reason = await _askReason(context);
      if (reason == null || reason.trim().isEmpty) return null;
      await client.rpc(
        'void_invoice_secure',
        params: {'p_invoice_id': invoiceId, 'p_reason': reason.trim()},
      );
      notifyGymDataChanged();
      messenger.showSnackBar(SnackBar(content: Text(l.invoiceVoided)));
      return 'void';
    }

    final ok = await showConfirmDialog(
      context,
      title: l.deleteInvoiceTitle,
      body: hasMoney
          ? l.invoiceDeleteWithPaymentsBody(formatCurrency(received))
          : l.deleteInvoiceBody,
      confirmLabel: l.delete,
      icon: AppIcons.delete,
    );
    if (ok != true) return null;
    await client.rpc(
      'delete_invoice_secure',
      params: {'p_invoice_id': invoiceId},
    );
    notifyGymDataChanged();
    messenger.showSnackBar(SnackBar(content: Text(l.invoiceDeleted)));
    return 'delete';
  } on PostgrestException catch (e) {
    final msg = e.message;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          msg.contains('permission_denied')
              ? l.invoiceNotAllowed
              : msg.contains('only_bill_cannot_delete')
              ? l.invoiceOnlyBillCantRemove
              : l.invoiceRemoveFailed,
        ),
      ),
    );
    return null;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.invoiceRemoveFailed)));
    return null;
  }
}

Future<String?> _askReason(BuildContext context) {
  final l = context.l10n;
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.invoiceVoidAction),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l.invoiceVoidReasonLabel,
          hintText: l.invoiceVoidReasonHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: Text(l.invoiceVoidAction),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

class _RemoveSheet extends StatelessWidget {
  final bool canVoid;
  final bool canErase;
  const _RemoveSheet({required this.canVoid, required this.canErase});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const help = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: AppTheme.inkSoft,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTopBar(title: l.invoiceRemoveTitle),
            const SizedBox(height: 8),
            if (canVoid) ...[
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'void'),
                child: Text(l.invoiceVoidAction),
              ),
              const SizedBox(height: 6),
              Text(l.invoiceVoidHelp, style: help),
            ],
            if (canVoid && canErase) const SizedBox(height: 16),
            if (canErase) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: AppTheme.statusDanger,
                  side: const BorderSide(color: AppTheme.statusDanger),
                ),
                onPressed: () => Navigator.pop(context, 'delete'),
                child: Text(l.invoiceDeleteAction),
              ),
              const SizedBox(height: 6),
              Text(l.invoiceDeleteHelp, style: help),
            ],
          ],
        ),
      ),
    );
  }
}
