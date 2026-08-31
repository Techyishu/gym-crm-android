class ActivityLogEntry {
  final String id;
  final String gymId;
  final String branchName;
  final String? actorId;
  final String actorName;
  final String? actorRole;
  final String module;
  final String actionType;
  final String entityType;
  final String? entityId;
  final String? entityLabel;
  final double? amount;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.gymId,
    required this.branchName,
    this.actorId,
    required this.actorName,
    this.actorRole,
    required this.module,
    required this.actionType,
    required this.entityType,
    this.entityId,
    this.entityLabel,
    this.amount,
    required this.metadata,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('Activity log row missing id');
    }
    return ActivityLogEntry(
      id: id,
      gymId: json['gym_id'] as String? ?? '',
      branchName: json['branch_name'] as String? ?? 'Branch',
      actorId: json['actor_id'] as String?,
      actorName: json['actor_name'] as String? ?? 'System',
      actorRole: json['actor_role'] as String?,
      module: json['module'] as String? ?? 'system',
      actionType: json['action_type'] as String? ?? 'updated',
      entityType: json['entity_type'] as String? ?? 'record',
      entityId: json['entity_id'] as String?,
      entityLabel: json['entity_label'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  String get actionLabel => actionType
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
