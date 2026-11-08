import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/sale_cart_item.dart';
import '../models/sale_payment.dart';
import '../models/sale_result.dart';

class PosRepository {
  PosRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  static const double _quantityTolerance = 0.000001;

  /// Completes a sale atomically.
  ///
  /// All amounts are stored in KES minor units (1 KES = 100 minor units).
  Future<SaleResult> completeSale({
    required List<SaleCartItem> cartItems,
    required List<SalePayment> payments,
    required String cashierUserId,
    required String deviceId,
    String? customerId,
    String? servedByWorkerId,
    int discountMinor = 0,
    DateTime? occurredAt,
  }) async {
    _validateActor(cashierUserId, deviceId);

    if (cartItems.isEmpty) {
      throw ArgumentError('Add at least one product before checkout.');
    }

    if (discountMinor < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }

    final now = occurredAt ?? DateTime.now();
    final saleId = _uuid.v4();

    late SaleResult result;

    await _db.transaction((txn) async {
      final preparedLines = <Map<String, dynamic>>[];
      final requiredStock = <String, double>{};

      var subtotalMinor = 0;

      // 1. Validate each product and calculate authoritative prices.
      for (final item in cartItems) {
        if (item.quantity <= 0 ||
            !item.quantity.isFinite ||
            item.conversionFactor <= 0 ||
            !item.conversionFactor.isFinite) {
          throw ArgumentError('Invalid quantity or unit conversion.');
        }

        final productRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
          limit: 1,
        );

        if (productRows.isEmpty) {
          throw StateError('Product ${item.productName} no longer exists.');
        }

        final product = productRows.first;

        if ((product['active'] as num).toInt() != 1) {
          throw StateError('${product['name']} is archived.');
        }

        final baseUnit = product['base_unit'] as String;
        final unitName = item.unitName.trim();

        if (unitName.isEmpty) {
          throw ArgumentError('A selling unit is required.');
        }

        // Base unit has a conversion factor of exactly one.
        double actualFactor;

        if (unitName == baseUnit) {
          actualFactor = 1;
        } else {
          final unitRows = await txn.query(
            'product_units',
            where: 'product_id = ? AND unit_name = ?',
            whereArgs: [item.productId, unitName],
            limit: 1,
          );

          if (unitRows.isEmpty) {
            throw StateError(
              'The unit $unitName is not configured for ${product['name']}.',
            );
          }

          actualFactor =
              (unitRows.first['base_units_per_unit'] as num).toDouble();
        }

        if ((actualFactor - item.conversionFactor).abs() > _quantityTolerance) {
          throw StateError(
            'The unit conversion for ${product['name']} has changed. '
            'Refresh the cart and try again.',
          );
        }

        final baseQuantity = item.quantity * actualFactor;

        final sellingPricePerBase =
            (product['selling_price_minor'] as num).toInt();

        final costPerBase = (product['buying_cost_minor'] as num).toInt();

        if (sellingPricePerBase < 0 || costPerBase < 0) {
          throw StateError('Invalid product price or cost.');
        }

        final unitPriceMinor = (sellingPricePerBase * actualFactor).round();

        final lineTotalMinor = (item.quantity * unitPriceMinor).round();

        final costMinor = (baseQuantity * costPerBase).round();

        if (lineTotalMinor <= 0) {
          throw StateError(
            'The selling total for ${product['name']} must be positive.',
          );
        }

        subtotalMinor += lineTotalMinor;

        requiredStock[item.productId] =
            (requiredStock[item.productId] ?? 0) + baseQuantity;

        preparedLines.add({
          'id': _uuid.v4(),
          'product_id': item.productId,
          'product_name': product['name'],
          'quantity': item.quantity,
          'unit_name': unitName,
          'base_quantity': baseQuantity,
          'unit_price_minor': unitPriceMinor,
          'cost_minor': costMinor,
          'line_total_minor': lineTotalMinor,
        });
      }

      // 2. Calculate sale total.
      if (discountMinor > subtotalMinor) {
        throw ArgumentError('Discount cannot exceed the subtotal.');
      }

      final totalMinor = subtotalMinor - discountMinor;

      if (totalMinor <= 0) {
        throw ArgumentError('Sale total must be greater than zero.');
      }

      // 3. Validate available stock for every product.
      // Aggregate quantities prevent overselling when a product
      // appears more than once in the same cart.
      for (final entry in requiredStock.entries) {
        final stockRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_base), 0) AS balance
          FROM stock_movements
          WHERE product_id = ?
          ''',
          [entry.key],
        );

        final available = (stockRows.first['balance'] as num).toDouble();

        if (available + _quantityTolerance < entry.value) {
          final productRows = await txn.query(
            'products',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [entry.key],
            limit: 1,
          );

          final productName =
              productRows.isEmpty ? entry.key : productRows.first['name'];

          throw StateError(
            'Insufficient stock for $productName. '
            'Available: $available, required: ${entry.value}.',
          );
        }
      }

      // 4. Validate the selected worker.
      if (servedByWorkerId != null && servedByWorkerId.trim().isNotEmpty) {
        final workerRows = await txn.query(
          'workers',
          where: 'id = ? AND active = 1',
          whereArgs: [servedByWorkerId.trim()],
          limit: 1,
        );

        if (workerRows.isEmpty) {
          throw StateError('The selected worker is not active.');
        }
      }

      // 5. Validate payments.
      var paidMinor = 0;

      for (final payment in payments) {
        if (!payment.hasValidMethod) {
          throw ArgumentError(
            'Unsupported payment method: ${payment.method}.',
          );
        }

        if (!payment.hasValidAmount) {
          throw ArgumentError('Payment amounts must be positive.');
        }

        paidMinor += payment.amountMinor;
      }

      if (paidMinor > totalMinor) {
        throw ArgumentError(
          'Payments cannot exceed the sale total.',
        );
      }

      final balanceMinor = totalMinor - paidMinor;

      // 6. Enforce customer credit rules.
      String? cleanCustomerId;

      if (customerId != null && customerId.trim().isNotEmpty) {
        cleanCustomerId = customerId.trim();

        final customerRows = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [cleanCustomerId],
          limit: 1,
        );

        if (customerRows.isEmpty) {
          throw StateError('The selected customer does not exist.');
        }
      }

      if (balanceMinor > 0) {
        if (cleanCustomerId == null) {
          throw StateError(
            'Select a customer before completing a credit sale.',
          );
        }

        final customerRows = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [cleanCustomerId],
          limit: 1,
        );

        final creditLimit =
            (customerRows.first['credit_limit_minor'] as num).toInt();

        final debtRows = await txn.rawQuery(
          '''
          SELECT COALESCE(
            SUM(total_minor - paid_minor), 0
          ) AS outstanding
          FROM sales
          WHERE customer_id = ?
            AND status != 'void'
          ''',
          [cleanCustomerId],
        );

        final existingDebt = (debtRows.first['outstanding'] as num).toInt();

        if (creditLimit <= 0) {
          throw StateError(
            'This customer does not have a credit facility.',
          );
        }

        if (existingDebt + balanceMinor > creditLimit) {
          throw StateError(
            'Customer credit limit exceeded. '
            'Existing debt: $existingDebt minor units. '
            'New balance: $balanceMinor minor units. '
            'Credit limit: $creditLimit minor units.',
          );
        }
      }

      // 7. Generate a unique daily receipt number.
      final receiptNumber = await _generateReceiptNumber(
        txn,
        now,
      );

      final status = balanceMinor == 0
          ? 'paid'
          : paidMinor == 0
              ? 'unpaid'
              : 'part_paid';

      final occurredAtText = now.toIso8601String();

      // 8. Insert the sale.
      await txn.insert('sales', {
        'id': saleId,
        'receipt_number': receiptNumber,
        'customer_id': cleanCustomerId,
        'cashier_user_id': cashierUserId.trim(),
        'served_by_worker_id': servedByWorkerId?.trim().isEmpty == true
            ? null
            : servedByWorkerId?.trim(),
        'subtotal_minor': subtotalMinor,
        'discount_minor': discountMinor,
        'total_minor': totalMinor,
        'paid_minor': paidMinor,
        'status': status,
        'occurred_at': occurredAtText,
        'device_id': deviceId.trim(),
        'sync_state': 'pending',
      });

      // 9. Insert sale lines and deduct stock.
      for (final line in preparedLines) {
        await txn.insert('sale_lines', {
          'id': line['id'],
          'sale_id': saleId,
          'product_id': line['product_id'],
          'quantity': line['quantity'],
          'unit_name': line['unit_name'],
          'base_quantity': line['base_quantity'],
          'unit_price_minor': line['unit_price_minor'],
          'cost_minor': line['cost_minor'],
          'line_total_minor': line['line_total_minor'],
        });

        final movementId = _uuid.v4();

        final movement = {
          'id': movementId,
          'product_id': line['product_id'],
          'movement_type': 'sale',
          'quantity_base': -(line['base_quantity'] as double),
          'unit_name': line['unit_name'],
          'entered_quantity': line['quantity'],
          'conversion_factor':
              (line['base_quantity'] as double) / (line['quantity'] as double),
          'reference_type': 'sale',
          'reference_id': saleId,
          'reason': 'Point of sale checkout',
          'actor_user_id': cashierUserId.trim(),
          'device_id': deviceId.trim(),
          'occurred_at': occurredAtText,
          'sync_state': 'pending',
        };

        await txn.insert('stock_movements', movement);

        await _addOutboxEvent(
          txn,
          aggregateType: 'stock_movement',
          aggregateId: movementId,
          eventType: 'stock.sale_recorded',
          payload: movement,
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: cashierUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'stock_sale',
          entityType: 'product',
          entityId: line['product_id'] as String,
          newValue: movement,
          now: now,
        );
      }

      // 10. Insert payment rows.
      for (final payment in payments) {
        final paymentId = _uuid.v4();

        final paymentMap = {
          'id': paymentId,
          'related_type': 'sale',
          'related_id': saleId,
          'method': payment.method,
          'amount_minor': payment.amountMinor,
          'reference': payment.reference?.trim().isEmpty == true
              ? null
              : payment.reference?.trim(),
          'received_by': cashierUserId.trim(),
          'occurred_at': occurredAtText,
          'sync_state': 'pending',
        };

        await txn.insert('payments', paymentMap);

        await _addOutboxEvent(
          txn,
          aggregateType: 'payment',
          aggregateId: paymentId,
          eventType: 'payment.sale_received',
          payload: paymentMap,
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: cashierUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'payment_received',
          entityType: 'sale',
          entityId: saleId,
          newValue: paymentMap,
          now: now,
        );
      }

      // 11. Record sale sync event.
      final saleMap = {
        'id': saleId,
        'receipt_number': receiptNumber,
        'customer_id': cleanCustomerId,
        'cashier_user_id': cashierUserId.trim(),
        'served_by_worker_id': servedByWorkerId?.trim().isEmpty == true
            ? null
            : servedByWorkerId?.trim(),
        'subtotal_minor': subtotalMinor,
        'discount_minor': discountMinor,
        'total_minor': totalMinor,
        'paid_minor': paidMinor,
        'balance_minor': balanceMinor,
        'status': status,
        'occurred_at': occurredAtText,
        'device_id': deviceId.trim(),
      };

      await _addOutboxEvent(
        txn,
        aggregateType: 'sale',
        aggregateId: saleId,
        eventType: 'sale.completed',
        payload: {
          'sale': saleMap,
          'lines': preparedLines,
        },
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: cashierUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'complete',
        entityType: 'sale',
        entityId: saleId,
        newValue: {
          'sale': saleMap,
          'lines': preparedLines,
        },
        now: now,
      );

      result = SaleResult(
        saleId: saleId,
        receiptNumber: receiptNumber,
        subtotalMinor: subtotalMinor,
        discountMinor: discountMinor,
        totalMinor: totalMinor,
        paidMinor: paidMinor,
        balanceMinor: balanceMinor,
        status: status,
        occurredAt: now,
      );
    });

    return result;
  }

  Future<String> _generateReceiptNumber(
    Transaction txn,
    DateTime date,
  ) async {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    final prefix = 'SOK-$year$month$day-';

    final rows = await txn.rawQuery(
      '''
      SELECT receipt_number
      FROM sales
      WHERE receipt_number LIKE ?
      ORDER BY receipt_number DESC
      LIMIT 1
      ''',
      ['$prefix%'],
    );

    var nextSequence = 1;

    if (rows.isNotEmpty) {
      final previous = rows.first['receipt_number'] as String;
      final previousSequence = int.tryParse(previous.substring(prefix.length));

      if (previousSequence != null) {
        nextSequence = previousSequence + 1;
      }
    }

    return '$prefix${nextSequence.toString().padLeft(4, '0')}';
  }

  void _validateActor(String actorUserId, String deviceId) {
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
