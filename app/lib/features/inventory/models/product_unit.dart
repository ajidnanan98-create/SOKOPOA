
class ProductUnit {
  final String id;
  final String productId;
  final String unitName;
  final double baseUnitsPerUnit;

  const ProductUnit({
    required this.id,
    required this.productId,
    required this.unitName,
    required this.baseUnitsPerUnit,
  });

  factory ProductUnit.fromMap(Map<String, dynamic> map) {
    return ProductUnit(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      unitName: map['unit_name'] as String,
      baseUnitsPerUnit:
          (map['base_units_per_unit'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'product_id': productId,
      'unit_name': unitName,
      'base_units_per_unit': baseUnitsPerUnit,
    };
  }
}
