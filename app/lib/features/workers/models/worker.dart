class Worker {
  const Worker({
    required this.id,
    required this.fullName,
    required this.role,
    this.phone,
    required this.active,
    this.hiredAt,
    required this.createdAt,
    required this.syncState,
  });

  final String id;
  final String fullName;
  final String role;
  final String? phone;
  final bool active;
  final DateTime? hiredAt;
  final DateTime createdAt;
  final String syncState;

  factory Worker.fromMap(Map<String, Object?> map) {
    return Worker(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      role: map['role'] as String,
      phone: map['phone'] as String?,
      active: (map['active'] as num).toInt() == 1,
      hiredAt: map['hired_at'] == null
          ? null
          : DateTime.parse(map['hired_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'full_name': fullName,
      'role': role,
      'phone': phone,
      'active': active ? 1 : 0,
      'hired_at': hiredAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'sync_state': syncState,
    };
  }
}
