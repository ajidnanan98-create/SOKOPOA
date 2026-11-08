class GoodsReceiptLine {
  final String id;
  final String goodsReceiptId;
  final String purchaseOrderLineId;
  final String productId;
  final String productName;
  final double enteredQuantity;
  final String unitName;
  final double conversionFactor;
  final double receivedQuantityBase;
  final double acceptedQuantityBase;
  final double damagedQuantityBase;
  final double rejectedQuantityBase;
  final double costPerBaseUnitMinor;
  final DateTime createdAt;

  const GoodsReceiptLine({
    required this.id,
    required this.goodsReceiptId,
    required this.purchaseOrderLineId,
    required this.productId,
    required this.productName,
    required this.enteredQuantity,
    required this.unitName,
    required this.conversionFactor,
    required this.receivedQuantityBase,
    required this.acceptedQuantityBase,
    required this.damagedQuantityBase,
    required this.rejectedQuantityBase,
    required this.costPerBaseUnitMinor,
    required this.createdAt,
  });

  factory GoodsReceiptLine.fromMap(Map<String, dynamic> map) {
    return GoodsReceiptLine(
      id: map['id'] as String,
      goodsReceiptId: map['goods_receipt_id'] as String,
      purchaseOrderLineId: map['purchase_order_line_id'] as String,
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      enteredQuantity: (map['entered_quantity'] as num).toDouble(),
      unitName: map['unit_name'] as String,
      conversionFactor: (map['conversion_factor'] as num).toDouble(),
      receivedQuantityBase:
          (map['received_quantity_base'] as num).toDouble(),
      acceptedQuantityBase:
          (map['accepted_quantity_base'] as num).toDouble(),
      damagedQuantityBase:
          (map['damaged_quantity_base'] as num).toDouble(),
      rejectedQuantityBase:
          (map['rejected_quantity_base'] as num).toDouble(),
      costPerBaseUnitMinor:
          (map['cost_per_base_unit_minor'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goods_receipt_id': goodsReceiptId,
      'purchase_order_line_id': purchaseOrderLineId,
      'product_id': productId,
      'product_name': productName,
      'entered_quantity': enteredQuantity,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'received_quantity_base': receivedQuantityBase,
      'accepted_quantity_base': acceptedQuantityBase,
      'damaged_quantity_base': damagedQuantityBase,
      'rejected_quantity_base': rejectedQuantityBase,
      'cost_per_base_unit_minor': costPerBaseUnitMinor,
      'created_at': createdAt.toIso8601String(),
    };
  }
}