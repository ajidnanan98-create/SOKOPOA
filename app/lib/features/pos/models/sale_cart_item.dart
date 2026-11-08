class SaleCartItem {
  const SaleCartItem({
    required this.productId,
    required this.productName,
    required this.unitName,
    required this.quantity,
    required this.conversionFactor,
    required this.unitPriceMinor,
    required this.costPerBaseUnitMinor,
  });

  final String productId;
  final String productName;
  final String unitName;
  final double quantity;
  final double conversionFactor;

  /// Selling price for one selected unit, in KES minor units.
  final int unitPriceMinor;

  /// Weighted-average buying cost for one base unit, in KES minor units.
  final int costPerBaseUnitMinor;

  double get baseQuantity => quantity * conversionFactor;

  int get lineTotalMinor => (quantity * unitPriceMinor).round();

  int get totalCostMinor => (baseQuantity * costPerBaseUnitMinor).round();

  int get grossProfitMinor => lineTotalMinor - totalCostMinor;

  SaleCartItem copyWith({
    double? quantity,
  }) {
    return SaleCartItem(
      productId: productId,
      productName: productName,
      unitName: unitName,
      quantity: quantity ?? this.quantity,
      conversionFactor: conversionFactor,
      unitPriceMinor: unitPriceMinor,
      costPerBaseUnitMinor: costPerBaseUnitMinor,
    );
  }
}
