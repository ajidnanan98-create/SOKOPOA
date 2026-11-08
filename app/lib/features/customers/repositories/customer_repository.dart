import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/customer.dart';
import '../../pos/models/sale_payment.dart';
import '../models/customer_repayment_result.dart';
import '../models/customer_repayment_history_entry.dart';

class CustomerRepository {
  CustomerRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    int creditLimitMinor = 0,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Customer name is required.');
    }

    if (creditLimitMinor < 0) {
      throw ArgumentError('Credit limit cannot be negative.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    final customer = Customer(
      id: _uuid.v4(),
      name: cleanName,
      phone: _cleanOptional(phone),
      email: _cleanOptional(email),
      creditLimitMinor: creditLimitMinor,
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert('customers', customer.toMap());

      await _addOutboxEvent(
        txn,
        aggregateId: customer.id,
        eventType: 'customer.created',
        payload: customer.toMap(),
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'create',
        entityId: customer.id,
        newValue: customer.toMap(),
        now: now,
      );
    });

    return customer;
  }

  Future<List<Customer>> getCustomers({String? search}) async {
    final cleanedSearch = search?.trim();

    final rows = await _db.query(
      'customers',
      where: cleanedSearch == null || cleanedSearch.isEmpty
          ? null
          : '''
            LOWER(name) LIKE ?
            OR LOWER(COALESCE(phone, '')) LIKE ?
            OR LOWER(COALESCE(email, '')) LIKE ?
          ''',
      whereArgs: cleanedSearch == null || cleanedSearch.isEmpty
          ? null
          : [
              '%${cleanedSearch.toLowerCase()}%',
              '%${cleanedSearch.toLowerCase()}%',
              '%${cleanedSearch.toLowerCase()}%',
            ],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomerById(String customerId) async {
    final rows = await _db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Customer.fromMap(rows.first);
  }

  Future<Customer> updateCustomer({
    required String customerId,
    required String name,
    String? phone,
    String? email,
    required int creditLimitMinor,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Customer name is required.');
    }

    if (creditLimitMinor < 0) {
      throw ArgumentError('Credit limit cannot be negative.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late Customer updatedCustomer;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Customer was not found.');
      }

      final previous = rows.first;

      final updated = {
        ...previous,
        'name': cleanName,
        'phone': _cleanOptional(phone),
        'email': _cleanOptional(email),
        'credit_limit_minor': creditLimitMinor,
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'customers',
        updated,
        where: 'id = ?',
        whereArgs: [customerId],
      );

      updatedCustomer = Customer.fromMap(updated);

      await _addOutboxEvent(
        txn,
        aggregateId: customerId,
        eventType: 'customer.updated',
        payload: updated,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'update',
        entityId: customerId,
        previousValue: previous,
        newValue: updated,
        now: now,
      );
    });

    return updatedCustomer;
  }

  Future<CustomerRepaymentResult> recordRepayment({
    required String customerId,
    required SalePayment payment,
    required String receivedBy,
    required String actorUserId,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    if (customerId.trim().isEmpty) {
      throw ArgumentError('Customer ID is required.');
    }

    if (!payment.hasValidMethod) {
      throw ArgumentError('Unsupported payment method.');
    }

    if (!payment.hasValidAmount) {
      throw ArgumentError('Repayment amount must be greater than zero.');
    }

    if (receivedBy.trim().isEmpty) {
      throw ArgumentError('Received-by user is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = (occurredAt ?? DateTime.now()).toUtc();
    final occurredAtText = now.toIso8601String();
    final reference = _cleanOptional(payment.reference);

    final allocations = <CustomerRepaymentAllocation>[];
    late int remainingDebtMinor;

    await _db.transaction((txn) async {
      final customerRows = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (customerRows.isEmpty) {
        throw StateError('Customer was not found.');
      }

      final sales = await txn.query(
        'sales',
        where: '''
          customer_id = ?
          AND status != 'void'
          AND total_minor > paid_minor
        ''',
        whereArgs: [customerId],
        orderBy: 'occurred_at ASC, id ASC',
      );

      var outstandingMinor = 0;

      for (final sale in sales) {
        outstandingMinor +=
            (sale['total_minor'] as int) - (sale['paid_minor'] as int);
      }

      if (payment.amountMinor > outstandingMinor) {
        throw ArgumentError(
          'Repayment exceeds the customer outstanding debt.',
        );
      }

      var amountRemaining = payment.amountMinor;

      for (final sale in sales) {
        if (amountRemaining == 0) break;

        final saleId = sale['id'] as String;
        final receiptNumber = sale['receipt_number'] as String;
        final totalMinor = sale['total_minor'] as int;
        final previousPaidMinor = sale['paid_minor'] as int;

        final balanceBefore = totalMinor - previousPaidMinor;

        if (balanceBefore <= 0) continue;

        final allocatedMinor =
            amountRemaining < balanceBefore ? amountRemaining : balanceBefore;

        final updatedPaidMinor = previousPaidMinor + allocatedMinor;

        final balanceAfter = totalMinor - updatedPaidMinor;

        final updatedStatus = balanceAfter == 0 ? 'paid' : 'part_paid';

        final updatedSale = {
          ...sale,
          'paid_minor': updatedPaidMinor,
          'status': updatedStatus,
          'sync_state': 'pending',
        };

        await txn.update(
          'sales',
          {
            'paid_minor': updatedPaidMinor,
            'status': updatedStatus,
            'sync_state': 'pending',
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );

        final paymentId = _uuid.v4();

        final paymentMap = {
          'id': paymentId,
          'related_type': 'sale',
          'related_id': saleId,
          'method': payment.method,
          'amount_minor': allocatedMinor,
          'reference': reference,
          'received_by': receivedBy.trim(),
          'occurred_at': occurredAtText,
          'sync_state': 'pending',
        };

        await txn.insert('payments', paymentMap);

        await _addOutboxEvent(
          txn,
          aggregateType: 'payment',
          aggregateId: paymentId,
          eventType: 'payment.customer_repayment_received',
          payload: paymentMap,
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: actorUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'customer_repayment_received',
          entityType: 'payment',
          entityId: paymentId,
          newValue: paymentMap,
          now: now,
        );

        await _addOutboxEvent(
          txn,
          aggregateType: 'sale',
          aggregateId: saleId,
          eventType: 'sale.payment_applied',
          payload: {
            'sale_id': saleId,
            'receipt_number': receiptNumber,
            'paid_minor': updatedPaidMinor,
            'balance_minor': balanceAfter,
            'status': updatedStatus,
          },
          now: now,
        );

        await _addAuditEntry(
          txn,
          actorUserId: actorUserId.trim(),
          deviceId: deviceId.trim(),
          action: 'payment_applied',
          entityType: 'sale',
          entityId: saleId,
          previousValue: sale,
          newValue: updatedSale,
          now: now,
        );

        allocations.add(
          CustomerRepaymentAllocation(
            saleId: saleId,
            receiptNumber: receiptNumber,
            amountMinor: allocatedMinor,
            paidMinor: updatedPaidMinor,
            balanceMinor: balanceAfter,
            saleStatus: updatedStatus,
          ),
        );

        amountRemaining -= allocatedMinor;
      }

      final debtRows = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(total_minor - paid_minor), 0)
          AS outstanding
        FROM sales
        WHERE customer_id = ?
          AND status != 'void'
        ''',
        [customerId],
      );

      remainingDebtMinor =
          (debtRows.first['outstanding'] as num?)?.toInt() ?? 0;
    });

    return CustomerRepaymentResult(
      customerId: customerId,
      amountMinor: payment.amountMinor,
      method: payment.method,
      reference: reference,
      receivedBy: receivedBy.trim(),
      occurredAt: now,
      allocations: allocations,
      remainingDebtMinor: remainingDebtMinor,
    );
  }

  Future<int> getOutstandingDebtMinor(String customerId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_minor - paid_minor), 0) AS outstanding
      FROM sales
      WHERE customer_id = ?
        AND status != 'void'
      ''',
      [customerId],
    );

    return (rows.first['outstanding'] as num?)?.toInt() ?? 0;
  }

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
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
    String aggregateType = 'customer',
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
    String entityType = 'customer',
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
      'entity_type': entityType,
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json': newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }

  /// Returns repayment allocations for a customer, newest first.
  Future<List<CustomerRepaymentHistoryEntry>> getRepaymentHistory(
    String customerId,
  ) async {
    final cleanCustomerId = customerId.trim();

    if (cleanCustomerId.isEmpty) {
      throw ArgumentError('Customer ID is required.');
    }

    final rows = await _db.rawQuery(
      '''
      SELECT
        payments.id AS payment_id,
        sales.id AS sale_id,
        sales.receipt_number AS receipt_number,
        payments.amount_minor AS amount_minor,
        payments.method AS method,
        payments.reference AS reference,
        payments.received_by AS received_by,
        payments.occurred_at AS occurred_at
      FROM payments
      INNER JOIN sales
        ON sales.id = payments.related_id
      WHERE payments.related_type = 'sale'
        AND sales.customer_id = ?
      ORDER BY payments.occurred_at DESC, payments.id DESC
      ''',
      [cleanCustomerId],
    );

    return rows
        .map(CustomerRepaymentHistoryEntry.fromMap)
        .toList(growable: false);
  }
}
