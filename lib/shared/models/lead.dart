class Lead {
  final String id;
  final String gymId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String status;
  final String? source;
  final String? notes;
  final String? followUpAt;
  final String createdAt;

  const Lead({
    required this.id,
    required this.gymId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.status,
    this.source,
    this.notes,
    this.followUpAt,
    required this.createdAt,
  });

  String get name => '$firstName $lastName'.trim();

  factory Lead.fromJson(Map<String, dynamic> j) => Lead(
        id: j['id'] as String,
        gymId: j['gym_id'] as String,
        firstName: j['first_name'] as String? ?? '',
        lastName: j['last_name'] as String? ?? '',
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        status: j['status'] as String,
        source: j['source'] as String?,
        notes: j['notes'] as String?,
        followUpAt: j['follow_up_at'] as String?,
        createdAt: j['created_at'] as String,
      );

  Map<String, dynamic> toJson() => {
        'gym_id': gymId,
        'first_name': firstName,
        'last_name': lastName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'status': status,
        if (source != null) 'source': source,
        if (notes != null) 'notes': notes,
        if (followUpAt != null) 'follow_up_at': followUpAt,
      };
}
