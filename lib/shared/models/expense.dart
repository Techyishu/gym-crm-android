class Expense {
  final String id;
  final String gymId;
  final String category;
  final double amount;
  final DateTime expenseDate;
  final String? note;

  Expense({
    required this.id,
    required this.gymId,
    required this.category,
    required this.amount,
    required this.expenseDate,
    this.note,
  });

  factory Expense.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw const FormatException('Expense row missing id');
    return Expense(
      id: id,
      gymId: j['gym_id'] as String,
      category: j['category'] as String,
      amount: (j['amount'] as num).toDouble(),
      expenseDate: DateTime.parse(j['expense_date'] as String),
      note: j['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'gym_id': gymId,
    'category': category,
    'amount': amount,
    'expense_date': expenseDate.toIso8601String().split('T')[0],
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}

const kExpenseCategories = ['Rent', 'Salary', 'Equipment', 'Utilities', 'Maintenance', 'Other'];
