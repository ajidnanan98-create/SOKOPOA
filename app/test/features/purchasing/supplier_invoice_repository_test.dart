import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/purchasing/repositories/supplier_invoice_repository.dart';

void main() {
  late Database database;
  late SupplierInvoiceRepository repository;

  const supplierId = 'supplier-001';
  const otherSupplierId = 'supplier-002';
  const purchaseOrderId = 'po-001';
  const otherPurchaseOrderId = 'po-002';
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
        version: 5,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE suppliers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT,
              address TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE purchase_orders (
              id TEXT PRIMARY KEY,
              order_number TEXT NOT NULL UNIQUE,
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              status TEXT NOT NULL DEFAULT 'draft',
              ordered_at TEXT,
              expected_at TEXT,
              notes TEXT,
              subtotal_minor INTEGER NOT NULL DEFAULT 0,
              discount_minor INTEGER NOT NULL DEFAULT 0,
              total_minor INTEGER NOT NULL DEFAULT 0,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE supplier_invoices (
              id TEXT PRIMARY KEY,
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              purchase_order_id TEXT REFERENCES purchase_orders(id),
              invoice_number TEXT NOT NULL,
              invoice_date TEXT NOT NULL,
              due_date TEXT,
              subtotal_minor INTEGER NOT NULL
                CHECK(subtotal_minor >= 0),
              tax_minor INTEGER NOT NULL DEFAULT 0
                CHECK(tax_minor >= 0),
              other_charges_minor INTEGER NOT NULL DEFAULT 0
                CHECK(other_charges_minor >= 0),
              total_minor INTEGER NOT NULL CHECK(total_minor > 0),
              status TEXT NOT NULL DEFAULT 'open'
                CHECK(status IN ('open', 'part_paid', 'paid', 'void')),
              notes TEXT,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending',
              UNIQUE(supplier_id, invoice_number)
            )
          ''');

          await db.execute('''
            CREATE TABLE supplier_payments (
              id TEXT PRIMARY KEY,
              supplier_invoice_id TEXT NOT NULL
                REFERENCES supplier_invoices(id),
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
              payment_method TEXT NOT NULL,
              reference TEXT,
              paid_by TEXT NOT NULL,
              device_id TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              created_at TEXT NOT NULL,
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
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              action TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              previous_value_json TEXT,
              new_value_json TEXT,
              reason TEXT,
              occurred_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE stock_movements (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              movement_type TEXT NOT NULL,
              quantity_base REAL NOT NULL,
              unit_name TEXT NOT NULL,
              entered_quantity REAL NOT NULL DEFAULT 0,
              conversion_factor REAL NOT NULL DEFAULT 1,
              reference_type TEXT,
              reference_id TEXT,
              reason TEXT,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');
        },
      ),
    );

    repository = SupplierInvoiceRepository(database: database);

    final now = DateTime.utc(2026, 11, 6).toIso8601String();

    await database.insert('suppliers', {
      'id': supplierId,
      'name': 'Test Supplier',
      'created_at': now,
      'updated_at': now,
      'sync_state': 'pending',
    });

    await database.insert('suppliers', {
      'id': otherSupplierId,
      'name': 'Other Supplier',
      'created_at': now,
      'updated_at': now,
      'sync_state': 'pending',
    });

    await database.insert('purchase_orders', {
      'id': purchaseOrderId,
      'order_number': 'PO-001',
      'supplier_id': supplierId,
      'status': 'ordered',
      'subtotal_minor': 10000,
      'discount_minor': 0,
      'total_minor': 10000,
      'actor_user_id': actor,
      'device_id': device,
      'created_at': now,
      'updated_at': now,
      'sync_state': 'pending',
    });

    await database.insert('purchase_orders', {
      'id': otherPurchaseOrderId,
      'order_number': 'PO-002',
      'supplier_id': otherSupplierId,
      'status': 'ordered',
      'subtotal_minor': 10000,
      'discount_minor': 0,
      'total_minor': 10000,
      'actor_user_id': actor,
      'device_id': device,
      'created_at': now,
      'updated_at': now,
      'sync_state': 'pending',
    });
  });

  tearDown(() async {
    await database.close();
  });

  Future<dynamic> createInvoice({
    String number = 'INV-001',
    String supplier = supplierId,
    String? linkedOrder,
    int subtotal = 10000,
    int tax = 0,
    int otherCharges = 0,
  }) {
    return repository.createInvoice(
      supplierId: supplier,
      invoiceNumber: number,
      invoiceDate: DateTime(2026, 11, 6),
      subtotalMinor: subtotal,
      taxMinor: tax,
      otherChargesMinor: otherCharges,
      purchaseOrderId: linkedOrder,
      actorUserId: actor,
      deviceId: device,
    );
  }

  Future<dynamic> recordPayment(
    String invoiceId, {
    int amount = 3000,
    String method = 'M-Pesa',
    String paidBy = actor,
    String paymentDevice = device,
    String? reference,
  }) {
    return repository.recordPayment(
      supplierInvoiceId: invoiceId,
      amountMinor: amount,
      paymentMethod: method,
      paidBy: paidBy,
      deviceId: paymentDevice,
      reference: reference,
    );
  }

  test('creates an invoice with the correct total and open status', () async {
    final invoice = await createInvoice(
      subtotal: 10000,
      tax: 1000,
      otherCharges: 500,
    );

    expect(invoice.supplierId, supplierId);
    expect(invoice.invoiceNumber, 'INV-001');
    expect(invoice.subtotalMinor, 10000);
    expect(invoice.taxMinor, 1000);
    expect(invoice.otherChargesMinor, 500);
    expect(invoice.totalMinor, 11500);
    expect(invoice.status, 'open');

    expect(
      await repository.getOutstandingBalanceMinor(invoice.id),
      11500,
    );
  });

  test('creates an invoice linked to a purchase order', () async {
    final invoice = await createInvoice(
      linkedOrder: purchaseOrderId,
    );

    expect(invoice.purchaseOrderId, purchaseOrderId);
  });

  test('rejects an invoice for a missing supplier', () async {
    await expectLater(
      createInvoice(supplier: 'missing-supplier'),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getInvoices(), isEmpty);
  });

  test('rejects a purchase order belonging to another supplier', () async {
    await expectLater(
      createInvoice(linkedOrder: otherPurchaseOrderId),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getInvoices(), isEmpty);
  });

  test('rejects a missing linked purchase order', () async {
    await expectLater(
      createInvoice(linkedOrder: 'missing-po'),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getInvoices(), isEmpty);
  });

  test('rejects duplicate invoice numbers for the same supplier', () async {
    await createInvoice();

    await expectLater(
      createInvoice(),
      throwsA(anything),
    );

    expect(await repository.getInvoices(), hasLength(1));
  });

  test('rejects an invoice with a zero total', () async {
    await expectLater(
      createInvoice(subtotal: 0),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getInvoices(), isEmpty);
  });

  test('rejects negative invoice amounts', () async {
    await expectLater(
      createInvoice(subtotal: -100),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      createInvoice(tax: -100),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      createInvoice(otherCharges: -100),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getInvoices(), isEmpty);
  });

  test('records a partial payment and updates outstanding balance', () async {
    final invoice = await createInvoice();

    await recordPayment(invoice.id, amount: 3000);

    final updated = await repository.getInvoiceById(invoice.id);

    expect(updated!.status, 'part_paid');
    expect(await repository.getTotalPaidMinor(invoice.id), 3000);
    expect(await repository.getOutstandingBalanceMinor(invoice.id), 7000);
  });

  test('records a full payment and marks invoice as paid', () async {
    final invoice = await createInvoice();

    await recordPayment(invoice.id, amount: 10000);

    final updated = await repository.getInvoiceById(invoice.id);

    expect(updated!.status, 'paid');
    expect(await repository.getTotalPaidMinor(invoice.id), 10000);
    expect(await repository.getOutstandingBalanceMinor(invoice.id), 0);
  });

  test('supports multiple partial payments', () async {
    final invoice = await createInvoice();

    await recordPayment(invoice.id, amount: 2000);
    await recordPayment(invoice.id, amount: 3000);
    await recordPayment(invoice.id, amount: 5000);

    final updated = await repository.getInvoiceById(invoice.id);

    expect(updated!.status, 'paid');
    expect(await repository.getTotalPaidMinor(invoice.id), 10000);
    expect(await repository.getOutstandingBalanceMinor(invoice.id), 0);

    expect(
      await repository.getPaymentsForInvoice(invoice.id),
      hasLength(3),
    );
  });

  test('rejects an overpayment without recording it', () async {
    final invoice = await createInvoice();

    await expectLater(
      recordPayment(invoice.id, amount: 10001),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getTotalPaidMinor(invoice.id), 0);
    expect(
      await repository.getPaymentsForInvoice(invoice.id),
      isEmpty,
    );
  });

  test('rejects payment to a missing invoice', () async {
    await expectLater(
      recordPayment('missing-invoice'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects zero and negative payment amounts', () async {
    final invoice = await createInvoice();

    await expectLater(
      recordPayment(invoice.id, amount: 0),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      recordPayment(invoice.id, amount: -100),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getTotalPaidMinor(invoice.id), 0);
  });

  test('rejects an empty payment method', () async {
    final invoice = await createInvoice();

    await expectLater(
      recordPayment(invoice.id, method: '  '),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPaymentsForInvoice(invoice.id), isEmpty);
  });

  test('rejects an empty payment actor or device', () async {
    final invoice = await createInvoice();

    await expectLater(
      recordPayment(invoice.id, paidBy: '  '),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      recordPayment(invoice.id, paymentDevice: '  '),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPaymentsForInvoice(invoice.id), isEmpty);
  });

  test('rejects payment to a void invoice', () async {
    final invoice = await createInvoice();

    await repository.voidInvoice(
      invoiceId: invoice.id,
      actorUserId: actor,
      deviceId: device,
    );

    await expectLater(
      recordPayment(invoice.id),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getPaymentsForInvoice(invoice.id), isEmpty);
  });

  test('voids an unpaid invoice and gives it zero outstanding balance',
      () async {
    final invoice = await createInvoice();

    await repository.voidInvoice(
      invoiceId: invoice.id,
      actorUserId: actor,
      deviceId: device,
    );

    final updated = await repository.getInvoiceById(invoice.id);

    expect(updated!.status, 'void');
    expect(await repository.getOutstandingBalanceMinor(invoice.id), 0);
  });

  test('does not allow an invoice with payments to be voided', () async {
    final invoice = await createInvoice();

    await recordPayment(invoice.id, amount: 1000);

    await expectLater(
      repository.voidInvoice(
        invoiceId: invoice.id,
        actorUserId: actor,
        deviceId: device,
      ),
      throwsA(isA<StateError>()),
    );

    final updated = await repository.getInvoiceById(invoice.id);

    expect(updated!.status, 'part_paid');
    expect(await repository.getTotalPaidMinor(invoice.id), 1000);
  });

  test('rejects voiding an invoice twice', () async {
    final invoice = await createInvoice();

    await repository.voidInvoice(
      invoiceId: invoice.id,
      actorUserId: actor,
      deviceId: device,
    );

    await expectLater(
      repository.voidInvoice(
        invoiceId: invoice.id,
        actorUserId: actor,
        deviceId: device,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects voiding a missing invoice', () async {
    await expectLater(
      repository.voidInvoice(
        invoiceId: 'missing-invoice',
        actorUserId: actor,
        deviceId: device,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('records invoice and payment audit entries and outbox events', () async {
    final invoice = await createInvoice();

    await recordPayment(
      invoice.id,
      amount: 3000,
      reference: 'MPESA-123',
    );

    final invoiceAudit = await database.query(
      'audit_log',
      where: 'entity_id = ?',
      whereArgs: [invoice.id],
    );

    final paymentAudit = await database.query(
      'audit_log',
      where: 'entity_id = ? AND action = ?',
      whereArgs: [invoice.id, 'payment_recorded'],
    );

    final invoiceOutbox = await database.query(
      'sync_outbox',
      where: 'aggregate_id = ?',
      whereArgs: [invoice.id],
    );

    final paymentOutbox = await database.query(
      'sync_outbox',
      where: 'aggregate_type = ?',
      whereArgs: ['supplier_payment'],
    );

    expect(invoiceAudit, isNotEmpty);
    expect(invoiceAudit.any((row) => row['action'] == 'create'), isTrue);

    expect(paymentAudit, hasLength(1));
    expect(paymentAudit.single['action'], 'payment_recorded');

    expect(invoiceOutbox, isNotEmpty);
    expect(
      invoiceOutbox.any(
        (row) => row['event_type'] == 'supplier_invoice.created',
      ),
      isTrue,
    );

    expect(paymentOutbox, hasLength(1));
    expect(
      paymentOutbox.single['event_type'],
      'supplier_payment.recorded',
    );
  });

  test('voiding an invoice records audit and sync events', () async {
    final invoice = await createInvoice();

    await repository.voidInvoice(
      invoiceId: invoice.id,
      actorUserId: actor,
      deviceId: device,
    );

    final audit = await database.query(
      'audit_log',
      where: 'entity_id = ?',
      whereArgs: [invoice.id],
    );

    final outbox = await database.query(
      'sync_outbox',
      where: 'aggregate_id = ?',
      whereArgs: [invoice.id],
    );

    expect(
      audit.any((row) => row['action'] == 'void'),
      isTrue,
    );

    expect(
      outbox.any(
        (row) => row['event_type'] == 'supplier_invoice.voided',
      ),
      isTrue,
    );
  });

  test('invoice and payment operations do not change physical stock', () async {
    final invoice = await createInvoice();

    await recordPayment(invoice.id, amount: 3000);

    final movements = await database.query('stock_movements');

    expect(movements, isEmpty);
  });

  test('filters invoices by supplier and status', () async {
    await createInvoice(number: 'INV-OPEN');

    final second = await createInvoice(
      number: 'INV-OTHER',
      supplier: otherSupplierId,
    );

    await recordPayment(second.id, amount: 3000);

    final openInvoices = await repository.getInvoices(status: 'open');
    final partialInvoices = await repository.getInvoices(status: 'part_paid');

    final supplierInvoices = await repository.getInvoices(
      supplierId: supplierId,
    );

    expect(openInvoices, hasLength(1));
    expect(openInvoices.single.invoiceNumber, 'INV-OPEN');

    expect(partialInvoices, hasLength(1));
    expect(partialInvoices.single.invoiceNumber, 'INV-OTHER');

    expect(supplierInvoices, hasLength(1));
    expect(supplierInvoices.single.invoiceNumber, 'INV-OPEN');
  });

  test('searches invoices by invoice number', () async {
    await createInvoice(number: 'SUPPLIER-INV-2026');

    final results = await repository.getInvoices(
      search: 'SUPPLIER-INV',
    );

    expect(results, hasLength(1));
    expect(results.single.invoiceNumber, 'SUPPLIER-INV-2026');
  });
}
