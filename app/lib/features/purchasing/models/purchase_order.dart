class PurchaseOrder {
  final String id;
  final String orderNumber;
  final String supplierId;
  final String status;
  final DateTime? orderedAt;
  final DateTime? expectedAt;
  final String? notes;
  final int subtotalMinor;
  final int discountMinor;
  final int totalMinor;
  final String actorUserId;
  final String deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncState;

  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.supplierId,
    required this.status,
    this.orderedAt,
    this.expectedAt,
    this.notes,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.totalMinor,
    required this.actorUserId,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.syncState = 'pending',
  });

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    return PurchaseOrder(
      id: map['id'] as String,
      orderNumber: map['order_number'] as String,
      supplierId: map['supplier_id'] as String,
      status: map['status'] as String,
      orderedAt: map['ordered_at'] == null
          ? null
          : DateTime.parse(map['ordered_at'] as String),
      expectedAt: map['expected_at'] == null
          ? null
          : DateTime.parse(map['expected_at'] as String),
      notes: map['notes'] as String?,
      subtotalMinor: (map['subtotal_minor'] as num).toInt(),
      discountMinor: (map['discount_minor'] as num).toInt(),
      totalMinor: (map['total_minor'] as num).toInt(),
      actorUserId: map['actor_user_id'] as String,
      deviceId: map['device_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'supplier_id': supplierId,
      'status': status,
      'ordered_at': orderedAt?.toIso8601String(),
      'expected_at': expectedAt?.toIso8601String(),
      'notes': notes,
      'subtotal_minor': subtotalMinor,
      'discount_minor': discountMinor,
      'total_minor': totalMinor,
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_state': syncState,
    };
  }
}