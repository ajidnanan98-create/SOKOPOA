
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../../inventory/models/product.dart';
import '../../inventory/models/product_unit.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_line.dart';

/// Data supplied when adding a product to a purchase order.
class PurchaseOrderLineInput {
  final String productId;
  final double enteredQuantity;
  final String unitName;
  final int unitCostMinor;

  const PurchaseOrderLineInput({
    required this.productId,
    required this.enteredQuantity,
    required this.unitName,
    required this.unitCostMinor,
  });
}

class PurchaseOrderRepository {
  PurchaseOrderRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  // CREATE PURCHASE ORDER

  Future<PurchaseOrder> createPurchaseOrder({
    required String orderNumber,
    required String supplierId,
    required List<PurchaseOrderLineInput> lines,
    required String actorUserId,
    required String deviceId,
    DateTime? expectedAt,
    String? notes,
    int discountMinor = 0,
  }) async {
    final cleanOrderNumber = orderNumber.trim();
    final cleanSupplierId = supplierId.trim();

    if (cleanOrderNumber.isEmpty) {
      throw ArgumentError('Purchase order number is required.');
    }

    if (cleanSupplierId.isEmpty) {
      throw ArgumentError('Supplier is required.');
    }

    if (lines.isEmpty) {
      throw ArgumentError('At least one purchase order line is required.');
    }

    if (discountMinor < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late PurchaseOrder purchaseOrder;

    await _db.transaction((txn) async {
      final supplier = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [cleanSupplierId],
        limit: 1,
      );

      if (supplier.isEmpty) {
        throw StateError('Selected supplier was not found.');
      }

      final orderId = _uuid.v4();

      final preparedLines = await _prepareLines(
        txn,
        purchaseOrderId: orderId,
        inputs: lines,
        now: now,
      );

      final subtotalMinor = preparedLines.fold<int>(
        0,
        (total, line) => total + line.lineTotalMinor,
      );

      if (discountMinor > subtotalMinor) {
        throw ArgumentError(
          'Discount cannot exceed the purchase order subtotal.',
        );
      }

      purchaseOrder = PurchaseOrder(
        id: orderId,
        orderNumber: cleanOrderNumber,
        supplierId: cleanSupplierId,
        status: 'draft',
        expectedAt: expectedAt?.toUtc(),
        notes: _cleanOptional(notes),
        subtotalMinor: subtotalMinor,
        discountMinor: discountMinor,
        totalMinor: subtotalMinor - discountMinor,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await txn.insert(
        'purchase_orders',
        purchaseOrder.toMap(),
      );

      for (final line in preparedLines) {
        await txn.insert(
          'purchase_order_lines',
          line.toMap(),
        );
      }

      await _addOutboxEvent(
        txn,
        aggregateId: orderId,
        eventType: 'purchase_order.created',
        payload: {
          'purchase_order': purchaseOrder.toMap(),
          'lines': preparedLines.map((line) => line.toMap()).toList(),
        },
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'create',
        entityId: orderId,
        newValue: {
          'purchase_order': purchaseOrder.toMap(),
          'lines': preparedLines.map((line) => line.toMap()).toList(),
        },
        now: now,
      );
    });

    return purchaseOrder;
  }

  // PREPARE AND VALIDATE PURCHASE ORDER LINES

  Future<List<PurchaseOrderLine>> _prepareLines(
    Transaction txn, {
    required String purchaseOrderId,
    required List<PurchaseOrderLineInput> inputs,
    required DateTime now,
  }) async {
    final prepared = <PurchaseOrderLine>[];

    for (final input in inputs) {
      final productId = input.productId.trim();
      final unitName = input.unitName.trim();

      if (productId.isEmpty || unitName.isEmpty) {
        throw ArgumentError(
          'Every purchase order line needs a product and unit.',
        );
      }

      if (!input.enteredQuantity.isFinite ||
          input.enteredQuantity <= 0) {
        throw ArgumentError(
          'Entered quantity must be a positive finite number.',
        );
      }

      if (input.unitCostMinor < 0) {
        throw ArgumentError('Unit cost cannot be negative.');
      }

      final productRows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );

      if (productRows.isEmpty) {
        throw StateError('A selected product was not found.');
      }

      final product = Product.fromMap(productRows.first);

      if (!product.active) {
        throw StateError(
          'Product "${product.name}" is inactive and cannot be ordered.',
        );
      }

      final factor = await _getConversionFactor(
        txn,
        product: product,
        unitName: unitName,
      );

      final baseQuantity = input.enteredQuantity * factor;

      if (!baseQuantity.isFinite || baseQuantity <= 0) {
        throw ArgumentError(
          'Calculated base quantity is invalid for ${product.name}.',
        );
      }

      final calculatedTotal =
          input.enteredQuantity * input.unitCostMinor;

      if (!calculatedTotal.isFinite ||
          calculatedTotal > 9007199254740991) {
        throw ArgumentError(
          'Line total is too large for ${product.name}.',
        );
      }

      final lineTotalMinor = calculatedTotal.round();

      prepared.add(
        PurchaseOrderLine(
          id: _uuid.v4(),
          purchaseOrderId: purchaseOrderId,
          productId: product.id,
          productName: product.name,
          productCode: product.code,
          enteredQuantity: input.enteredQuantity,
          unitName: unitName,
          conversionFactor: factor,
          baseQuantity: baseQuantity,
          unitCostMinor: input.unitCostMinor,
          lineTotalMinor: lineTotalMinor,
          createdAt: now,
        ),
      );
    }

    return prepared;
  }

