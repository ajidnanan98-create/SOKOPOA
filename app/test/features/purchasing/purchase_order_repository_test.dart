import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sokopoa/features/purchasing/repositories/purchase_order_repository.dart';

void main() {
  late Database database;
  late PurchaseOrderRepository repository;

  const actor = 'test-user';
  const device = 'test-device';
  const supplierId = 'supplier-001';
  const productId = 'product-001';

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
            CREATE TABLE purchase_orders (
              id TEXT PRIMARY KEY,
              order_number TEXT NOT NULL UNIQUE,
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              status TEXT NOT NULL DEFAULT 'draft'
                CHECK(status IN (
                  'draft',
                  'ordered',
                  'partially_received',
                  'received',
                  'cancelled'
                )),
              ordered_at TEXT,
              expected_at TEXT,
              notes TEXT,
              subtotal_minor INTEGER NOT NULL DEFAULT 0
                CHECK(subtotal_minor >= 0),
              discount_minor INTEGER NOT NULL DEFAULT 0
                CHECK(discount_minor >= 0),
              total_minor INTEGER NOT NULL DEFAULT 0
                CHECK(total_minor >= 0),
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE purchase_order_lines (
              id TEXT PRIMARY KEY,
              purchase_order_id TEXT NOT NULL
                REFERENCES purchase_orders(id) ON DELETE CASCADE,
              product_id TEXT NOT NULL REFERENCES products(id),
              product_name TEXT NOT NULL,
              product_code TEXT,
              entered_quantity REAL NOT NULL CHECK(entered_quantity > 0),
              unit_name TEXT NOT NULL,
              conversion_factor REAL NOT NULL
                CHECK(conversion_factor > 0),
              base_quantity REAL NOT NULL CHECK(base_quantity > 0),
              unit_cost_minor INTEGER NOT NULL
                CHECK(unit_cost_minor >= 0),
              line_total_minor INTEGER NOT NULL
                CHECK(line_total_minor >= 0),
              created_at TEXT NOT NULL
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

    repository = PurchaseOrderRepository(database: database);

    final now = DateTime.now().toUtc().toIso8601String();

    await database.insert('suppliers', {
      'id': supplierId,
      'name': 'Test Supplier',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert('products', {
      'id': productId,
      'code': 'SOAP-001',
      'name': 'Test Soap',
      'base_unit': 'piece',
      'buying_cost_minor': 5000,
      'selling_price_minor': 7000,
      'minimum_quantity': 10,
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
  });

  tearDown(() async {
    await database.close();
  });

  Future<dynamic> createOrder({
    String orderNumber = 'PO-001',
    String selectedSupplierId = supplierId,
    String selectedProductId = productId,
    double quantity = 2,
    String unitName = 'piece',
    int unitCostMinor = 5000,
    int discountMinor = 0,
  }) {
    return repository.createPurchaseOrder(
      orderNumber: orderNumber,
      supplierId: selectedSupplierId,
      lines: [
        PurchaseOrderLineInput(
          productId: selectedProductId,
          enteredQuantity: quantity,
          unitName: unitName,
          unitCostMinor: unitCostMinor,
        ),
      ],
      actorUserId: actor,
      deviceId: device,
      discountMinor: discountMinor,
    );
  }

  test('creates purchase order with correct totals and records', () async {
    final order = await createOrder(
      quantity: 2,
      unitCostMinor: 5000,
      discountMinor: 1000,
    );

    expect(order.orderNumber, 'PO-001');
    expect(order.status, 'draft');
    expect(order.subtotalMinor, 10000);
    expect(order.discountMinor, 1000);
    expect(order.totalMinor, 9000);

    final lines = await repository.getPurchaseOrderLines(order.id);

    expect(lines.length, 1);
    expect(lines.single.productName, 'Test Soap');
    expect(lines.single.productCode, 'SOAP-001');
    expect(lines.single.enteredQuantity, 2);
    expect(lines.single.unitName, 'piece');
    expect(lines.single.conversionFactor, 1);
    expect(lines.single.baseQuantity, 2);
    expect(lines.single.unitCostMinor, 5000);
    expect(lines.single.lineTotalMinor, 10000);

    final orders = await repository.getPurchaseOrders();
    expect(orders.length, 1);
  });

  test('converts cartons into base units correctly', () async {
    final order = await createOrder(
      orderNumber: 'PO-CARTON-001',
      quantity: 3,
      unitName: 'carton',
      unitCostMinor: 120000,
    );

    final lines = await repository.getPurchaseOrderLines(order.id);

    expect(lines.length, 1);
    expect(lines.single.enteredQuantity, 3);
    expect(lines.single.unitName, 'carton');
    expect(lines.single.conversionFactor, 24);
    expect(lines.single.baseQuantity, 72);
    expect(lines.single.lineTotalMinor, 360000);
  });

  test('purchase order creation does not change stock', () async {
    await createOrder();

    final movements = await database.query('stock_movements');

    expect(movements, isEmpty);
  });

  test('rejects a product that does not exist', () async {
    await expectLater(
      createOrder(selectedProductId: 'missing-product'),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
    expect(
      await database.query('purchase_order_lines'),
      isEmpty,
    );
  });

  test('rejects an inactive product', () async {
    await database.update(
      'products',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [productId],
    );

    await expectLater(
      createOrder(),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('rejects an unregistered packaging unit', () async {
    await expectLater(
      createOrder(unitName: 'crate'),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('rejects a discount greater than the subtotal', () async {
    await expectLater(
      createOrder(
        quantity: 2,
        unitCostMinor: 5000,
        discountMinor: 10001,
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('rejects a negative discount', () async {
    await expectLater(
      createOrder(discountMinor: -100),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('rejects zero or negative entered quantity', () async {
    await expectLater(
      createOrder(quantity: 0),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      createOrder(
        orderNumber: 'PO-NEGATIVE',
        quantity: -2,
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('rejects a negative unit cost', () async {
    await expectLater(
      createOrder(unitCostMinor: -500),
      throwsA(isA<ArgumentError>()),
    );

    expect(await repository.getPurchaseOrders(), isEmpty);
  });

  test('records audit and outbox entries when creating an order', () async {
    final order = await createOrder();

    final auditEntries = await database.query(
      'audit_log',
      where: 'entity_id = ?',
      whereArgs: [order.id],
    );

    final outboxEntries = await database.query(
      'sync_outbox',
      where: 'aggregate_id = ?',
      whereArgs: [order.id],
    );

    expect(auditEntries.length, 1);
    expect(auditEntries.single['action'], 'create');
    expect(auditEntries.single['entity_type'], 'purchase_order');

    expect(outboxEntries.length, 1);
    expect(
      outboxEntries.single['event_type'],
      'purchase_order.created',
    );
    expect(outboxEntries.single['status'], 'pending');
  });

  test('marks a draft purchase order as ordered without changing stock',
      () async {
    final order = await createOrder();

    final updated = await repository.markPurchaseOrderOrdered(
      purchaseOrderId: order.id,
      actorUserId: actor,
      deviceId: device,
    );

    expect(updated.status, 'ordered');
    expect(updated.orderedAt, isNotNull);

    final movements = await database.query('stock_movements');
    expect(movements, isEmpty);

    final outboxEntries = await database.query(
      'sync_outbox',
      where: 'aggregate_id = ?',
      whereArgs: [order.id],
    );

    expect(outboxEntries.length, 2);
    expect(
      outboxEntries.any(
        (entry) => entry['event_type'] == 'purchase_order.ordered',
      ),
      isTrue,
    );
  });

  test('rejects duplicate purchase order numbers', () async {
    await createOrder();

    await expectLater(
      createOrder(),
      throwsA(anything),
    );

    expect(await repository.getPurchaseOrders(), hasLength(1));
  });
}
