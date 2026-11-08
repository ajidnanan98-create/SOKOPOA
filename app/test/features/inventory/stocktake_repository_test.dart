import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/inventory/repositories/stocktake_repository.dart';

void main() {
  late Database database;
  late StocktakeRepository repository;

  const productId = 'product-1';
  const actorId = 'admin-1';
  const deviceId = 'desktop-1';

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE product_units (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              unit_name TEXT NOT NULL,
              base_units_per_unit REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_movements (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              movement_type TEXT NOT NULL,
              quantity_base REAL NOT NULL,
              unit_name TEXT NOT NULL,
              entered_quantity REAL NOT NULL,
              conversion_factor REAL NOT NULL,
              reference_type TEXT,
              reference_id TEXT,
              reason TEXT,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              sync_state TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE stocktakes (
              id TEXT PRIMARY KEY,
              status TEXT NOT NULL,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              reason TEXT,
              started_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              completed_at TEXT,
              sync_state TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE stocktake_lines (
              id TEXT PRIMARY KEY,
              stocktake_id TEXT NOT NULL,
              product_id TEXT NOT NULL,
              system_quantity_base REAL NOT NULL,
              counted_quantity_base REAL NOT NULL,
              variance_quantity_base REAL NOT NULL,
              unit_name TEXT NOT NULL,
              entered_quantity REAL NOT NULL,
              conversion_factor REAL NOT NULL,
              reason TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(stocktake_id, product_id)
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
              status TEXT NOT NULL
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
        },
      ),
    );

    repository = StocktakeRepository(database: database);

    await database.insert('products', {
      'id': productId,
      'name': 'Cooking oil',
      'active': 1,
    });
    await database.insert('product_units', {
      'id': 'unit-piece',
      'product_id': productId,
      'unit_name': 'piece',
      'base_units_per_unit': 1,
    });
    await database.insert('product_units', {
      'id': 'unit-box',
      'product_id': productId,
      'unit_name': 'box',
      'base_units_per_unit': 24,
    });
    await _insertMovement(
      database,
      id: 'opening-stock',
      productId: productId,
      quantityBase: 120,
      movementType: 'receipt',
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<Map<String, dynamic>> startSession({String? reason}) {
    return repository.startStocktake(
      actorUserId: actorId,
      deviceId: deviceId,
      reason: reason,
    );
  }

  test('counts packaging units and finalizes only the base-unit variance',
      () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    final line = await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 4,
      unitName: 'box',
      reason: 'Physical count confirmed',
    );

    expect(line['system_quantity_base'], 120);
    expect(line['counted_quantity_base'], 96);
    expect(line['variance_quantity_base'], -24);
    expect(line['conversion_factor'], 24);

    await repository.finalizeStocktake(stocktakeId: sessionId);

    final movements = await database.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['stocktake', sessionId],
    );
    expect(movements, hasLength(1));
    expect(movements.single['movement_type'], 'adjustment_out');
    expect(movements.single['quantity_base'], -24);
    expect(movements.single['entered_quantity'], 1);
    expect(movements.single['conversion_factor'], 24);

    final balance = await database.rawQuery(
      'SELECT SUM(quantity_base) AS balance FROM stock_movements WHERE product_id = ?',
      [productId],
    );
    expect((balance.single['balance'] as num).toDouble(), 96);

    final savedSession = await database.query(
      'stocktakes',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(savedSession.single['status'], 'completed');
    expect(savedSession.single['completed_at'], isNotNull);
  });

  test('requires a reason for a discrepancy and allows correction', () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 4,
      unitName: 'box',
    );

    await expectLater(
      repository.finalizeStocktake(stocktakeId: sessionId),
      throwsA(isA<StateError>()),
    );

    var adjustments = await database.query(
      'stock_movements',
      where: 'reference_type = ?',
      whereArgs: ['stocktake'],
    );
    expect(adjustments, isEmpty);

    final savedSession = await database.query(
      'stocktakes',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(savedSession.single['status'], 'draft');

    await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 4,
      unitName: 'box',
      reason: 'Damaged packaging found during count',
    );
    await repository.finalizeStocktake(stocktakeId: sessionId);

    adjustments = await database.query(
      'stock_movements',
      where: 'reference_type = ?',
      whereArgs: ['stocktake'],
    );
    expect(adjustments, hasLength(1));
  });

  test('completes a matching count without creating an adjustment', () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 5,
      unitName: 'box',
    );

    await repository.finalizeStocktake(stocktakeId: sessionId);

    final adjustments = await database.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['stocktake', sessionId],
    );
    expect(adjustments, isEmpty);

    final savedSession = await database.query(
      'stocktakes',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(savedSession.single['status'], 'completed');
  });

  test('blocks finalization if stock changes after the count snapshot',
      () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 4,
      unitName: 'box',
      reason: 'Counted stock',
    );

    await _insertMovement(
      database,
      id: 'sale-after-count',
      productId: productId,
      quantityBase: -1,
      movementType: 'sale',
    );

    await expectLater(
      repository.finalizeStocktake(stocktakeId: sessionId),
      throwsA(isA<StateError>()),
    );

    final adjustments = await database.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['stocktake', sessionId],
    );
    expect(adjustments, isEmpty);

    final savedSession = await database.query(
      'stocktakes',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(savedSession.single['status'], 'draft');
  });

  test('records stocktake events and audit entries', () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await repository.recordCount(
      stocktakeId: sessionId,
      productId: productId,
      enteredQuantity: 5,
      unitName: 'box',
    );
    await repository.finalizeStocktake(stocktakeId: sessionId);

    final outbox = await database.query('sync_outbox');
    final eventTypes = outbox.map((row) => row['event_type']).toList();
    expect(eventTypes, contains('stocktake.started'));
    expect(eventTypes, contains('stocktake_line.counted'));
    expect(eventTypes, contains('stocktake.completed'));

    final audit = await database.query('audit_log');
    final actions = audit.map((row) => row['action']).toList();
    expect(actions, contains('create'));
    expect(actions, contains('count'));
    expect(actions, contains('complete'));
  });

  test('cancels a draft with a reason and prevents later changes', () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await repository.cancelStocktake(
      stocktakeId: sessionId,
      reason: 'Stocktake entered in error',
    );

    final savedSession = await database.query(
      'stocktakes',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    expect(savedSession.single['status'], 'cancelled');
    expect(savedSession.single['reason'], 'Stocktake entered in error');

    await expectLater(
      repository.recordCount(
        stocktakeId: sessionId,
        productId: productId,
        enteredQuantity: 5,
        unitName: 'box',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.finalizeStocktake(stocktakeId: sessionId),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects negative and unconfigured counts', () async {
    final session = await startSession();
    final sessionId = session['id'] as String;

    await expectLater(
      repository.recordCount(
        stocktakeId: sessionId,
        productId: productId,
        enteredQuantity: -1,
        unitName: 'piece',
      ),
      throwsA(isA<ArgumentError>()),
    );

    await expectLater(
      repository.recordCount(
        stocktakeId: sessionId,
        productId: productId,
        enteredQuantity: 3,
        unitName: 'crate',
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _insertMovement(
  Database database, {
  required String id,
  required String productId,
  required double quantityBase,
  required String movementType,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await database.insert('stock_movements', {
    'id': id,
    'product_id': productId,
    'movement_type': movementType,
    'quantity_base': quantityBase,
    'unit_name': 'piece',
    'entered_quantity': quantityBase.abs(),
    'conversion_factor': 1,
    'reference_type': 'test',
    'reference_id': id,
    'reason': 'Test fixture',
    'actor_user_id': 'admin-1',
    'device_id': 'desktop-1',
    'occurred_at': now,
    'sync_state': 'synced',
  });
}
