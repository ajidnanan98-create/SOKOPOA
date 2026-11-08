
class StockMovement {
  final String id;
  final String productId;
  final String movementType;
  final double quantityBase;
  final String unitName;
  final double enteredQuantity;
  final double conversionFactor;
  final String? referenceType;
  final String? referenceId;
  final String? reason;
  final String actorUserId;
  final String deviceId;
  final DateTime occurredAt;
  final String syncState;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.movementType,
    required this.quantityBase,
    required this.unitName,
    required this.enteredQuantity,
    required this.conversionFactor,
    this.referenceType,
    this.referenceId,
    this.reason,
    required this.actorUserId,
    required this.deviceId,
    required this.occurredAt,
    this.syncState = 'pending',
  });

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      movementType: map['movement_type'] as String,
      quantityBase: (map['quantity_base'] as num).toDouble(),
      unitName: map['unit_name'] as String,
      enteredQuantity:
          (map['entered_quantity'] as num?)?.toDouble() ??
              (map['quantity_base'] as num).abs().toDouble(),
      conversionFactor:
          (map['conversion_factor'] as num?)?.toDouble() ?? 1,
      referenceType: map['reference_type'] as String?,
      referenceId: map['reference_id'] as String?,
      reason: map['reason'] as String?,
      actorUserId: map['actor_user_id'] as String,
      deviceId: map['device_id'] as String,
      occurredAt: DateTime.parse(map['occurred_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'movement_type': movementType,
      'quantity_base': quantityBase,
      'unit_name': unitName,
      'entered_quantity': enteredQuantity,
      'conversion_factor': conversionFactor,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'reason': reason,
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'occurred_at': occurredAt.toIso8601String(),
      'sync_state': syncState,
    };
  }
}
