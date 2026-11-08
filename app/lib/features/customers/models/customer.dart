class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final int creditLimitMinor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncState;

  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.creditLimitMinor = 0,
    required this.createdAt,
    required this.updatedAt,
    this.syncState = 'pending',
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      creditLimitMinor: map['credit_limit_minor'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'credit_limit_minor': creditLimitMinor,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_state': syncState,
    };
  }
}