import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/access/role_access.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/expense.dart';
import '../../../shared/widgets/redesign.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:gym_crm/shared/widgets/adaptive_sheet.dart';
import '../../../shared/widgets/responsive_content.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final gymId = await ref.watch(gymIdProvider.future);
  final client = Supabase.instance.client;

  final data = await client
      .from('expenses')
      .select()
      .eq('gym_id', gymId)
      .order('expense_date', ascending: false);

  return (data as List).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(_expensesProvider);
    final role = ref.watch(staffRoleProvider).valueOrNull;
    final canDelete = RoleAccess.canDeleteExpense(role);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Expenses'),
        leading: const BackButton(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _showAddSheet(context, ref),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add, size: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: ResponsiveContent(child: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyExpenses();

          final now = DateTime.now();
          final monthTotal = list
              .where((e) => e.expenseDate.year == now.year && e.expenseDate.month == now.month)
              .fold<double>(0, (s, e) => s + e.amount);

          return Column(
            children: [
              _MonthSummary(total: monthTotal),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_expensesProvider),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _ExpenseCard(
                      expense: list[i],
                      canDelete: canDelete,
                      onDelete: () async {
                        await Supabase.instance.client
                            .from('expenses')
                            .delete()
                            .eq('id', list[i].id);
                        ref.invalidate(_expensesProvider);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      )),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddExpenseSheet(),
    ).then((_) => ref.invalidate(_expensesProvider));
  }
}

// ── Month summary strip ─────────────────────────────────────────────────────────

class _MonthSummary extends StatelessWidget {
  final double total;
  const _MonthSummary({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('This month', style: TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
          const Spacer(),
          Text(
            formatCurrency(total),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
        ],
      ),
    );
  }
}

// ── Expense card ──────────────────────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final bool canDelete;
  final VoidCallback onDelete;
  const _ExpenseCard({required this.expense, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.category,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(expense.expenseDate),
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
                if (expense.note != null && expense.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    expense.note!,
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatCurrency(expense.amount),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.ink),
              ),
              if (canDelete) ...[
                const SizedBox(height: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 16, color: AppTheme.inkHint),
                  onSelected: (v) async {
                    if (v == 'delete') {
                      final ok = await showConfirmDialog(
                        context,
                        title: 'Delete expense?',
                        body: 'Delete this ${expense.category} entry of ${formatCurrency(expense.amount)}? This cannot be undone.',
                        confirmLabel: 'Delete',
                        icon: Icons.delete_outline,
                      );
                      if (ok == true) onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: AppTheme.statusDanger),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: AppTheme.statusDanger)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add Expense Sheet ────────────────────────────────────────────────────────

class _AddExpenseSheet extends ConsumerStatefulWidget {
  const _AddExpenseSheet();

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _category = kExpenseCategories.first;
  DateTime _date = DateTime.now();
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;
    setState(() => _loading = true);

    try {
      final gymId = await ref.read(gymIdProvider.future);
      final client = Supabase.instance.client;

      await client.from('expenses').insert({
        'gym_id': gymId,
        'category': _category,
        'amount': amount,
        'expense_date': _date.toIso8601String().split('T')[0],
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(title: 'Add expense'),
            const SizedBox(height: 18),
            const FieldLabel('Category'),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: kExpenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Amount'),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Date'),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(formatDate(_date), style: const TextStyle(color: AppTheme.ink)),
              ),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Note (optional)'),
            TextFormField(controller: _noteCtrl, maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Save expense'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.inkHint),
          SizedBox(height: 16),
          Text(
            'No expenses logged',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.ink),
          ),
          SizedBox(height: 8),
          Text(
            'Log rent, salary, and other gym expenses here',
            style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
