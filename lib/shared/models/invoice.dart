class Invoice {
  final String id;
  final String memberId;
  final String gymId;
  final String? invoiceNumber;
  final double amount;
  final double? originalAmount;
  final double discountAmount;
  final double admissionFee;
  final String status;
  final String? description;
  final String? dueAt;
  final String? paidAt;
  final String createdAt;
  final Member? member;

  const Invoice({
    required this.id,
    required this.memberId,
    required this.gymId,
    this.invoiceNumber,
    required this.amount,
    this.originalAmount,
    this.discountAmount = 0,
    this.admissionFee = 0,
    required this.status,
    this.description,
    this.dueAt,
    this.paidAt,
    required this.createdAt,
    this.member,
  });

  bool get hasDiscount => discountAmount > 0;

  factory Invoice.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty)
      throw FormatException('Invoice row missing id');

    return Invoice(
      id: id,
      memberId: j['member_id'] as String? ?? '',
      gymId: j['gym_id'] as String? ?? '',
      invoiceNumber: j['invoice_number'] as String?,
      amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
      originalAmount: (j['original_amount'] as num?)?.toDouble(),
      discountAmount: (j['discount_amount'] as num?)?.toDouble() ?? 0.0,
      admissionFee: (j['admission_fee'] as num?)?.toDouble() ?? 0.0,
      status: j['status'] as String? ?? 'unknown',
      description: j['description'] as String?,
      dueAt: j['due_at'] as String?,
      paidAt: j['paid_at'] as String?,
      createdAt: j['created_at'] as String? ?? '',
      member: j['members'] != null
          ? Member.fromJson(j['members'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Member {
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;

  const Member({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
  });

  String get fullName => '$firstName $lastName';

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    firstName: j['first_name'] as String? ?? '',
    lastName: j['last_name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    phone: j['phone'] as String?,
  );
}
