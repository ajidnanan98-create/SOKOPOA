import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/expense.dart';

class ExpenseRepository {
  ExpenseRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  static const supportedPaymentMethods = <String>[
    'cash',
    'mpesa',
    'card',
    'bank',
  ];

  // CREATE EXPENSE
  Future<Expense> createExpense({
    required String category,
    required int amountMinor,
    required String paymentMethod,
    String? description,
    required String actorUserId,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final cleanCategory = category.trim();
    final cleanMethod = paymentMethod.trim().toLowerCase();
    final cleanDescription = _cleanOptional(description);

    if (cleanCategory.isEmpty) {
      throw ArgumentError('Expense category is required.');
    }

    if (amountMinor <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }

    _validatePaymentMethod(cleanMethod);
    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    final expense = Expense(
      id: _uuid.v4(),
      category: cleanCategory,
      amountMinor: amountMinor,
      paymentMethod: cleanMethod,
      description: cleanDescription,
      actorUserId: actorUserId.trim(),
      occurredAt: (occurredAt ?? now).toUtc(),
    );

    await _db.transaction((txn) async {
      await txn.insert('expenses', expense.toMap());

      await _addOutboxEvent(
        txn,
        expenseId: expense.id,
        eventType: 'expense.created',
        payload: expense.toMap(),
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        expenseId: expense.id,
        newValue: expense.toMap(),
        now: now,
      );
    });

    return expense;
  }

  // GET EXPENSES
  Future<List<Expense>> getExpenses({
    String? search,
    String? category,
    DateTime? from,
    DateTime? to,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];

    final cleanSearch = search?.trim();
    final cleanCategory = category?.trim();

    if (cleanSearch != null && cleanSearch.isNotEmpty) {
      conditions.add('''
        (
          LOWER(category) LIKE ?
          OR LOWER(COALESCE(description, '')) LIKE ?
        )
      ''');

      final value = '%${cleanSearch.toLowerCase()}%';
      arguments.addAll([value, value]);
    }

    if (cleanCategory != null && cleanCategory.isNotEmpty) {
      conditions.add('category = ?');
      arguments.add(cleanCategory);
    }

    if (from != null) {
      conditions.add('occurred_at >= ?');
      arguments.add(from.toUtc().toIso8601String());
    }

    if (to != null) {
      conditions.add('occurred_at <= ?');
      arguments.add(to.toUtc().toIso8601String());
    }

    final rows = await _db.query(
      'expenses',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: conditions.isEmpty ? null : arguments,
      orderBy: 'occurred_at DESC',
    );

    return rows.map(Expense.fromMap).toList();
  }

  // GET EXPENSE BY ID
  Future<Expense?> getExpenseById(String expenseId) async {
    final rows = await _db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Expense.fromMap(rows.first);
  }

  // UPDATE EXPENSE
  Future<Expense> updateExpense({
    required String expenseId,
    required String category,
    required int amountMinor,
    required String paymentMethod,
    String? description,
    required String actorUserId,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final cleanCategory = category.trim();
    final cleanMethod = paymentMethod.trim().toLowerCase();

    if (cleanCategory.isEmpty) {
      throw ArgumentError('Expense category is required.');
    }

    if (amountMinor <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }

    _validatePaymentMethod(cleanMethod);
    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late Expense updatedExpense;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Expense was not found.');
      }

      final previous = rows.first;

      final updated = {
        ...previous,
        'category': cleanCategory,
        'amount_minor': amountMinor,
        'payment_method': cleanMethod,
        'description': _cleanOptional(description),
        'occurred_at':
            (occurredAt ?? DateTime.parse(previous['occurred_at'] as String))
                .toUtc()
                .toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'expenses',
        updated,
        where: 'id = ?',
        whereArgs: [expenseId],
      );

      updatedExpense = Expense.fromMap(updated);

      await _addOutboxEvent(
        txn,
        expenseId: expenseId,
        eventType: 'expense.updated',
        payload: updated,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'update',
        expenseId: expenseId,
        previousValue: previous,
        newValue: updated,
        now: now,
      );
    });

    return updatedExpense;
  }

  // DELETE EXPENSE
  Future<void> deleteExpense({
    required String expenseId,
    required String actorUserId,
    required String deviceId,
  }) async {
    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Expense was not found.');
      }

      final previous = rows.first;

      await txn.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
      );

      await _addOutboxEvent(
        txn,
        expenseId: expenseId,
        eventType: 'expense.deleted',
        payload: previous,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'delete',
        expenseId: expenseId,
        previousValue: previous,
        now: now,
      );
    });
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
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError(
        'User and device identifiers are required.',
      );
    }
  }

  void _validatePaymentMethod(String method) {
    if (!supportedPaymentMethods.contains(method)) {
      throw ArgumentError('Unsupported expense payment method.');
    }
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String expenseId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': 'expense',
      'aggregate_id': expenseId,
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
    required String expenseId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': 'expense',
      'entity_id': expenseId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json': newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }
}
