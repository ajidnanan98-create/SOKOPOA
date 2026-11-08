import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/expenses/repositories/expense_repository.dart';

void main() {
  late Database database;
  late ExpenseRepository repository;

  const actor = 'test-user';
  const device = 'test-device';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE expenses (
              id TEXT PRIMARY KEY,
              category TEXT NOT NULL,
              amount_minor INTEGER NOT NULL,
              payment_method TEXT NOT NULL,
              description TEXT,
              actor_user_id TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE sync_outbox (
              event_id TEXT PRIMARY KEY,
              aggregate_type TEXT NOT NULL,
              aggregate_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              status TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE audit_log (
              id TEXT PRIMARY KEY,
              actor_user_id TEXT,
              device_id TEXT,
              action TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT,
              previous_value_json TEXT,
              new_value_json TEXT,
              reason TEXT,
              occurred_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );

    repository = ExpenseRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('ExpenseRepository', () {
    test('creates an expense and records sync and audit entries', () async {
      final expense = await repository.createExpense(
        category: '  Transport ',
        amountMinor: 150000,
        paymentMethod: ' cash ',
        description: ' Delivery transport ',
        actorUserId: actor,
        deviceId: device,
      );

      expect(expense.category, 'Transport');
      expect(expense.amountMinor, 150000);
      expect(expense.paymentMethod, 'cash');
      expect(expense.description, 'Delivery transport');
      expect(expense.actorUserId, actor);
      expect(expense.syncState, 'pending');

      final rows = await database.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      expect(rows, hasLength(1));

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [expense.id],
      );

      expect(events, hasLength(1));
      expect(events.first['event_type'], 'expense.created');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [expense.id],
      );

      expect(audits, hasLength(1));
      expect(audits.first['action'], 'create');
      expect(audits.first['entity_type'], 'expense');
      expect(audits.first['actor_user_id'], actor);
      expect(audits.first['device_id'], device);
    });

    test('creates an expense without an optional description', () async {
      final expense = await repository.createExpense(
        category: 'Rent',
        amountMinor: 250000,
        paymentMethod: 'mpesa',
        actorUserId: actor,
        deviceId: device,
      );

      expect(expense.category, 'Rent');
      expect(expense.description, isNull);
    });

    test('rejects invalid expense details', () async {
      await expectLater(
        repository.createExpense(
          category: ' ',
          amountMinor: 10000,
          paymentMethod: 'cash',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createExpense(
          category: 'Transport',
          amountMinor: 0,
          paymentMethod: 'cash',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createExpense(
          category: 'Transport',
          amountMinor: 10000,
          paymentMethod: 'crypto',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('expenses'), isEmpty);
    });

    test('rejects missing actor or device identifiers', () async {
      await expectLater(
        repository.createExpense(
          category: 'Transport',
          amountMinor: 10000,
          paymentMethod: 'cash',
          actorUserId: '',
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createExpense(
          category: 'Transport',
          amountMinor: 10000,
          paymentMethod: 'cash',
          actorUserId: actor,
          deviceId: ' ',
        ),
        throwsArgumentError,
      );

      expect(await database.query('expenses'), isEmpty);
    });

    test('lists expenses newest first', () async {
      await repository.createExpense(
        category: 'Transport',
        amountMinor: 10000,
        paymentMethod: 'cash',
        actorUserId: actor,
        deviceId: device,
        occurredAt: DateTime.utc(2026, 11, 1),
      );

      await repository.createExpense(
        category: 'Electricity',
        amountMinor: 20000,
        paymentMethod: 'mpesa',
        actorUserId: actor,
        deviceId: device,
        occurredAt: DateTime.utc(2026, 11, 2),
      );

      final expenses = await repository.getExpenses();

      expect(expenses, hasLength(2));
      expect(expenses.first.category, 'Electricity');
      expect(expenses.last.category, 'Transport');
    });

    test('searches expenses by category and description', () async {
      await repository.createExpense(
        category: 'Transport',
        amountMinor: 10000,
        paymentMethod: 'cash',
        description: 'Delivery to customer',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.createExpense(
        category: 'Electricity',
        amountMinor: 20000,
        paymentMethod: 'mpesa',
        description: 'Monthly power bill',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getExpenses(search: 'TRANSPORT'),
        hasLength(1),
      );

      expect(
        await repository.getExpenses(search: 'power bill'),
        hasLength(1),
      );

      expect(
        await repository.getExpenses(search: 'not-found'),
        isEmpty,
      );
    });

    test('filters expenses by category', () async {
      await repository.createExpense(
        category: 'Transport',
        amountMinor: 10000,
        paymentMethod: 'cash',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.createExpense(
        category: 'Rent',
        amountMinor: 20000,
        paymentMethod: 'mpesa',
        actorUserId: actor,
        deviceId: device,
      );

      final expenses = await repository.getExpenses(category: 'Rent');

      expect(expenses, hasLength(1));
      expect(expenses.first.category, 'Rent');
    });

    test('retrieves an expense by ID', () async {
      final created = await repository.createExpense(
        category: 'Stock delivery',
        amountMinor: 15000,
        paymentMethod: 'cash',
        actorUserId: actor,
        deviceId: device,
      );

      final found = await repository.getExpenseById(created.id);

      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.category, 'Stock delivery');

      expect(
        await repository.getExpenseById('missing-expense'),
        isNull,
      );
    });

    test('updates an expense and records sync and audit entries', () async {
      final created = await repository.createExpense(
        category: 'Transport',
        amountMinor: 10000,
        paymentMethod: 'cash',
        description: 'Old description',
        actorUserId: actor,
        deviceId: device,
      );

      final updated = await repository.updateExpense(
        expenseId: created.id,
        category: 'Fuel',
        amountMinor: 25000,
        paymentMethod: 'mpesa',
        description: 'Updated description',
        actorUserId: actor,
        deviceId: device,
        occurredAt: DateTime.utc(2026, 11, 5),
      );

      expect(updated.category, 'Fuel');
      expect(updated.amountMinor, 25000);
      expect(updated.paymentMethod, 'mpesa');
      expect(updated.description, 'Updated description');
      expect(updated.occurredAt.toUtc(), DateTime.utc(2026, 11, 5));
      expect(updated.syncState, 'pending');

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
      );

      expect(events, hasLength(2));
      expect(events.last['event_type'], 'expense.updated');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [created.id],
      );

      expect(audits, hasLength(2));
      expect(audits.last['action'], 'update');
      expect(audits.last['previous_value_json'], isNotNull);
      expect(audits.last['new_value_json'], isNotNull);
    });

    test('rejects updating an expense that does not exist', () async {
      await expectLater(
        repository.updateExpense(
          expenseId: 'missing-expense',
          category: 'Rent',
          amountMinor: 10000,
          paymentMethod: 'cash',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsStateError,
      );
    });

    test('deletes an expense and records sync and audit entries', () async {
      final created = await repository.createExpense(
        category: 'Repairs',
        amountMinor: 50000,
        paymentMethod: 'cash',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.deleteExpense(
        expenseId: created.id,
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getExpenseById(created.id),
        isNull,
      );

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
      );

      expect(events, hasLength(2));
      expect(events.last['event_type'], 'expense.deleted');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [created.id],
      );

      expect(audits, hasLength(2));
      expect(audits.last['action'], 'delete');
      expect(audits.last['previous_value_json'], isNotNull);
    });
  });
}
