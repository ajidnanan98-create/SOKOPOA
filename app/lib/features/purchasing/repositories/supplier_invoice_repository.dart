
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/supplier_invoice.dart';
import '../models/supplier_payment.dart';

class SupplierInvoiceRepository {
  SupplierInvoiceRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  // CREATE SUPPLIER INVOICE

  Future<SupplierInvoice> createInvoice({
    required String supplierId,
    required String invoiceNumber,
    required DateTime invoiceDate,
    required int subtotalMinor,
    required String actorUserId,
    required String deviceId,
    String? purchaseOrderId,
    DateTime? dueDate,
    int taxMinor = 0,
    int otherChargesMinor = 0,
    String? notes,
  }) async {
    final cleanSupplierId = supplierId.trim();
    final cleanInvoiceNumber = invoiceNumber.trim();
    final cleanPurchaseOrderId = _cleanOptional(purchaseOrderId);

    if (cleanSupplierId.isEmpty) {
      throw ArgumentError('Supplier is required.');
    }

    if (cleanInvoiceNumber.isEmpty) {
      throw ArgumentError('Invoice number is required.');
    }

    if (subtotalMinor < 0 || taxMinor < 0 || otherChargesMinor < 0) {
      throw ArgumentError('Invoice amounts cannot be negative.');
    }

    final totalMinor = subtotalMinor + taxMinor + otherChargesMinor;

    if (totalMinor <= 0) {
      throw ArgumentError('Invoice total must be greater than zero.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    final invoice = SupplierInvoice(
      id: _uuid.v4(),
      supplierId: cleanSupplierId,
      invoiceNumber: cleanInvoiceNumber,
      purchaseOrderId: cleanPurchaseOrderId,
      invoiceDate: invoiceDate.toUtc().toIso8601String(),
      dueDate: dueDate?.toUtc().toIso8601String(),
      subtotalMinor: subtotalMinor,
      taxMinor: taxMinor,
      otherChargesMinor: otherChargesMinor,
      totalMinor: totalMinor,
      status: 'open',
      notes: _cleanOptional(notes),
      actorUserId: actorUserId.trim(),
      deviceId: deviceId.trim(),
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );

    await _db.transaction((txn) async {
      final suppliers = await txn.query(
        'suppliers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [cleanSupplierId],
        limit: 1,
      );

      if (suppliers.isEmpty) {
        throw StateError('Supplier does not exist.');
      }

      if (cleanPurchaseOrderId != null) {
        final orders = await txn.query(
          'purchase_orders',
          columns: ['supplier_id'],
          where: 'id = ?',
          whereArgs: [cleanPurchaseOrderId],
          limit: 1,
        );

        if (orders.isEmpty) {
          throw StateError('Linked purchase order does not exist.');
        }

        if (orders.first['supplier_id'] != cleanSupplierId) {
          throw StateError(
            'Purchase order belongs to a different supplier.',
          );
        }
      }

      final duplicates = await txn.query(
        'supplier_invoices',
        columns: ['id'],
        where: 'supplier_id = ? AND invoice_number = ?',
        whereArgs: [cleanSupplierId, cleanInvoiceNumber],
        limit: 1,
      );

      if (duplicates.isNotEmpty) {
        throw StateError(
          'This invoice number already exists for this supplier.',
        );
      }

      await txn.insert('supplier_invoices', invoice.toMap());

      await _addOutboxEvent(
        txn,
        aggregateId: invoice.id,
        eventType: 'supplier_invoice.created',
        payload: invoice.toMap(),
        aggregateType: 'supplier_invoice',
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        entityType: 'supplier_invoice',
        entityId: invoice.id,
        newValue: invoice.toMap(),
        now: now,
      );
    });

    return invoice;
  }

  // GET INVOICES

  Future<List<SupplierInvoice>> getInvoices({
    String? supplierId,
    String? status,
    String? search,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];

    final cleanSupplierId = _cleanOptional(supplierId);
    final cleanStatus = _cleanOptional(status);
    final cleanSearch = _cleanOptional(search);

    if (cleanSupplierId != null) {
      conditions.add('supplier_id = ?');
      arguments.add(cleanSupplierId);
    }

    if (cleanStatus != null) {
      conditions.add('status = ?');
      arguments.add(cleanStatus);
    }

    if (cleanSearch != null) {
      conditions.add('LOWER(invoice_number) LIKE ?');
      arguments.add('%${cleanSearch.toLowerCase()}%');
    }

    final rows = await _db.query(
      'supplier_invoices',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'invoice_date DESC, created_at DESC',
    );

    return rows.map(SupplierInvoice.fromMap).toList();
  }

  // GET ONE INVOICE

  Future<SupplierInvoice?> getInvoiceById(String invoiceId) async {
    final rows = await _db.query(
      'supplier_invoices',
      where: 'id = ?',
      whereArgs: [invoiceId.trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return SupplierInvoice.fromMap(rows.first);
  }

  // GET PAYMENTS FOR AN INVOICE

  Future<List<SupplierPayment>> getPaymentsForInvoice(
    String invoiceId,
  ) async {
    final rows = await _db.query(
      'supplier_payments',
      where: 'supplier_invoice_id = ?',
      whereArgs: [invoiceId.trim()],
      orderBy: 'occurred_at DESC',
    );

    return rows.map(SupplierPayment.fromMap).toList();
  }

  // GET TOTAL PAID

  Future<int> getTotalPaidMinor(String invoiceId) async {
    final result = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_minor), 0) AS total_paid
      FROM supplier_payments
      WHERE supplier_invoice_id = ?
      ''',
      [invoiceId.trim()],
    );

    return (result.first['total_paid'] as num).toInt();
  }

  // GET OUTSTANDING BALANCE

  Future<int> getOutstandingBalanceMinor(String invoiceId) async {
    final rows = await _db.query(
      'supplier_invoices',
      columns: ['total_minor', 'status'],
      where: 'id = ?',
      whereArgs: [invoiceId.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError('Supplier invoice does not exist.');
    }

    if (rows.first['status'] == 'void') {
      return 0;
    }

    final total = (rows.first['total_minor'] as num).toInt();
    final paid = await getTotalPaidMinor(invoiceId);

    return total - paid;
  }

  // RECORD SUPPLIER PAYMENT

  Future<SupplierPayment> recordPayment({
    required String supplierInvoiceId,
    required int amountMinor,
    required String paymentMethod,
    required String paidBy,
    required String deviceId,
    String? reference,
    DateTime? occurredAt,
  }) async {
    final cleanInvoiceId = supplierInvoiceId.trim();
    final cleanMethod = paymentMethod.trim();

    if (cleanInvoiceId.isEmpty) {
      throw ArgumentError('Invoice is required.');
    }

    if (amountMinor <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }

    if (cleanMethod.isEmpty) {
      throw ArgumentError('Payment method is required.');
    }

    _validateActor(paidBy, deviceId);

    final now = DateTime.now().toUtc();

    late SupplierPayment payment;

    await _db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'supplier_invoices',
        where: 'id = ?',
        whereArgs: [cleanInvoiceId],
        limit: 1,
      );

      if (invoiceRows.isEmpty) {
        throw StateError('Supplier invoice does not exist.');
      }

      final invoice = SupplierInvoice.fromMap(invoiceRows.first);

      if (invoice.status == 'void') {
        throw StateError('Cannot pay a void invoice.');
      }

      if (invoice.status == 'paid') {
        throw StateError('This invoice is already fully paid.');
      }

      final paidRows = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(amount_minor), 0) AS total_paid
        FROM supplier_payments
        WHERE supplier_invoice_id = ?
        ''',
        [cleanInvoiceId],
      );

      final alreadyPaid =
          (paidRows.first['total_paid'] as num).toInt();

      final balance = invoice.totalMinor - alreadyPaid;

      if (amountMinor > balance) {
        throw StateError(
          'Payment exceeds the outstanding invoice balance.',
        );
      }

      payment = SupplierPayment(
        id: _uuid.v4(),
        supplierInvoiceId: invoice.id,
        supplierId: invoice.supplierId,
        amountMinor: amountMinor,
        paymentMethod: cleanMethod,
        reference: _cleanOptional(reference),
        paidBy: paidBy.trim(),
        deviceId: deviceId.trim(),
        occurredAt: (occurredAt ?? now).toUtc().toIso8601String(),
        createdAt: now.toIso8601String(),
      );

      await txn.insert('supplier_payments', payment.toMap());

      final newPaidTotal = alreadyPaid + amountMinor;
      final newStatus =
          newPaidTotal >= invoice.totalMinor ? 'paid' : 'part_paid';

      final updatedInvoice = SupplierInvoice(
        id: invoice.id,
        supplierId: invoice.supplierId,
        invoiceNumber: invoice.invoiceNumber,
        purchaseOrderId: invoice.purchaseOrderId,
        invoiceDate: invoice.invoiceDate,
        dueDate: invoice.dueDate,
        subtotalMinor: invoice.subtotalMinor,
        taxMinor: invoice.taxMinor,
        otherChargesMinor: invoice.otherChargesMinor,
        totalMinor: invoice.totalMinor,
        status: newStatus,
        notes: invoice.notes,
        actorUserId: paidBy.trim(),
        deviceId: deviceId.trim(),
        createdAt: invoice.createdAt,
        updatedAt: now.toIso8601String(),
        syncState: 'pending',
      );

      await txn.update(
        'supplier_invoices',
        {
          'status': newStatus,
          'actor_user_id': paidBy.trim(),
          'device_id': deviceId.trim(),
          'updated_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [invoice.id],
      );

      await _addOutboxEvent(
        txn,
        aggregateId: payment.id,
        eventType: 'supplier_payment.recorded',
        payload: payment.toMap(),
        aggregateType: 'supplier_payment',
        now: now,
      );

      await _addOutboxEvent(
        txn,
        aggregateId: invoice.id,
        eventType: 'supplier_invoice.$newStatus',
        payload: updatedInvoice.toMap(),
        aggregateType: 'supplier_invoice',
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: paidBy,
        deviceId: deviceId,
        action: 'payment_recorded',
        entityType: 'supplier_invoice',
        entityId: invoice.id,
        previousValue: {
          'status': invoice.status,
          'total_paid_minor': alreadyPaid,
          'balance_minor': balance,
        },
        newValue: {
          'payment': payment.toMap(),
          'status': newStatus,
          'total_paid_minor': newPaidTotal,
          'balance_minor': invoice.totalMinor - newPaidTotal,
        },
        now: now,
      );
    });

