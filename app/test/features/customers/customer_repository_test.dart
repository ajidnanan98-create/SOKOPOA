import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sokopoa/features/pos/models/sale_payment.dart';

import 'package:sokopoa/features/customers/repositories/customer_repository.dart';

void main() {
  late Database database;
  late CustomerRepository repository;

  const actor = 'test-user';
  const device = 'test-device';

  final now = DateTime.utc(2026, 11, 7);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT,
              credit_limit_minor INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE sales (
              id TEXT PRIMARY KEY,
              receipt_number TEXT NOT NULL UNIQUE,
              customer_id TEXT REFERENCES customers(id),
              cashier_user_id TEXT NOT NULL,
              served_by_worker_id TEXT,
              subtotal_minor INTEGER NOT NULL,
              discount_minor INTEGER NOT NULL DEFAULT 0,
              total_minor INTEGER NOT NULL,
              paid_minor INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              device_id TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
          await db.execute('''
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              related_type TEXT NOT NULL,
              related_id TEXT NOT NULL,
              method TEXT NOT NULL,
              amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
              reference TEXT,
              received_by TEXT NOT NULL,
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

    repository = CustomerRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });
  Future<void> insertCreditSale({
    required String id,
    required String receiptNumber,
    required String customerId,
    required int totalMinor,
    int paidMinor = 0,
    String status = 'unpaid',
    String occurredAt = '2026-11-01T10:00:00.000Z',
  }) async {
    await database.insert('sales', {
      'id': id,
      'receipt_number': receiptNumber,
      'customer_id': customerId,
      'cashier_user_id': actor,
      'subtotal_minor': totalMinor,
      'discount_minor': 0,
      'total_minor': totalMinor,
      'paid_minor': paidMinor,
      'status': status,
      'occurred_at': occurredAt,
      'device_id': device,
    });
  }

  group('CustomerRepository', () {
    test('creates a customer with audit and sync records', () async {
      final customer = await repository.createCustomer(
        name: '  Test Customer  ',
        phone: '0712345678',
        email: 'customer@example.com',
        creditLimitMinor: 500000,
        actorUserId: actor,
        deviceId: device,
      );

      expect(customer.name, 'Test Customer');
      expect(customer.phone, '0712345678');
      expect(customer.email, 'customer@example.com');
      expect(customer.creditLimitMinor, 500000);
      expect(customer.syncState, 'pending');

      final customers = await database.query('customers');
      final events = await database.query('sync_outbox');
      final audits = await database.query('audit_log');

      expect(customers, hasLength(1));
      expect(events, hasLength(1));
      expect(events.first['event_type'], 'customer.created');
      expect(audits, hasLength(1));
      expect(audits.first['action'], 'create');
    });

    test('rejects an empty customer name', () async {
      expect(
        () => repository.createCustomer(
          name: '   ',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('customers'), isEmpty);
    });

    test('rejects a negative credit limit', () async {
      expect(
        () => repository.createCustomer(
          name: 'Test Customer',
          creditLimitMinor: -1,
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('customers'), isEmpty);
    });

    test('rejects missing actor or device identifiers', () async {
      expect(
        () => repository.createCustomer(
          name: 'Test Customer',
          actorUserId: '',
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('customers'), isEmpty);
    });

    test('searches customers by name, phone and email', () async {
      await repository.createCustomer(
        name: 'Meru Wholesale',
        phone: '0712345678',
        email: 'meru@example.com',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getCustomers(search: 'meru'),
        hasLength(1),
      );

      expect(
        await repository.getCustomers(search: '071234'),
        hasLength(1),
      );

      expect(
        await repository.getCustomers(search: 'example.com'),
        hasLength(1),
      );

      expect(
        await repository.getCustomers(search: 'unknown'),
        isEmpty,
      );
    });

    test('gets a customer by ID', () async {
      final created = await repository.createCustomer(
        name: 'Customer One',
        actorUserId: actor,
        deviceId: device,
      );

      final found = await repository.getCustomerById(created.id);

      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.name, 'Customer One');
    });

    test('returns null for an unknown customer ID', () async {
      final found = await repository.getCustomerById('missing-id');

      expect(found, isNull);
    });

    test('updates customer details and records audit history', () async {
      final created = await repository.createCustomer(
        name: 'Old Name',
        phone: '0700000000',
        creditLimitMinor: 100000,
        actorUserId: actor,
        deviceId: device,
      );

      final updated = await repository.updateCustomer(
        customerId: created.id,
        name: 'New Name',
        phone: '0711111111',
        email: 'new@example.com',
        creditLimitMinor: 250000,
        actorUserId: actor,
        deviceId: device,
      );

      expect(updated.name, 'New Name');
      expect(updated.phone, '0711111111');
      expect(updated.email, 'new@example.com');
      expect(updated.creditLimitMinor, 250000);

      final events = await database.query(
        'sync_outbox',
        orderBy: 'created_at ASC',
      );
      final audits = await database.query(
        'audit_log',
        orderBy: 'occurred_at ASC',
      );

      expect(events, hasLength(2));
      expect(events.last['event_type'], 'customer.updated');
      expect(audits, hasLength(2));
      expect(audits.last['action'], 'update');
      expect(audits.last['previous_value_json'], isNotNull);
      expect(audits.last['new_value_json'], isNotNull);
    });

    test('rejects updating a customer with a negative credit limit', () async {
      final created = await repository.createCustomer(
        name: 'Customer One',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        () => repository.updateCustomer(
          customerId: created.id,
          name: 'Customer One',
          creditLimitMinor: -100,
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );
    });

    test('rejects updating a customer that does not exist', () async {
      expect(
        () => repository.updateCustomer(
          customerId: 'missing-id',
          name: 'Customer One',
          creditLimitMinor: 0,
          actorUserId: actor,
          deviceId: device,
        ),
        throwsStateError,
      );
    });

    test('calculates outstanding debt from non-void sales', () async {
      final customer = await repository.createCustomer(
        name: 'Credit Customer',
        creditLimitMinor: 1000000,
        actorUserId: actor,
        deviceId: device,
      );

      await database.insert('sales', {
        'id': 'sale-001',
        'receipt_number': 'TEST-001',
        'customer_id': customer.id,
        'cashier_user_id': actor,
        'subtotal_minor': 300000,
        'discount_minor': 0,
        'total_minor': 300000,
        'paid_minor': 100000,
        'status': 'part_paid',
        'occurred_at': now.toIso8601String(),
        'device_id': device,
      });

      await database.insert('sales', {
        'id': 'sale-002',
        'receipt_number': 'TEST-002',
        'customer_id': customer.id,
        'cashier_user_id': actor,
        'subtotal_minor': 200000,
        'discount_minor': 0,
        'total_minor': 200000,
        'paid_minor': 0,
        'status': 'unpaid',
        'occurred_at': now.toIso8601String(),
        'device_id': device,
      });

      await database.insert('sales', {
        'id': 'sale-003',
        'receipt_number': 'TEST-003',
        'customer_id': customer.id,
        'cashier_user_id': actor,
        'subtotal_minor': 50000,
        'discount_minor': 0,
        'total_minor': 50000,
        'paid_minor': 0,
        'status': 'void',
        'occurred_at': now.toIso8601String(),
        'device_id': device,
      });

      final debt = await repository.getOutstandingDebtMinor(customer.id);

      // KSh 2,000 outstanding + KSh 0 from the void sale.
      expect(debt, 400000);
    });

    test('returns zero debt for a customer without sales', () async {
      final customer = await repository.createCustomer(
        name: 'Cash Customer',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getOutstandingDebtMinor(customer.id),
        0,
      );
    });

    test('allocates repayment to oldest outstanding sales first', () async {
      final customer = await repository.createCustomer(
        name: 'FIFO Customer',
        creditLimitMinor: 1000000,
        actorUserId: actor,
        deviceId: device,
      );

      await insertCreditSale(
        id: 'sale-old',
        receiptNumber: 'FIFO-001',
        customerId: customer.id,
        totalMinor: 100000,
        occurredAt: '2026-11-01T10:00:00.000Z',
      );

      await insertCreditSale(
        id: 'sale-new',
        receiptNumber: 'FIFO-002',
        customerId: customer.id,
        totalMinor: 150000,
        occurredAt: '2026-11-02T10:00:00.000Z',
      );

      final result = await repository.recordRepayment(
        customerId: customer.id,
        payment: const SalePayment(
          method: 'cash',
          amountMinor: 120000,
        ),
        receivedBy: actor,
        actorUserId: actor,
        deviceId: device,
      );

      expect(result.amountMinor, 120000);
      expect(result.allocations, hasLength(2));
      expect(result.allocations[0].saleId, 'sale-old');
      expect(result.allocations[0].amountMinor, 100000);
      expect(result.allocations[0].saleStatus, 'paid');
      expect(result.allocations[1].saleId, 'sale-new');
      expect(result.allocations[1].amountMinor, 20000);
      expect(result.allocations[1].saleStatus, 'part_paid');
      expect(result.remainingDebtMinor, 130000);

      final payments = await database.query('payments');

      expect(payments, hasLength(2));
      expect(
        payments.fold<int>(
          0,
          (sum, row) => sum + (row['amount_minor'] as int),
        ),
        120000,
      );
    });

    test('rejects repayment greater than outstanding debt', () async {
      final customer = await repository.createCustomer(
        name: 'Overpayment Customer',
        actorUserId: actor,
        deviceId: device,
      );

      await insertCreditSale(
        id: 'sale-overpay',
        receiptNumber: 'OVER-001',
        customerId: customer.id,
        totalMinor: 50000,
      );

      expect(
        repository.recordRepayment(
          customerId: customer.id,
          payment: const SalePayment(
            method: 'mpesa',
            amountMinor: 60000,
          ),
          receivedBy: actor,
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      final sale = await database.query(
        'sales',
        where: 'id = ?',
        whereArgs: ['sale-overpay'],
      );

      expect(sale.first['paid_minor'], 0);
      expect(await database.query('payments'), isEmpty);
    });

    test('fully settles a sale and preserves M-PESA reference', () async {
      final customer = await repository.createCustomer(
        name: 'Settlement Customer',
        actorUserId: actor,
        deviceId: device,
      );

      await insertCreditSale(
        id: 'sale-settle',
        receiptNumber: 'SETTLE-001',
        customerId: customer.id,
        totalMinor: 75000,
      );

      final result = await repository.recordRepayment(
        customerId: customer.id,
        payment: const SalePayment(
          method: 'mpesa',
          amountMinor: 75000,
          reference: 'QW12345678',
        ),
        receivedBy: actor,
        actorUserId: actor,
        deviceId: device,
      );

      expect(result.remainingDebtMinor, 0);
      expect(result.reference, 'QW12345678');
      expect(result.allocations.single.saleStatus, 'paid');

      final sale = await database.query(
        'sales',
        where: 'id = ?',
        whereArgs: ['sale-settle'],
      );

      expect(sale.first['paid_minor'], 75000);
      expect(sale.first['status'], 'paid');

      final payments = await database.query('payments');

      expect(payments, hasLength(1));
      expect(payments.first['reference'], 'QW12345678');
    });

    test('returns repayment history with the linked sale receipt', () async {
      final customer = await repository.createCustomer(
        name: 'History Customer',
        actorUserId: actor,
        deviceId: device,
      );

      await insertCreditSale(
        id: 'sale-history',
        receiptNumber: 'HISTORY-001',
        customerId: customer.id,
        totalMinor: 50000,
      );

      await repository.recordRepayment(
        customerId: customer.id,
        payment: const SalePayment(
          method: 'mpesa',
          amountMinor: 20000,
          reference: 'MPESA12345',
        ),
        receivedBy: actor,
        actorUserId: actor,
        deviceId: device,
      );

      final history = await repository.getRepaymentHistory(customer.id);

      expect(history, hasLength(1));
      expect(history.single.receiptNumber, 'HISTORY-001');
      expect(history.single.amountMinor, 20000);
      expect(history.single.method, 'mpesa');
      expect(history.single.reference, 'MPESA12345');
      expect(history.single.receivedBy, actor);
      expect(history.single.saleId, 'sale-history');
    });
  });
}
