class GoodsReceipt {
  final String id;
  final String receiptNumber;
  final String purchaseOrderId;
  final String status;
  final DateTime receivedAt;
  final String? notes;
  final String actorUserId;
  final String deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? postedAt;
  final String syncState;

  const GoodsReceipt({
    required this.id,
    required this.receiptNumber,
    required this.purchaseOrderId,
    required this.status,
    required this.receivedAt,
    this.notes,
    required this.actorUserId,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.postedAt,
    this.syncState = 'pending',
  });

  factory GoodsReceipt.fromMap(Map<String, dynamic> map) {
    return GoodsReceipt(
      id: map['id'] as String,
      receiptNumber: map['receipt_number'] as String,
      purchaseOrderId: map['purchase_order_id'] as String,
      status: map['status'] as String,
      receivedAt: DateTime.parse(map['received_at'] as String),
      notes: map['notes'] as String?,
      actorUserId: map['actor_user_id'] as String,
      deviceId: map['device_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      postedAt: map['posted_at'] == null
          ? null
          : DateTime.parse(map['posted_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'purchase_order_id': purchaseOrderId,
      'status': status,
      'received_at': receivedAt.toIso8601String(),
      'notes': notes,
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'posted_at': postedAt?.toIso8601String(),
      'sync_state': syncState,
    };
  }
}