    return payment;
  }

  // VOID UNPAID INVOICE

  Future<void> voidInvoice({
    required String invoiceId,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanInvoiceId = invoiceId.trim();

    if (cleanInvoiceId.isEmpty) {
      throw ArgumentError('Invoice ID is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'supplier_invoices',
        where: 'id = ?',
        whereArgs: [cleanInvoiceId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Supplier invoice does not exist.');
      }

      final invoice = SupplierInvoice.fromMap(rows.first);

      if (invoice.status == 'void') {
        throw StateError('Invoice is already void.');
      }

      final paymentRows = await txn.query(
        'supplier_payments',
        columns: ['id'],
        where: 'supplier_invoice_id = ?',
        whereArgs: [cleanInvoiceId],
        limit: 1,
      );

      if (paymentRows.isNotEmpty) {
        throw StateError(
          'Cannot void an invoice that has recorded payments.',
        );
      }

      final updatedInvoice = SupplierInvoice(
        id: invoice.id,
        supplierId: invoice.supplierId,
        invoiceNumber: invoice.invoiceNumber,
        purchaseOrderId: invoice.purchaseOrderId,
        invoiceDate: invoice.invoiceDate,
        dueDate: invoice.dueDate,
        subtotalMinor: invoice.subtotalMinor,
        taxMinor: invoice.taxMinor,
        otherChargesMinor: invoice.otherChargesMinor,
        totalMinor: invoice.totalMinor,
        status: 'void',
        notes: invoice.notes,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        createdAt: invoice.createdAt,
        updatedAt: now.toIso8601String(),
        syncState: 'pending',
      );

      await txn.update(
        'supplier_invoices',
        {
          'status': 'void',
          'actor_user_id': actorUserId.trim(),
          'device_id': deviceId.trim(),
          'updated_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [invoice.id],
      );

      await _addOutboxEvent(
        txn,
        aggregateId: invoice.id,
        eventType: 'supplier_invoice.voided',
        payload: updatedInvoice.toMap(),
        aggregateType: 'supplier_invoice',
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'void',
        entityType: 'supplier_invoice',
        entityId: invoice.id,
        previousValue: invoice.toMap(),
        newValue: updatedInvoice.toMap(),
        now: now,
      );
    });
  }

  // HELPERS

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  void _validateActor(String actorUserId, String deviceId) {
    if (actorUserId.trim().isEmpty) {
      throw ArgumentError('Actor user ID is required.');
    }

    if (deviceId.trim().isEmpty) {
      throw ArgumentError('Device ID is required.');
    }
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
    required String aggregateType,
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
      'actor_user_id': actorUserId.trim(),
      'device_id': deviceId.trim(),
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json':
          newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }
}
