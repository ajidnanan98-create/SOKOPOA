
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/pos/screens/pos_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
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

          await db.insert('products', {
            'id': 'test-product-001',
            'code': 'SOAP001',
            'name': 'Test Washing Soap',
            'category': 'Household',
            'base_unit': 'piece',
            'buying_cost_minor': 5000,
            'selling_price_minor': 7500,
            'minimum_quantity': 5,
            'active': 1,
            'created_at': '2026-11-07T10:00:00.000',
            'updated_at': '2026-11-07T10:00:00.000',
          });

          await db.insert('stock_movements', {
            'id': 'test-stock-001',
            'product_id': 'test-product-001',
            'movement_type': 'opening',
            'quantity_base': 20,
            'unit_name': 'piece',
            'entered_quantity': 20,
            'conversion_factor': 1,
            'actor_user_id': 'test-user',
            'device_id': 'test-device',
            'occurred_at': '2026-11-07T10:00:00.000',
          });
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('POS loads products from injected in-memory database',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosScreen(
            cashierUserId: 'test-user',
            deviceId: 'test-device',
            database: database,
          ),
        ),
      ),
    );

    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();

    expect(find.text('Test Washing Soap'), findsOneWidget);
    expect(find.textContaining('75'), findsWidgets);
    expect(find.textContaining('20'), findsWidgets);
  });
}