  // VALIDATE BASE UNIT OR REGISTERED PACKAGING UNIT

  Future<double> _getConversionFactor(
    Transaction txn, {
    required Product product,
    required String unitName,
  }) async {
    if (product.baseUnit.trim().toLowerCase() ==
        unitName.toLowerCase()) {
      return 1.0;
    }

    final rows = await txn.query(
      'product_units',
      where: 'product_id = ? AND LOWER(unit_name) = LOWER(?)',
      whereArgs: [product.id, unitName],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError(
        '"$unitName" is not a registered unit for ${product.name}.',
      );
    }

    final unit = ProductUnit.fromMap(rows.first);

    if (!unit.baseUnitsPerUnit.isFinite ||
        unit.baseUnitsPerUnit <= 0) {
      throw StateError(
        'The conversion factor for "$unitName" is invalid.',
      );
    }

    return unit.baseUnitsPerUnit;
  }

  // GET PURCHASE ORDERS

  Future<List<PurchaseOrder>> getPurchaseOrders({
    String? supplierId,
    String? status,
    String? search,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];

    if (supplierId != null && supplierId.trim().isNotEmpty) {
      conditions.add('supplier_id = ?');
      arguments.add(supplierId.trim());
    }

    if (status != null && status.trim().isNotEmpty) {
      conditions.add('status = ?');
      arguments.add(status.trim());
    }

    if (search != null && search.trim().isNotEmpty) {
      conditions.add('LOWER(order_number) LIKE ?');
      arguments.add('%${search.trim().toLowerCase()}%');
    }

    final rows = await _db.query(
      'purchase_orders',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'created_at DESC',
    );

    return rows.map(PurchaseOrder.fromMap).toList();
  }

  // GET PURCHASE ORDER BY ID

