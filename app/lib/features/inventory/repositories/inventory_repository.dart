import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../models/stock_movement.dart';

class InventoryRepository {
  InventoryRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  // PRODUCT REGISTRATION
  Future<Product> createProduct({
    required String name,
    String? code,
    String? category,
    String? description,
    String? imagePath,
    required String baseUnit,
    required int buyingCostMinor,
    required int sellingPriceMinor,
    required double minimumQuantity,
    double openingQuantity = 0,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();
    final cleanUnit = baseUnit.trim();
    final cleanCode = _cleanOptional(code);
    final cleanImagePath = _cleanOptional(imagePath);
    final now = DateTime.now().toUtc();

    if (cleanName.isEmpty) throw ArgumentError('Product name is required.');
    if (cleanUnit.isEmpty) throw ArgumentError('Base unit is required.');
    if (buyingCostMinor < 0 || sellingPriceMinor < 0) {
      throw ArgumentError('Product prices cannot be negative.');
    }
    if (!minimumQuantity.isFinite || minimumQuantity < 0) {
      throw ArgumentError('Minimum quantity must be zero or greater.');
    }
    if (!openingQuantity.isFinite || openingQuantity < 0) {
      throw ArgumentError('Opening stock must be zero or greater.');
    }
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }

    final product = Product(
      id: _uuid.v4(),
      code: cleanCode,
      name: cleanName,
      category: _cleanOptional(category),
      description: _cleanOptional(description),
      imagePath: cleanImagePath,
      baseUnit: cleanUnit,
      buyingCostMinor: buyingCostMinor,
      sellingPriceMinor: sellingPriceMinor,
      minimumQuantity: minimumQuantity,
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      if (cleanCode != null) {
        final duplicate = await txn.query(
          'products',
          columns: ['id'],
          where: 'LOWER(code) = LOWER(?)',
          whereArgs: [cleanCode],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError('A product with code "$cleanCode" already exists.');
        }
      }

      await txn.insert('products', product.toMap());

      final baseUnitRecord = ProductUnit(
        id: _uuid.v4(),
        productId: product.id,
        unitName: cleanUnit,
        baseUnitsPerUnit: 1,
      );
      await txn.insert('product_units', baseUnitRecord.toMap());

      await _addOutboxEvent(
        txn,
        aggregateType: 'product_unit',
        aggregateId: baseUnitRecord.id,
        eventType: 'product_unit.created',
        payload: baseUnitRecord.toMap(),
        now: now,
      );

      if (openingQuantity > 0) {
        final movement = StockMovement(
          id: _uuid.v4(),
          productId: product.id,
          movementType: 'opening',
          quantityBase: openingQuantity,
          unitName: cleanUnit,
          enteredQuantity: openingQuantity,
          conversionFactor: 1,
          referenceType: 'product',
          referenceId: product.id,
          reason: 'Opening stock',
          actorUserId: actorUserId,
          deviceId: deviceId,
          occurredAt: now,
        );
        await txn.insert('stock_movements', movement.toMap());
        await _addOutboxEvent(
          txn,
          aggregateType: 'stock_movement',
          aggregateId: movement.id,
          eventType: 'stock.opening_recorded',
          payload: movement.toMap(),
          now: now,
        );
      }

      await _addOutboxEvent(
        txn,
        aggregateType: 'product',
        aggregateId: product.id,
        eventType: 'product.created',
        payload: product.toMap(),
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        entityType: 'product',
        entityId: product.id,
        newValue: product.toMap(),
        now: now,
      );
    });
    return product;
  }

  // PRODUCT UNITS / PACKAGING CONVERSIONS
  Future<List<ProductUnit>> getProductUnits(String productId) async {
    final rows = await _db.query(
      'product_units',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'unit_name COLLATE NOCASE ASC',
    );
    return rows.map(ProductUnit.fromMap).toList();
  }

  Future<ProductUnit> addProductUnit({
    required String productId,
    required String unitName,
    required double baseUnitsPerUnit,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanUnitName = unitName.trim();
    if (cleanUnitName.isEmpty) throw ArgumentError('Unit name is required.');
    if (!baseUnitsPerUnit.isFinite || baseUnitsPerUnit <= 0) {
      throw ArgumentError('Conversion factor must be greater than zero.');
    }
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }

    final now = DateTime.now().toUtc();
    final unit = ProductUnit(
      id: _uuid.v4(),
      productId: productId,
      unitName: cleanUnitName,
      baseUnitsPerUnit: baseUnitsPerUnit,
    );

    await _db.transaction((txn) async {
      final productRows = await txn.query(
        'products',
        where: 'id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw StateError('Product does not exist or is archived.');
      }

      final duplicate = await txn.query(
        'product_units',
        columns: ['id'],
        where: 'product_id = ? AND LOWER(unit_name) = LOWER(?)',
        whereArgs: [productId, cleanUnitName],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError(
          'The unit "$cleanUnitName" is already configured for this product.',
        );
      }

      await txn.insert('product_units', unit.toMap());
      await _addOutboxEvent(
        txn,
        aggregateType: 'product_unit',
        aggregateId: unit.id,
        eventType: 'product_unit.created',
        payload: unit.toMap(),
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        entityType: 'product_unit',
        entityId: unit.id,
        newValue: unit.toMap(),
        now: now,
      );
    });
    return unit;
  }

  // UPDATE PRODUCT
  Future<Product> updateProduct({
    required String productId,
    required String name,
    String? code,
    String? category,
    String? description,
    String? imagePath,
    required int buyingCostMinor,
    required int sellingPriceMinor,
    required double minimumQuantity,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();
    final cleanCode = _cleanOptional(code);
    final cleanImagePath = _cleanOptional(imagePath);
    final now = DateTime.now().toUtc();

    if (cleanName.isEmpty) throw ArgumentError('Product name is required.');
    if (buyingCostMinor < 0 || sellingPriceMinor < 0) {
      throw ArgumentError('Product prices cannot be negative.');
    }
    if (!minimumQuantity.isFinite || minimumQuantity < 0) {
      throw ArgumentError('Minimum quantity must be zero or greater.');
    }
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }

    late Product updatedProduct;
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Product not found or archived.');

      final previous = Product.fromMap(rows.first);
      if (cleanCode != null) {
        final duplicate = await txn.query(
          'products',
          columns: ['id'],
          where: 'LOWER(code) = LOWER(?) AND id != ?',
          whereArgs: [cleanCode, productId],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw StateError('A product with code "$cleanCode" already exists.');
        }
      }

      updatedProduct = Product(
        id: previous.id,
        code: cleanCode,
        name: cleanName,
        category: _cleanOptional(category),
        description: _cleanOptional(description),
        imagePath: cleanImagePath ?? previous.imagePath,
        baseUnit: previous.baseUnit,
        buyingCostMinor: buyingCostMinor,
        sellingPriceMinor: sellingPriceMinor,
        minimumQuantity: minimumQuantity,
        active: previous.active,
        createdAt: previous.createdAt,
        updatedAt: now,
        syncState: 'pending',
      );
      final updatedMap = updatedProduct.toMap();

      await txn.update(
        'products',
        updatedMap,
        where: 'id = ?',
        whereArgs: [productId],
      );
      await _addOutboxEvent(
        txn,
        aggregateType: 'product',
        aggregateId: productId,
        eventType: 'product.updated',
        payload: updatedMap,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'update',
        entityType: 'product',
        entityId: productId,
        previousValue: previous.toMap(),
        newValue: updatedMap,
        now: now,
      );
    });
    return updatedProduct;
  }

  // READ PRODUCTS
  Future<List<Product>> getProducts({
    String search = '',
    bool includeArchived = false,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];
    if (!includeArchived) conditions.add('active = 1');

    final term = search.trim();
    if (term.isNotEmpty) {
      conditions.add('(name LIKE ? OR code LIKE ? OR category LIKE ?)');
      final pattern = '%$term%';
      arguments.addAll([pattern, pattern, pattern]);
    }

    final rows = await _db.query(
      'products',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getProductById(String productId) async {
    final rows = await _db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  // STOCK BALANCE
  Future<double> getStockBalance(String productId) async {
    final result = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity_base), 0) AS balance
      FROM stock_movements
      WHERE product_id = ?
      ''',
      [productId],
    );
    return (result.first['balance'] as num).toDouble();
  }

  Future<Map<String, double>> getStockBalances() async {
    final rows = await _db.rawQuery(
      '''
      SELECT product_id, COALESCE(SUM(quantity_base), 0) AS balance
      FROM stock_movements
      GROUP BY product_id
      ''',
    );
    return {
      for (final row in rows)
        row['product_id'] as String: (row['balance'] as num).toDouble(),
    };
  }

  Future<List<Product>> getLowStockProducts() async {
    final products = await getProducts();
    final balances = await getStockBalances();
    return products.where((product) {
      final balance = balances[product.id] ?? 0;
      return balance <= product.minimumQuantity;
    }).toList();
  }

  // RECORD STOCK MOVEMENTS
  Future<StockMovement> recordStockMovement({
    required String productId,
    required String movementType,
    required double quantity,
    required String unitName,
    required String actorUserId,
    required String deviceId,
    String? referenceType,
    String? referenceId,
    String? reason,
  }) async {
    const positiveTypes = {'receipt', 'return_in', 'adjustment_in'};
    const negativeTypes = {
      'sale',
      'damage',
      'expiry',
      'return_out',
      'adjustment_out',
    };

    if (!positiveTypes.contains(movementType) &&
        !negativeTypes.contains(movementType)) {
      throw ArgumentError('Unsupported stock movement type.');
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('Quantity must be greater than zero.');
    }
    if (unitName.trim().isEmpty) throw ArgumentError('Unit name is required.');
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }
    if ((movementType == 'adjustment_in' ||
            movementType == 'adjustment_out' ||
            movementType == 'damage' ||
            movementType == 'expiry') &&
        (reason == null || reason.trim().isEmpty)) {
      throw ArgumentError('A reason is required for this movement.');
    }

    final now = DateTime.now().toUtc();
    late StockMovement movement;
    await _db.transaction((txn) async {
      final productRows = await txn.query(
        'products',
        where: 'id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw StateError('Product does not exist or is archived.');
      }

      final unitRows = await txn.query(
        'product_units',
        where: 'product_id = ? AND LOWER(unit_name) = LOWER(?)',
        whereArgs: [productId, unitName.trim()],
        limit: 1,
      );
      if (unitRows.isEmpty) {
        throw StateError(
          'Unit "${unitName.trim()}" is not configured for this product.',
        );
      }

      final conversionFactor =
          (unitRows.first['base_units_per_unit'] as num).toDouble();
      final baseQuantity = quantity * conversionFactor;
      if (!baseQuantity.isFinite || baseQuantity <= 0) {
        throw ArgumentError('Converted stock quantity is invalid.');
      }

      final isPositive = positiveTypes.contains(movementType);
      final signedBaseQuantity = isPositive ? baseQuantity : -baseQuantity;
      movement = StockMovement(
        id: _uuid.v4(),
        productId: productId,
        movementType: movementType,
        quantityBase: signedBaseQuantity,
        unitName: unitName.trim(),
        enteredQuantity: quantity,
        conversionFactor: conversionFactor,
        referenceType: _cleanOptional(referenceType),
        referenceId: _cleanOptional(referenceId),
        reason: _cleanOptional(reason),
        actorUserId: actorUserId,
        deviceId: deviceId,
        occurredAt: now,
      );

      final balanceRows = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(quantity_base), 0) AS balance
        FROM stock_movements
        WHERE product_id = ?
        ''',
        [productId],
      );
      final currentBalance = (balanceRows.first['balance'] as num).toDouble();
      final newBalance = currentBalance + signedBaseQuantity;
      if (newBalance < -0.000001) {
        throw StateError(
          'Insufficient stock. Available: $currentBalance ${productRows.first['base_unit']}',
        );
      }

      await txn.insert('stock_movements', movement.toMap());
      await _addOutboxEvent(
        txn,
        aggregateType: 'stock_movement',
        aggregateId: movement.id,
        eventType: 'stock.${movementType}_recorded',
        payload: movement.toMap(),
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'stock_movement',
        entityType: 'product',
        entityId: productId,
        newValue: movement.toMap(),
        now: now,
      );
    });
    return movement;
  }

  // ARCHIVE PRODUCT
  Future<void> archiveProduct({
    required String productId,
    required String actorUserId,
    required String deviceId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('An archive reason is required.');
    }
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }

    final now = DateTime.now().toUtc();
    await _db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Product not found or already archived.');
      }

      final balanceRows = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(quantity_base), 0) AS balance
        FROM stock_movements
        WHERE product_id = ?
        ''',
        [productId],
      );
      final balance = (balanceRows.first['balance'] as num).toDouble();
      if (balance > 0.000001) {
        throw StateError(
          'This product still has $balance units in stock. Record a stock adjustment before archiving it.',
        );
      }

      final previous = rows.first;
      await txn.update(
        'products',
        {
          'active': 0,
          'updated_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
      final updated = {
        ...previous,
        'active': 0,
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };
      await _addOutboxEvent(
        txn,
        aggregateType: 'product',
        aggregateId: productId,
        eventType: 'product.archived',
        payload: updated,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'archive',
        entityType: 'product',
        entityId: productId,
        previousValue: previous,
        newValue: updated,
        reason: reason.trim(),
        now: now,
      );
    });
  }

  // INTERNAL HELPERS
  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String aggregateType,
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': aggregateType,
      'aggregate_id': aggregateId,
      'event_type': eventType,
      'payload_json': jsonEncode(payload),
      'created_at': now.toIso8601String(),
      'status': 'pending',
    });
  }

  Future<void> _addAuditEntry(
    Transaction txn, {
    required String actorUserId,
    required String deviceId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    String? reason,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json': newValue == null ? null : jsonEncode(newValue),
      'reason': reason,
      'occurred_at': now.toIso8601String(),
    });
  }
}
