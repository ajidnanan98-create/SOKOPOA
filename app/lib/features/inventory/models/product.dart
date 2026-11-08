class Product {
  final String id;
  final String? code;
  final String name;
  final String? category;
  final String? description;
  final String baseUnit;
  final int buyingCostMinor;
  final int sellingPriceMinor;
  final double minimumQuantity;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncState;

  /// Relative path to the product image inside SOKOPOA's app-managed storage.
  ///
  /// This is nullable so existing products and products without photographs
  /// continue to work normally.
  final String? imagePath;

  const Product({
    required this.id,
    this.code,
    required this.name,
    this.category,
    this.description,
    required this.baseUnit,
    required this.buyingCostMinor,
    required this.sellingPriceMinor,
    required this.minimumQuantity,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.syncState = 'pending',
    this.imagePath,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      code: map['code'] as String?,
      name: map['name'] as String,
      category: map['category'] as String?,
      description: map['description'] as String?,
      baseUnit: map['base_unit'] as String,
      buyingCostMinor: (map['buying_cost_minor'] as num).toInt(),
      sellingPriceMinor: (map['selling_price_minor'] as num).toInt(),
      minimumQuantity: (map['minimum_quantity'] as num).toDouble(),
      active: (map['active'] as num).toInt() == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncState: map['sync_state'] as String? ?? 'pending',
      imagePath: map['image_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'category': category,
      'description': description,
      'base_unit': baseUnit,
      'buying_cost_minor': buyingCostMinor,
      'selling_price_minor': sellingPriceMinor,
      'minimum_quantity': minimumQuantity,
      'active': active ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_state': syncState,
      'image_path': imagePath,
    };
  }

  Product copyWith({
    String? code,
    String? name,
    String? category,
    String? description,
    String? baseUnit,
    int? buyingCostMinor,
    int? sellingPriceMinor,
    double? minimumQuantity,
    bool? active,
    DateTime? updatedAt,
    String? syncState,
    String? imagePath,
    bool clearImagePath = false,
  }) {
    return Product(
      id: id,
      code: code ?? this.code,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      baseUnit: baseUnit ?? this.baseUnit,
      buyingCostMinor: buyingCostMinor ?? this.buyingCostMinor,
      sellingPriceMinor: sellingPriceMinor ?? this.sellingPriceMinor,
      minimumQuantity: minimumQuantity ?? this.minimumQuantity,
      active: active ?? this.active,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncState: syncState ?? this.syncState,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
    );
  }
}