  Future<PurchaseOrder?> getPurchaseOrderById(
    String purchaseOrderId,
  ) async {
    final rows = await _db.query(
      'purchase_orders',
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return PurchaseOrder.fromMap(rows.first);
  }

  // GET PURCHASE ORDER LINES

  Future<List<PurchaseOrderLine>> getPurchaseOrderLines(
    String purchaseOrderId,
  ) async {
    final rows = await _db.query(
      'purchase_order_lines',
      where: 'purchase_order_id = ?',
      whereArgs: [purchaseOrderId],
      orderBy: 'created_at ASC',
    );

    return rows.map(PurchaseOrderLine.fromMap).toList();
  }

  // UPDATE DRAFT PURCHASE ORDER

  Future<PurchaseOrder> updateDraftPurchaseOrder({
    required String purchaseOrderId,
    required String orderNumber,
    required String supplierId,
    required List<PurchaseOrderLineInput> lines,
    required String actorUserId,
    required String deviceId,
    DateTime? expectedAt,
    String? notes,
    int discountMinor = 0,
  }) async {
    final cleanOrderNumber = orderNumber.trim();
    final cleanSupplierId = supplierId.trim();

    if (cleanOrderNumber.isEmpty || cleanSupplierId.isEmpty) {
      throw ArgumentError(
        'Purchase order number and supplier are required.',
      );
    }

    if (lines.isEmpty) {
      throw ArgumentError(
        'At least one purchase order line is required.',
      );
    }

    if (discountMinor < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late PurchaseOrder updatedOrder;

    await _db.transaction((txn) async {
      final existingRows = await txn.query(
        'purchase_orders',
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        throw StateError('Purchase order was not found.');
      }

      final previous = existingRows.first;

      if (previous['status'] != 'draft') {
        throw StateError(
          'Only draft purchase orders can be edited.',
        );
      }

      final supplierRows = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [cleanSupplierId],
        limit: 1,
      );

      if (supplierRows.isEmpty) {
        throw StateError('Selected supplier was not found.');
      }

      final preparedLines = await _prepareLines(
        txn,
        purchaseOrderId: purchaseOrderId,
        inputs: lines,
        now: now,
      );

      final subtotalMinor = preparedLines.fold<int>(
        0,
        (total, line) => total + line.lineTotalMinor,
      );

      if (discountMinor > subtotalMinor) {
        throw ArgumentError(
          'Discount cannot exceed the purchase order subtotal.',
        );
      }

      final updatedMap = <String, dynamic>{
        ...previous,
        'order_number': cleanOrderNumber,
        'supplier_id': cleanSupplierId,
        'expected_at': expectedAt?.toUtc().toIso8601String(),
        'notes': _cleanOptional(notes),
        'subtotal_minor': subtotalMinor,
        'discount_minor': discountMinor,
        'total_minor': subtotalMinor - discountMinor,
        'actor_user_id': actorUserId.trim(),
        'device_id': deviceId.trim(),
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'purchase_orders',
        updatedMap,
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
      );

      await txn.delete(
        'purchase_order_lines',
        where: 'purchase_order_id = ?',
        whereArgs: [purchaseOrderId],
      );

      for (final line in preparedLines) {
        await txn.insert(
          'purchase_order_lines',
          line.toMap(),
        );
      }

      updatedOrder = PurchaseOrder.fromMap(updatedMap);

      final newValue = {
        'purchase_order': updatedOrder.toMap(),
        'lines': preparedLines.map((line) => line.toMap()).toList(),
      };

      await _addOutboxEvent(
        txn,
        aggregateId: purchaseOrderId,
        eventType: 'purchase_order.updated',
        payload: newValue,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'update',
        entityId: purchaseOrderId,
        previousValue: previous,
        newValue: newValue,
        now: now,
      );
    });

    return updatedOrder;
  }

  // MARK PURCHASE ORDER AS ORDERED

  Future<PurchaseOrder> markPurchaseOrderOrdered({
    required String purchaseOrderId,
    required String actorUserId,
    required String deviceId,
  }) async {
    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late PurchaseOrder updatedOrder;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'purchase_orders',
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Purchase order was not found.');
      }

      final previous = rows.first;

      if (previous['status'] != 'draft') {
        throw StateError(
          'Only draft purchase orders can be marked as ordered.',
        );
      }

      final lineRows = await txn.query(
        'purchase_order_lines',
        where: 'purchase_order_id = ?',
        whereArgs: [purchaseOrderId],
        limit: 1,
      );

      if (lineRows.isEmpty) {
        throw StateError(
          'A purchase order must contain at least one line.',
        );
      }

      final updatedMap = <String, dynamic>{
        ...previous,
        'status': 'ordered',
        'ordered_at': now.toIso8601String(),
        'actor_user_id': actorUserId.trim(),
        'device_id': deviceId.trim(),
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'purchase_orders',
        updatedMap,
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
      );

      updatedOrder = PurchaseOrder.fromMap(updatedMap);

      await _addOutboxEvent(
        txn,
        aggregateId: purchaseOrderId,
        eventType: 'purchase_order.ordered',
        payload: updatedOrder.toMap(),
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'mark_ordered',
        entityId: purchaseOrderId,
        previousValue: previous,
        newValue: updatedMap,
        now: now,
      );
    });

    return updatedOrder;
  }

  // INTERNAL HELPERS

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  void _validateActor(String actorUserId, String deviceId) {
    if (actorUserId.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      throw ArgumentError(
        'User and device identifiers are required.',
      );
    }
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': 'purchase_order',
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
    required String entityId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': 'purchase_order',
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json':
          newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }
}
