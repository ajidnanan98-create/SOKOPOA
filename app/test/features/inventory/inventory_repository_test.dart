import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sokopoa/features/inventory/repositories/inventory_repository.dart';

void main() {
  late Database database;
  late InventoryRepository repository;

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
        version: 3,
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

    repository = InventoryRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('registers a product and records opening stock', () async {
    final product = await repository.createProduct(
      name: 'Test Soap',
      code: 'TEST-SOAP-001',
      baseUnit: 'piece',
      buyingCostMinor: 5000,
      sellingPriceMinor: 7000,
      minimumQuantity: 10,
      openingQuantity: 100,
      actorUserId: actor,
      deviceId: device,
    );

    expect(product.name, 'Test Soap');
    expect(await repository.getStockBalance(product.id), 100);

    final products = await repository.getProducts();
    expect(products.length, 1);

    final units = await repository.getProductUnits(product.id);
    expect(units.length, 1);
    expect(units.single.unitName, 'piece');
    expect(units.single.baseUnitsPerUnit, 1);
  });

  test('rejects duplicate product codes', () async {
    Future<void> createTestProduct() async {
      await repository.createProduct(
        name: 'Duplicate Test',
        code: 'DUPLICATE-001',
        baseUnit: 'piece',
        buyingCostMinor: 1000,
        sellingPriceMinor: 1500,
        minimumQuantity: 5,
        actorUserId: actor,
        deviceId: device,
      );
    }

    await createTestProduct();

    await expectLater(
      createTestProduct(),
      throwsA(isA<StateError>()),
    );

    expect((await repository.getProducts()).length, 1);
  });

  test('calculates stock correctly from base-unit movements', () async {
    final product = await repository.createProduct(
      name: 'Movement Test',
      baseUnit: 'piece',
      buyingCostMinor: 1000,
      sellingPriceMinor: 1500,
      minimumQuantity: 5,
      openingQuantity: 100,
      actorUserId: actor,
      deviceId: device,
    );

    await repository.recordStockMovement(
      productId: product.id,
      movementType: 'receipt',
      quantity: 50,
      unitName: 'piece',
      actorUserId: actor,
      deviceId: device,
    );

    await repository.recordStockMovement(
      productId: product.id,
      movementType: 'sale',
      quantity: 10,
      unitName: 'piece',
      actorUserId: actor,
      deviceId: device,
    );

    await repository.recordStockMovement(
      productId: product.id,
      movementType: 'damage',
      quantity: 2,
      unitName: 'piece',
      reason: 'Damaged packaging',
      actorUserId: actor,
      deviceId: device,
    );

    expect(await repository.getStockBalance(product.id), 138);
  });

  test('converts boxes to pieces when receiving and selling stock', () async {
    final product = await repository.createProduct(
      name: 'Boxed Soap',
      baseUnit: 'piece',
      buyingCostMinor: 1000,
      sellingPriceMinor: 1500,
      minimumQuantity: 0,
      actorUserId: actor,
      deviceId: device,
    );

    final boxUnit = await repository.addProductUnit(
      productId: product.id,
      unitName: 'box',
      baseUnitsPerUnit: 24,
      actorUserId: actor,
      deviceId: device,
    );

    expect(boxUnit.baseUnitsPerUnit, 24);

    final receipt = await repository.recordStockMovement(
      productId: product.id,
      movementType: 'receipt',
      quantity: 5,
      unitName: 'box',
      actorUserId: actor,
      deviceId: device,
    );

    expect(receipt.enteredQuantity, 5);
    expect(receipt.conversionFactor, 24);
    expect(receipt.quantityBase, 120);
    expect(await repository.getStockBalance(product.id), 120);

    final sale = await repository.recordStockMovement(
      productId: product.id,
      movementType: 'sale',
      quantity: 2,
      unitName: 'box',
      actorUserId: actor,
      deviceId: device,
    );

    expect(sale.enteredQuantity, 2);
    expect(sale.conversionFactor, 24);
    expect(sale.quantityBase, -48);
    expect(await repository.getStockBalance(product.id), 72);

    final storedMovements = await database.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [product.id],
      orderBy: 'occurred_at ASC',
    );

    expect(storedMovements.length, 2);
    expect(storedMovements[0]['entered_quantity'], 5);
    expect(storedMovements[0]['conversion_factor'], 24);
    expect(storedMovements[0]['quantity_base'], 120);
    expect(storedMovements[1]['entered_quantity'], 2);
    expect(storedMovements[1]['conversion_factor'], 24);
    expect(storedMovements[1]['quantity_base'], -48);
  });

  test('rejects a unit that is not configured for the product', () async {
    final product = await repository.createProduct(
      name: 'Unconfigured Unit Test',
      baseUnit: 'piece',
      buyingCostMinor: 1000,
      sellingPriceMinor: 1500,
      minimumQuantity: 0,
      openingQuantity: 10,
      actorUserId: actor,
      deviceId: device,
    );

    await expectLater(
      repository.recordStockMovement(
        productId: product.id,
        movementType: 'receipt',
        quantity: 1,
        unitName: 'carton',
        actorUserId: actor,
        deviceId: device,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getStockBalance(product.id), 10);
  });

  test('prevents stock from becoming negative after unit conversion', () async {
    final product = await repository.createProduct(
      name: 'Limited Stock Test',
      baseUnit: 'piece',
      buyingCostMinor: 1000,
      sellingPriceMinor: 1500,
      minimumQuantity: 0,
      openingQuantity: 5,
      actorUserId: actor,
      deviceId: device,
    );

    await repository.addProductUnit(
      productId: product.id,
      unitName: 'box',
      baseUnitsPerUnit: 24,
      actorUserId: actor,
      deviceId: device,
    );

    await expectLater(
      repository.recordStockMovement(
        productId: product.id,
        movementType: 'sale',
        quantity: 1,
        unitName: 'box',
        actorUserId: actor,
        deviceId: device,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await repository.getStockBalance(product.id), 5);
  });
}
