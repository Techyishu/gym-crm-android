class Member {
  final String id;
  final String gymId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? customId;
  final String? avatarUrl;
  final String? notes;
  final String status;
  final String joinedAt;
  final String createdAt;
  final String? userId;
  final String? nextPaymentDate;
  final int billingIntervalMonths;
  final Membership? currentMembership;
  final String? biometricId;

  const Member({
    required this.id,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.customId,
    this.avatarUrl,
    this.notes,
    required this.status,
    required this.joinedAt,
    required this.createdAt,
    this.userId,
    this.nextPaymentDate,
    this.billingIntervalMonths = 1,
    this.currentMembership,
    this.biometricId,
  });

  String get fullName => '$firstName $lastName';

  factory Member.fromJson(Map<String, dynamic> j) {
    // id is used for routing — throw rather than silently produce an empty-string
    // ID that would cause subtle navigation bugs downstream.
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('Member row missing id');

    return Member(
      id: id,
      gymId: j['gym_id'] as String? ?? '',
      firstName: j['first_name'] as String? ?? '',
      lastName: j['last_name'] as String? ?? '',
      email: j['email'] as String? ?? '',
      phone: j['phone'] as String?,
      customId: j['custom_id'] as String?,
      avatarUrl: j['avatar_url'] as String?,
      notes: j['notes'] as String?,
      status: j['status'] as String? ?? 'unknown',
      joinedAt: j['joined_at'] as String? ?? j['created_at'] as String? ?? '',
      createdAt: j['created_at'] as String? ?? '',
      userId: j['user_id'] as String?,
      nextPaymentDate: j['next_payment_date'] as String?,
      billingIntervalMonths: (j['billing_interval_months'] as int?) ?? 1,
      biometricId: j['biometric_id'] as String?,
      currentMembership: (() {
        final list = j['memberships'] as List?;
        if (list == null || list.isEmpty) return null;
        final maps = list.cast<Map<String, dynamic>>();
        // Prefer the active membership; fall back to first if none are active.
        final active = maps.where((ms) => ms['status'] == 'active').toList();
        return Membership.fromJson(active.isNotEmpty ? active.first : maps.first);
      })(),
    );
  }

  Map<String, dynamic> toJson() => {
        'gym_id': gymId,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        if (phone != null) 'phone': phone,
        if (notes != null) 'notes': notes,
        'status': status,
      };
}

class Membership {
  final String id;
  final String memberId;
  final String planId;
  final String status;
  final String startsAt;
  final String? endsAt;
  final MembershipPlan? plan;

  const Membership({
    required this.id,
    required this.memberId,
    required this.planId,
    required this.status,
    required this.startsAt,
    this.endsAt,
    this.plan,
  });

  factory Membership.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('Membership row missing id');

    return Membership(
      id: id,
      memberId: j['member_id'] as String? ?? '',
      planId: j['plan_id'] as String? ?? '',
      status: j['status'] as String? ?? 'unknown',
      startsAt: j['starts_at'] as String? ?? '',
      endsAt: j['ends_at'] as String?,
      plan: j['membership_plans'] != null
          ? MembershipPlan.fromJson(
              j['membership_plans'] as Map<String, dynamic>)
          : null,
    );
  }
}

class MembershipPlan {
  final String id;
  final String gymId;
  final String name;
  final double price;
  final String billingInterval;
  final List<String> features;
  final int? maxClasses;
  final bool isActive;

  const MembershipPlan({
    required this.id,
    required this.gymId,
    required this.name,
    required this.price,
    required this.billingInterval,
    required this.features,
    this.maxClasses,
    required this.isActive,
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) throw FormatException('MembershipPlan row missing id');

    return MembershipPlan(
      id: id,
      gymId: j['gym_id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      price: (j['price'] as num?)?.toDouble() ?? 0.0,
      billingInterval: j['billing_interval'] as String? ?? 'monthly',
      features: List<String>.from(j['features'] ?? []),
      maxClasses: j['max_classes'] as int?,
      isActive: j['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'gym_id': gymId,
        'name': name,
        'price': price,
        'billing_interval': billingInterval,
        'features': features,
        if (maxClasses != null) 'max_classes': maxClasses,
        'is_active': isActive,
      };
}
