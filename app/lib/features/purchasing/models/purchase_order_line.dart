class PurchaseOrderLine {
  final String id;
  final String purchaseOrderId;
  final String productId;
  final String productName;
  final String? productCode;
  final double enteredQuantity;
  final String unitName;
  final double conversionFactor;
  final double baseQuantity;
  final int unitCostMinor;
  final int lineTotalMinor;
  final DateTime createdAt;

  const PurchaseOrderLine({
    required this.id,
    required this.purchaseOrderId,
    required this.productId,
    required this.productName,
    this.productCode,
    required this.enteredQuantity,
    required this.unitName,
    required this.conversionFactor,
    required this.baseQuantity,
    required this.unitCostMinor,
    required this.lineTotalMinor,
    required this.createdAt,
  });

  factory PurchaseOrderLine.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderLine(
      id: map['id'] as String,
      purchaseOrderId: map['purchase_order_id'] as String,
      productId: map['product_id'] as String,
      productName: map['product_name'] as String,
      productCode: map['product_code'] as String?,
      enteredQuantity: (map['entered_quantity'] as num).toDouble(),
      unitName: map['unit_name'] as String,
      conversionFactor: (map['conversion_factor'] as num).toDouble(),
      baseQuantity: (map['base_quantity'] as num).toDouble(),
      unitCostMinor: (map['unit_cost_minor'] as num).toInt(),
      lineTotalMinor: (map['line_total_minor'] as num).toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchase_order_id': purchaseOrderId,
      'product_id': productId,
      'product_name': productName,
      'product_code': productCode,
      'entered_quantity': enteredQuantity,
      'unit_name': unitName,
      'conversion_factor': conversionFactor,
      'base_quantity': baseQuantity,
      'unit_cost_minor': unitCostMinor,
      'line_total_minor': lineTotalMinor,
      'created_at': createdAt.toIso8601String(),
    };
  }
}