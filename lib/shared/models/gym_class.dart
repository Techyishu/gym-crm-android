class GymClass {
  final String id;
  final String gymId;
  final String name;
  final String? description;
  final String? instructorId;
  final String type;
  final int capacity;
  final int durationMin;
  final String color;
  final String createdAt;
  final String? defaultStartTime;
  final String? defaultEndTime;
  final String? trainerName;
  final List<int> scheduleDays;

  const GymClass({
    required this.id,
    required this.gymId,
    required this.name,
    this.description,
    this.instructorId,
    required this.type,
    required this.capacity,
    required this.durationMin,
    required this.color,
    required this.createdAt,
    this.defaultStartTime,
    this.defaultEndTime,
    this.trainerName,
    this.scheduleDays = const [],
  });

  factory GymClass.fromJson(Map<String, dynamic> j) => GymClass(
    id: j['id'] as String,
    gymId: j['gym_id'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    instructorId: j['instructor_id'] as String?,
    type: j['type'] as String,
    capacity: j['capacity'] as int,
    durationMin: j['duration_min'] as int,
    color: j['color'] as String,
    createdAt: j['created_at'] as String,
    defaultStartTime: j['default_start_time'] as String?,
    defaultEndTime: j['default_end_time'] as String?,
    trainerName: j['trainer_name'] as String?,
    scheduleDays:
        (j['schedule_days'] as List?)?.map((e) => e as int).toList() ??
        const [],
  );
}

class ClassSession {
  final String id;
  final String classId;
  final String startsAt;
  final String endsAt;
  final int? capacityOverride;
  final String status;
  final String? notes;
  final GymClass? gymClass;
  final int? bookingCount;

  const ClassSession({
    required this.id,
    required this.classId,
    required this.startsAt,
    required this.endsAt,
    this.capacityOverride,
    required this.status,
    this.notes,
    this.gymClass,
    this.bookingCount,
  });

  factory ClassSession.fromJson(Map<String, dynamic> j) => ClassSession(
    id: j['id'] as String,
    classId: j['class_id'] as String,
    startsAt: j['starts_at'] as String,
    endsAt: j['ends_at'] as String,
    capacityOverride: j['capacity_override'] as int?,
    status: j['status'] as String,
    notes: j['notes'] as String?,
    gymClass: j['classes'] != null
        ? GymClass.fromJson(j['classes'] as Map<String, dynamic>)
        : null,
    bookingCount: j['booking_count'] as int?,
  );
}

class Booking {
  final String id;
  final String sessionId;
  final String memberId;
  final String status;
  final String bookedAt;
  final ClassSession? session;

  const Booking({
    required this.id,
    required this.sessionId,
    required this.memberId,
    required this.status,
    required this.bookedAt,
    this.session,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
    id: j['id'] as String,
    sessionId: j['session_id'] as String,
    memberId: j['member_id'] as String,
    status: j['status'] as String,
    bookedAt: j['booked_at'] as String,
    session: j['class_sessions'] != null
        ? ClassSession.fromJson(j['class_sessions'] as Map<String, dynamic>)
        : null,
  );
}
