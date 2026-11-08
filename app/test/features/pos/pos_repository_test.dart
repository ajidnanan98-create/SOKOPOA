import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/pos/models/sale_cart_item.dart';
import 'package:sokopoa/features/pos/models/sale_payment.dart';
import 'package:sokopoa/features/pos/repositories/pos_repository.dart';

void main() {
  late Database database;
  late PosRepository repository;

  const actor = 'test-user';
  const device = 'test-device';
  const productId = 'product-001';
  const customerId = 'customer-001';

  final saleDate = DateTime(2026, 11, 6, 14, 30);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              code TEXT UNIQUE,
              name TEXT NOT NULL,
              category TEXT,
              description TEXT,
              base_unit TEXT NOT NULL,
              buying_cost_minor INTEGER NOT NULL DEFAULT 0,
              selling_price_minor INTEGER NOT NULL DEFAULT 0,
              minimum_quantity REAL NOT NULL DEFAULT 0,
              active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending',
              image_path TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE product_units (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL REFERENCES products(id),
              unit_name TEXT NOT NULL,
              base_units_per_unit REAL NOT NULL
                CHECK(base_units_per_unit > 0),
              UNIQUE(product_id, unit_name)
            )
          ''');

          await db.execute('''
            CREATE TABLE workers (
              id TEXT PRIMARY KEY,
              full_name TEXT NOT NULL,
              phone TEXT,
              role TEXT NOT NULL,
              active INTEGER NOT NULL DEFAULT 1,
              hired_at TEXT,
              created_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

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
              served_by_worker_id TEXT REFERENCES workers(id),
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
            CREATE TABLE sale_lines (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL REFERENCES sales(id),
              product_id TEXT NOT NULL REFERENCES products(id),
              quantity REAL NOT NULL CHECK(quantity > 0),
              unit_name TEXT NOT NULL,
              base_quantity REAL NOT NULL CHECK(base_quantity > 0),
              unit_price_minor INTEGER NOT NULL,
              cost_minor INTEGER NOT NULL,
              line_total_minor INTEGER NOT NULL
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
            CREATE TABLE stock_movements (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL REFERENCES products(id),
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

    repository = PosRepository(database: database);

    final now = saleDate.toIso8601String();

    await database.insert('products', {
      'id': productId,
      'code': 'SOAP-001',
      'name': 'Test Soap',
      'base_unit': 'piece',
      'buying_cost_minor': 5000,
      'selling_price_minor': 7000,
      'minimum_quantity': 5,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert('product_units', {
      'id': 'unit-001',
      'product_id': productId,
      'unit_name': 'carton',
      'base_units_per_unit': 24,
    });

    await database.insert('customers', {
      'id': customerId,
      'name': 'Test Customer',
      'credit_limit_minor': 100000,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert('workers', {
      'id': 'worker-001',
      'full_name': 'Test Worker',
      'role': 'sales',
      'active': 1,
      'created_at': now,
    });

    await database.insert('stock_movements', {
      'id': 'opening-stock-001',
      'product_id': productId,
      'movement_type': 'adjustment_in',
      'quantity_base': 100,
      'unit_name': 'piece',
      'entered_quantity': 100,
      'conversion_factor': 1,
      'reference_type': 'opening_stock',
      'actor_user_id': actor,
      'device_id': device,
      'occurred_at': now,
    });
  });

  tearDown(() async {
    await database.close();
  });

  SaleCartItem item({
    double quantity = 1,
    String unitName = 'piece',
    double conversionFactor = 1,
  }) {
    return SaleCartItem(
      productId: productId,
      productName: 'Test Soap',
      unitName: unitName,
      quantity: quantity,
      conversionFactor: conversionFactor,
      unitPriceMinor: 7000,
      costPerBaseUnitMinor: 5000,
    );
  }

  Future<dynamic> complete({
    List<SaleCartItem>? cartItems,
    List<SalePayment> payments = const [
      SalePayment(method: 'cash', amountMinor: 7000),
    ],
    String? selectedCustomerId,
    String? workerId,
    int discountMinor = 0,
  }) {
    return repository.completeSale(
      cartItems: cartItems ?? [item()],
      payments: payments,
      cashierUserId: actor,
      deviceId: device,
      customerId: selectedCustomerId,
      servedByWorkerId: workerId,
      discountMinor: discountMinor,
      occurredAt: saleDate,
    );
  }

  Future<double> stockBalance() async {
    final rows = await database.rawQuery('''
      SELECT COALESCE(SUM(quantity_base), 0) AS balance
      FROM stock_movements
      WHERE product_id = ?
    ''', [productId]);

    return (rows.first['balance'] as num).toDouble();
  }

  test('completes a cash sale and deducts stock correctly', () async {
    final result = await complete();

    expect(result.receiptNumber, 'SOK-20261106-0001');
    expect(result.subtotalMinor, 7000);
    expect(result.discountMinor, 0);
    expect(result.totalMinor, 7000);
    expect(result.paidMinor, 7000);
    expect(result.balanceMinor, 0);
    expect(result.status, 'paid');

    expect(await stockBalance(), 99);

    final sales = await database.query('sales');
    final lines = await database.query('sale_lines');
    final payments = await database.query('payments');

    expect(sales.length, 1);
    expect(lines.length, 1);
    expect(payments.length, 1);

    expect(lines.first['unit_price_minor'], 7000);
    expect(lines.first['cost_minor'], 5000);
    expect(lines.first['line_total_minor'], 7000);

    expect(payments.first['method'], 'cash');
    expect(payments.first['amount_minor'], 7000);
  });

  test('converts carton sales into base stock units correctly', () async {
    final result = await complete(
      cartItems: [
        item(
          quantity: 2,
          unitName: 'carton',
          conversionFactor: 24,
        ),
      ],
      payments: [
        SalePayment(method: 'cash', amountMinor: 336000),
      ],
    );
    expect(result.subtotalMinor, 336000);
    expect(result.totalMinor, 336000);

    expect(await stockBalance(), 52);

    final lines = await database.query('sale_lines');
    expect(lines.first['quantity'], 2);
    expect(lines.first['unit_name'], 'carton');
    expect(lines.first['base_quantity'], 48);
    expect(lines.first['unit_price_minor'], 168000);
    expect(lines.first['cost_minor'], 240000);

    final movements = await database.query(
      'stock_movements',
      where: 'movement_type = ?',
      whereArgs: ['sale'],
    );

    expect(movements.length, 1);
    expect(movements.first['quantity_base'], -48);
    expect(movements.first['conversion_factor'], 24);
  });

  test('supports split payments', () async {
    final result = await complete(
      payments: const [
        SalePayment(method: 'cash', amountMinor: 3000),
        SalePayment(
          method: 'mpesa',
          amountMinor: 4000,
          reference: 'MPESA-123',
        ),
      ],
    );

    expect(result.status, 'paid');
    expect(result.paidMinor, 7000);
    expect(result.balanceMinor, 0);

    final payments = await database.query('payments');

    expect(payments.length, 2);
    expect(
      payments.fold<int>(
        0,
        (total, payment) => total + (payment['amount_minor'] as int),
      ),
      7000,
    );
  });

  test('records a partial payment against a customer sale', () async {
    final result = await complete(
      selectedCustomerId: customerId,
      payments: const [
        SalePayment(method: 'mpesa', amountMinor: 2000),
      ],
    );

    expect(result.status, 'part_paid');
    expect(result.paidMinor, 2000);
    expect(result.balanceMinor, 5000);

    final sales = await database.query('sales');

    expect(sales.first['paid_minor'], 2000);
    expect(sales.first['status'], 'part_paid');
  });

  test('allows a full credit sale within the customer credit limit', () async {
    final result = await complete(
      selectedCustomerId: customerId,
      payments: const [],
    );

    expect(result.status, 'unpaid');
    expect(result.paidMinor, 0);
    expect(result.balanceMinor, 7000);

    expect(await database.query('payments'), isEmpty);
  });

  test('rejects credit sales without a customer', () async {
    await expectLater(
      complete(payments: const []),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await stockBalance(), 100);
  });

  test('rejects credit exceeding the customer credit limit', () async {
    await database.update(
      'customers',
      {'credit_limit_minor': 6000},
      where: 'id = ?',
      whereArgs: [customerId],
    );

    await expectLater(
      complete(
        selectedCustomerId: customerId,
        payments: const [],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await stockBalance(), 100);
  });

  test('rejects overselling and leaves stock unchanged', () async {
    await expectLater(
      complete(
        cartItems: [item(quantity: 101)],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await database.query('sale_lines'), isEmpty);
    expect(await database.query('payments'), isEmpty);
    expect(await stockBalance(), 100);
  });

  test('rejects payments greater than the sale total', () async {
    await expectLater(
      complete(
        payments: const [
          SalePayment(method: 'cash', amountMinor: 8000),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await stockBalance(), 100);
  });

  test('rejects a conversion factor that differs from the database', () async {
    await expectLater(
      complete(
        cartItems: [
          item(
            quantity: 1,
            unitName: 'carton',
            conversionFactor: 12,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await stockBalance(), 100);
  });

  test('generates sequential daily receipt numbers', () async {
    final first = await complete();

    final second = await complete(
      cartItems: [item(quantity: 2)],
      payments: const [
        SalePayment(method: 'cash', amountMinor: 14000),
      ],
    );

    expect(first.receiptNumber, 'SOK-20261106-0001');
    expect(second.receiptNumber, 'SOK-20261106-0002');
  });

  test('records audit and sync events for a completed sale', () async {
    await complete();

    final outbox = await database.query('sync_outbox');
    final audit = await database.query('audit_log');

    expect(
      outbox.any((row) => row['event_type'] == 'sale.completed'),
      isTrue,
    );

    expect(
      outbox.any((row) => row['event_type'] == 'stock.sale_recorded'),
      isTrue,
    );

    expect(
      outbox.any((row) => row['event_type'] == 'payment.sale_received'),
      isTrue,
    );

    expect(
      audit.any(
        (row) => row['entity_type'] == 'sale' && row['action'] == 'complete',
      ),
      isTrue,
    );
  });

  test('rejects a sale assigned to an inactive worker', () async {
    await database.update(
      'workers',
      {'active': 0},
      where: 'id = ?',
      whereArgs: ['worker-001'],
    );

    await expectLater(
      complete(workerId: 'worker-001'),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('sales'), isEmpty);
    expect(await stockBalance(), 100);
  });
}
