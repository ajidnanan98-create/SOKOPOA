import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_line.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_line.dart';

/// Quantities supplied when recording goods received
/// against one purchase order line.
///
/// All accepted, damaged and rejected quantities are
/// expressed in the product's base unit.
class GoodsReceiptLineInput {
  final String purchaseOrderLineId;
  final double enteredQuantity;
  final double acceptedQuantityBase;
  final double damagedQuantityBase;
  final double rejectedQuantityBase;

  const GoodsReceiptLineInput({
    required this.purchaseOrderLineId,
    required this.enteredQuantity,
    required this.acceptedQuantityBase,
    required this.damagedQuantityBase,
    required this.rejectedQuantityBase,
  });
}

class GoodsReceiptRepository {
  GoodsReceiptRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  static const double _quantityTolerance = 0.000001;

  // CREATE GOODS RECEIPT

  Future<GoodsReceipt> createGoodsReceipt({
    required String receiptNumber,
    required String purchaseOrderId,
    required List<GoodsReceiptLineInput> lines,
    required String actorUserId,
    required String deviceId,
    DateTime? receivedAt,
    String? notes,
  }) async {
    final cleanReceiptNumber = receiptNumber.trim();
    final cleanPurchaseOrderId = purchaseOrderId.trim();

    if (cleanReceiptNumber.isEmpty) {
      throw ArgumentError('Receipt number is required.');
    }

    if (cleanPurchaseOrderId.isEmpty) {
      throw ArgumentError('Purchase order is required.');
    }

    if (lines.isEmpty) {
      throw ArgumentError(
        'At least one goods receipt line is required.',
      );
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now();
    final receiptDate = receivedAt ?? now;
    final receiptId = _uuid.v4();

    late GoodsReceipt createdReceipt;
    final preparedLines = <GoodsReceiptLine>[];

    await _db.transaction((txn) async {
      final orderRows = await txn.query(
        'purchase_orders',
        where: 'id = ?',
        whereArgs: [cleanPurchaseOrderId],
        limit: 1,
      );

      if (orderRows.isEmpty) {
        throw StateError('Purchase order was not found.');
      }

      final order = PurchaseOrder.fromMap(orderRows.first);

      if (order.status != 'ordered' && order.status != 'partially_received') {
        throw StateError(
          'Only ordered or partially received purchase orders '
          'can receive goods.',
        );
      }

      final orderLineRows = await txn.query(
        'purchase_order_lines',
        where: 'purchase_order_id = ?',
        whereArgs: [cleanPurchaseOrderId],
      );

      final orderLines = {
        for (final row in orderLineRows)
          row['id'] as String: PurchaseOrderLine.fromMap(row),
      };

      if (orderLines.isEmpty) {
        throw StateError(
          'The purchase order has no lines.',
        );
      }

      final usedLineIds = <String>{};

      for (final input in lines) {
        final lineId = input.purchaseOrderLineId.trim();

        if (!usedLineIds.add(lineId)) {
          throw ArgumentError(
            'A purchase order line cannot appear twice '
            'in the same receipt.',
          );
        }

        final orderLine = orderLines[lineId];

        if (orderLine == null) {
          throw ArgumentError(
            'A receipt line does not belong to this purchase order.',
          );
        }

        final enteredQuantity = input.enteredQuantity;
        final accepted = input.acceptedQuantityBase;
        final damaged = input.damagedQuantityBase;
        final rejected = input.rejectedQuantityBase;
        final conversionFactor = orderLine.conversionFactor;

        if (!enteredQuantity.isFinite || enteredQuantity <= 0) {
          throw ArgumentError(
            'Received quantity must be greater than zero.',
          );
        }

        if (!accepted.isFinite ||
            !damaged.isFinite ||
            !rejected.isFinite ||
            accepted < 0 ||
            damaged < 0 ||
            rejected < 0) {
          throw ArgumentError(
            'Accepted, damaged and rejected quantities '
            'must be valid non-negative numbers.',
          );
        }

        final receivedBase = enteredQuantity * conversionFactor;

        final accountedBase = accepted + damaged + rejected;

        if ((receivedBase - accountedBase).abs() > _quantityTolerance) {
          throw ArgumentError(
            'Received quantity must equal accepted + '
            'damaged + rejected quantity for '
            '${orderLine.productName}.',
          );
        }

        final previouslyReceived = await _getPostedReceivedBase(
          txn,
          purchaseOrderLineId: lineId,
        );

        final remaining = orderLine.baseQuantity - previouslyReceived;

        if (receivedBase - remaining > _quantityTolerance) {
          throw StateError(
            'Receiving this quantity would exceed the '
            'remaining ordered quantity for '
            '${orderLine.productName}.',
          );
        }

        preparedLines.add(
          GoodsReceiptLine(
            id: _uuid.v4(),
            goodsReceiptId: receiptId,
            purchaseOrderLineId: lineId,
            productId: orderLine.productId,
            productName: orderLine.productName,
            enteredQuantity: enteredQuantity,
            unitName: orderLine.unitName,
            conversionFactor: conversionFactor,
            receivedQuantityBase: receivedBase,
            acceptedQuantityBase: accepted,
            damagedQuantityBase: damaged,
            rejectedQuantityBase: rejected,
            costPerBaseUnitMinor: orderLine.unitCostMinor / conversionFactor,
            createdAt: now,
          ),
        );
      }

      createdReceipt = GoodsReceipt(
        id: receiptId,
        receiptNumber: cleanReceiptNumber,
        purchaseOrderId: cleanPurchaseOrderId,
        status: 'draft',
        receivedAt: receiptDate,
        notes: _cleanOptional(notes),
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        createdAt: now,
        updatedAt: now,
      );

      await txn.insert(
        'goods_receipts',
        createdReceipt.toMap(),
      );

      for (final line in preparedLines) {
        await txn.insert(
          'goods_receipt_lines',
          line.toMap(),
        );
      }

      await _addOutboxEvent(
        txn,
        aggregateType: 'goods_receipt',
        aggregateId: receiptId,
        eventType: 'goods_receipt.created',
        payload: {
          'goods_receipt': createdReceipt.toMap(),
          'lines': preparedLines.map((line) => line.toMap()).toList(),
        },
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'create',
        entityType: 'goods_receipt',
        entityId: receiptId,
        newValue: {
          'goods_receipt': createdReceipt.toMap(),
          'lines': preparedLines.map((line) => line.toMap()).toList(),
        },
        now: now,
      );
    });

    return createdReceipt;
  }

  // POST GOODS RECEIPT
  //
  // Posting is atomic:
  // - Only accepted quantities enter stock.
  // - Damaged and rejected quantities do not enter stock.
  // - Purchase order received quantities are recalculated.
  // - Receipt, stock, audit and sync records commit together.

  Future<GoodsReceipt> postGoodsReceipt({
    required String goodsReceiptId,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanReceiptId = goodsReceiptId.trim();

    if (cleanReceiptId.isEmpty) {
      throw ArgumentError('Goods receipt ID is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now();
    final postedAt = now.toIso8601String();

    late GoodsReceipt postedReceipt;

    await _db.transaction((txn) async {
      // 1. Load and validate the receipt.

      final receiptRows = await txn.query(
        'goods_receipts',
        where: 'id = ?',
        whereArgs: [cleanReceiptId],
        limit: 1,
      );

      if (receiptRows.isEmpty) {
        throw StateError('Goods receipt was not found.');
      }

      final receipt = GoodsReceipt.fromMap(receiptRows.first);

      if (receipt.status != 'draft') {
        throw StateError(
          'Only draft goods receipts can be posted.',
        );
      }

      // 2. Load and validate the purchase order.

      final orderRows = await txn.query(
        'purchase_orders',
        where: 'id = ?',
        whereArgs: [receipt.purchaseOrderId],
        limit: 1,
      );

      if (orderRows.isEmpty) {
        throw StateError('Purchase order was not found.');
      }

      final order = PurchaseOrder.fromMap(orderRows.first);

      if (order.status != 'ordered' && order.status != 'partially_received') {
        throw StateError(
          'This purchase order cannot receive goods.',
        );
      }

      // 3. Load the purchase order lines.

      final orderLineRows = await txn.query(
        'purchase_order_lines',
        where: 'purchase_order_id = ?',
        whereArgs: [receipt.purchaseOrderId],
      );

      if (orderLineRows.isEmpty) {
        throw StateError(
          'The purchase order has no lines.',
        );
      }

      final orderLines = {
        for (final row in orderLineRows)
          row['id'] as String: PurchaseOrderLine.fromMap(row),
      };

      // 4. Load the receipt lines.

      final receiptLineRows = await txn.query(
        'goods_receipt_lines',
        where: 'goods_receipt_id = ?',
        whereArgs: [receipt.id],
      );

      if (receiptLineRows.isEmpty) {
        throw StateError(
          'The goods receipt has no lines.',
        );
      }

      final receiptLines =
          receiptLineRows.map(GoodsReceiptLine.fromMap).toList();

      final usedLineIds = <String>{};

      // 5. Revalidate every line and prevent over-receiving.
      //
      // This check is repeated during posting because multiple
      // draft receipts may have been created for the same quantity.

      for (final line in receiptLines) {
        if (!usedLineIds.add(line.purchaseOrderLineId)) {
          throw StateError(
            'The receipt contains a duplicate purchase order line.',
          );
        }

        final orderLine = orderLines[line.purchaseOrderLineId];

        if (orderLine == null) {
          throw StateError(
            'A receipt line does not belong to this purchase order.',
          );
        }

        if (line.productId != orderLine.productId ||
            line.conversionFactor != orderLine.conversionFactor ||
            line.unitName != orderLine.unitName) {
          throw StateError(
            'A receipt line no longer matches its purchase order line.',
          );
        }

        if (!line.receivedQuantityBase.isFinite ||
            !line.acceptedQuantityBase.isFinite ||
            !line.damagedQuantityBase.isFinite ||
            !line.rejectedQuantityBase.isFinite ||
            line.receivedQuantityBase <= 0 ||
            line.acceptedQuantityBase < 0 ||
            line.damagedQuantityBase < 0 ||
            line.rejectedQuantityBase < 0) {
          throw StateError(
            'A receipt contains invalid quantities.',
          );
        }

        final accountedBase = line.acceptedQuantityBase +
            line.damagedQuantityBase +
            line.rejectedQuantityBase;

        if ((line.receivedQuantityBase - accountedBase).abs() >
            _quantityTolerance) {
          throw StateError(
            'Receipt quantities do not reconcile for '
            '${line.productName}.',
          );
        }

        final previouslyReceived = await _getPostedReceivedBase(
          txn,
          purchaseOrderLineId: line.purchaseOrderLineId,
        );

        final remaining = orderLine.baseQuantity - previouslyReceived;

        if (line.receivedQuantityBase - remaining > _quantityTolerance) {
          throw StateError(
            'Posting this receipt would exceed the remaining '
            'ordered quantity for ${line.productName}.',
          );
        }
      }
      // 6. Calculate and update weighted-average product costs.
      //
      // Aggregate accepted quantities by product first so that
      // multiple receipt lines for one product are calculated
      // together. Existing stock is measured before this receipt.

      final acceptedByProduct = <String, Map<String, double>>{};

      for (final line in receiptLines) {
        final accepted = line.acceptedQuantityBase;

        if (accepted <= 0) {
          continue;
        }

        final totals = acceptedByProduct.putIfAbsent(
          line.productId,
          () => {
            'quantity': 0,
            'cost_total': 0,
          },
        );

        totals['quantity'] = totals['quantity']! + accepted;

        totals['cost_total'] =
            totals['cost_total']! + (accepted * line.costPerBaseUnitMinor);
      }

      for (final entry in acceptedByProduct.entries) {
        final productId = entry.key;
        final incomingQuantity = entry.value['quantity']!;
        final incomingCostTotal = entry.value['cost_total']!;

        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );

        if (productRows.isEmpty) {
          throw StateError(
            'A product in this receipt could not be found.',
          );
        }

        final previousProduct = productRows.first;

        final stockRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_base), 0) AS balance
          FROM stock_movements
          WHERE product_id = ?
          ''',
          [productId],
        );

        final oldStock = (stockRows.first['balance'] as num).toDouble();

        final oldCost = (previousProduct['buying_cost_minor'] as num).toInt();

        if (oldStock < -_quantityTolerance) {
          throw StateError(
            'Product ${previousProduct['name']} has a negative '
            'stock balance. Correct it before posting this receipt.',
          );
        }

        if (oldStock > _quantityTolerance && oldCost <= 0) {
          throw StateError(
            'Cannot post this receipt because '
            '${previousProduct['name']} has existing stock '
            'but no recorded buying cost. The owner must correct '
            'the opening stock cost first.',
          );
        }

        final newAverageCost = oldStock <= _quantityTolerance
            ? (incomingCostTotal / incomingQuantity).round()
            : ((oldStock * oldCost + incomingCostTotal) /
                    (oldStock + incomingQuantity))
                .round();

        final updatedProduct = <String, dynamic>{
          ...previousProduct,
          'buying_cost_minor': newAverageCost,
          'updated_at': postedAt,
          'sync_state': 'pending',
        };

        await txn.update(
          'products',
          updatedProduct,
          where: 'id = ?',
          whereArgs: [productId],
        );

        await _addOutboxEvent(
          txn,
          aggregateType: 'product',
          aggregateId: productId,
          eventType: 'product.average_cost_updated',
          payload: updatedProduct,
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: actorUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'average_cost_updated',
          entityType: 'product',
          entityId: productId,
          previousValue: previousProduct,
          newValue: updatedProduct,
          now: now,
        );
      }

      // 6. Insert stock movements for accepted quantities only.

      final stockMovements = <Map<String, dynamic>>[];

      for (final line in receiptLines) {
        final accepted = line.acceptedQuantityBase;

        // Damaged/rejected-only lines must not create stock.
        if (accepted <= 0) {
          continue;
        }

        final movementId = _uuid.v4();

        final movement = <String, dynamic>{
          'id': movementId,
          'product_id': line.productId,
          'movement_type': 'receipt',
          'quantity_base': accepted,
          'unit_name': line.unitName,
          'entered_quantity': accepted / line.conversionFactor,
          'conversion_factor': line.conversionFactor,
          'reference_type': 'goods_receipt',
          'reference_id': receipt.id,
          'reason': null,
          'actor_user_id': actorUserId.trim(),
          'device_id': deviceId.trim(),
          'occurred_at': postedAt,
          'sync_state': 'pending',
        };

        await txn.insert(
          'stock_movements',
          movement,
        );

        stockMovements.add(movement);

        await _addOutboxEvent(
          txn,
          aggregateType: 'stock_movement',
          aggregateId: movementId,
          eventType: 'stock.receipt_recorded',
          payload: movement,
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: actorUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'stock_movement',
          entityType: 'product',
          entityId: line.productId,
          newValue: movement,
          now: now,
        );
      }

      // 7. Mark the receipt as posted.

      final previousReceiptValue = receipt.toMap();

      final updatedReceiptMap = <String, dynamic>{
        ...receipt.toMap(),
        'status': 'posted',
        'posted_at': postedAt,
        'updated_at': postedAt,
        'actor_user_id': actorUserId.trim(),
        'device_id': deviceId.trim(),
        'sync_state': 'pending',
      };

      await txn.update(
        'goods_receipts',
        updatedReceiptMap,
        where: 'id = ?',
        whereArgs: [receipt.id],
      );

      postedReceipt = GoodsReceipt.fromMap(
        updatedReceiptMap,
      );

      // 8. Update the purchase order's receiving status.
      //
      // The received quantity includes accepted, damaged and
      // rejected goods because all were physically delivered.

      var allLinesFullyReceived = true;

      for (final orderLine in orderLines.values) {
        final totalReceived = await _getPostedReceivedBase(
          txn,
          purchaseOrderLineId: orderLine.id,
        );

        if (totalReceived < orderLine.baseQuantity - _quantityTolerance) {
          allLinesFullyReceived = false;
          break;
        }
      }

      final newOrderStatus =
          allLinesFullyReceived ? 'received' : 'partially_received';

      final updatedOrderMap = <String, dynamic>{
        ...order.toMap(),
        'status': newOrderStatus,
        'updated_at': postedAt,
        'actor_user_id': actorUserId.trim(),
        'device_id': deviceId.trim(),
        'sync_state': 'pending',
      };

      await txn.update(
        'purchase_orders',
        updatedOrderMap,
        where: 'id = ?',
        whereArgs: [order.id],
      );

      // 9. Record the receipt posting event.

      await _addOutboxEvent(
        txn,
        aggregateType: 'goods_receipt',
        aggregateId: receipt.id,
        eventType: 'goods_receipt.posted',
        payload: {
          'goods_receipt': updatedReceiptMap,
          'lines': receiptLines.map((line) => line.toMap()).toList(),
          'stock_movements': stockMovements,
        },
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'post',
        entityType: 'goods_receipt',
        entityId: receipt.id,
        previousValue: previousReceiptValue,
        newValue: {
          'goods_receipt': updatedReceiptMap,
          'lines': receiptLines.map((line) => line.toMap()).toList(),
          'stock_movements': stockMovements,
        },
        now: now,
      );

      // 10. Record the purchase order status change.

      await _addOutboxEvent(
        txn,
        aggregateType: 'purchase_order',
        aggregateId: order.id,
        eventType: 'purchase_order.$newOrderStatus',
        payload: updatedOrderMap,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'goods_received',
        entityType: 'purchase_order',
        entityId: order.id,
        previousValue: order.toMap(),
        newValue: updatedOrderMap,
        now: now,
      );
    });

    return postedReceipt;
  }
  // GET GOODS RECEIPT BY ID

  Future<GoodsReceipt?> getGoodsReceiptById(
    String receiptId,
  ) async {
    final rows = await _db.query(
      'goods_receipts',
      where: 'id = ?',
      whereArgs: [receiptId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return GoodsReceipt.fromMap(rows.first);
  }

  // GET GOODS RECEIPT LINES

  Future<List<GoodsReceiptLine>> getGoodsReceiptLines(
    String receiptId,
  ) async {
    final rows = await _db.query(
      'goods_receipt_lines',
      where: 'goods_receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'created_at ASC',
    );

    return rows.map(GoodsReceiptLine.fromMap).toList();
  }

  // GET RECEIPTS FOR A PURCHASE ORDER

  Future<List<GoodsReceipt>> getGoodsReceiptsForOrder(
    String purchaseOrderId,
  ) async {
    final rows = await _db.query(
      'goods_receipts',
      where: 'purchase_order_id = ?',
      whereArgs: [purchaseOrderId],
      orderBy: 'received_at DESC',
    );

    return rows.map(GoodsReceipt.fromMap).toList();
  }

  // GET QUANTITY ALREADY RECEIVED THROUGH POSTED RECEIPTS

  Future<double> _getPostedReceivedBase(
    DatabaseExecutor executor, {
    required String purchaseOrderLineId,
  }) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(
        SUM(grl.received_quantity_base),
        0
      ) AS received_total
      FROM goods_receipt_lines grl
      INNER JOIN goods_receipts gr
        ON gr.id = grl.goods_receipt_id
      WHERE grl.purchase_order_line_id = ?
        AND gr.status = 'posted'
      ''',
      [purchaseOrderLineId],
    );

    return (rows.first['received_total'] as num).toDouble();
  }

  // INTERNAL HELPERS

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  void _validateActor(
    String actorUserId,
    String deviceId,
  ) {
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError(
        'User and device identifiers are required.',
      );
    }
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
      'occurred_at': now.toIso8601String(),
    });
  }
}
