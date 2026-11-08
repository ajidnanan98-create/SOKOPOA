import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sokopoa/core/backup_service.dart';
import 'package:sokopoa/core/sync_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            code TEXT,
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
            sync_state TEXT NOT NULL DEFAULT 'pending'
          );
        ''');
        await db.execute('''
          CREATE TABLE product_units (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            unit_name TEXT NOT NULL,
            base_units_per_unit REAL NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT);
        ''');
        await db.execute('''
          CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT);
        ''');
        await db.execute('''
          CREATE TABLE sales (id TEXT PRIMARY KEY, receipt_number TEXT);
        ''');
        await db.execute('''
          CREATE TABLE sale_lines (id TEXT PRIMARY KEY, sale_id TEXT);
        ''');
        await db.execute('''
          CREATE TABLE stock_movements (id TEXT PRIMARY KEY, product_id TEXT);
        ''');
        await db.execute('''
          CREATE TABLE expenses (id TEXT PRIMARY KEY, amount_minor INTEGER);
        ''');
        await db.execute('''
          CREATE TABLE workers (id TEXT PRIMARY KEY, full_name TEXT);
        ''');
        await db.execute('''
          CREATE TABLE worker_payments (id TEXT PRIMARY KEY, amount_minor INTEGER);
        ''');
        await db.execute('''
          CREATE TABLE audit_log (id TEXT PRIMARY KEY, action TEXT);
        ''');
      },
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('BackupService creates a valid JSON snapshot containing table rows', () async {
    await db.insert('products', {
      'id': 'p-101',
      'code': 'CODE-101',
      'name': 'Test Sugar 50kg',
      'base_unit': 'kg',
      'buying_cost_minor': 5000,
      'selling_price_minor': 6500,
      'minimum_quantity': 10,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'sync_state': 'pending',
    });

    final backupService = BackupService(database: db);
    final jsonStr = await backupService.createBackupJson();

    expect(jsonStr, contains('p-101'));
    expect(jsonStr, contains('Test Sugar 50kg'));

    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(map['version'], equals('1.0.0'));
    expect(map['tables'], isNotNull);
  });

  test('BackupService restores records from JSON payload', () async {
    final backupService = BackupService(database: db);

    final payload = jsonEncode({
      'version': '1.0.0',
      'exported_at': DateTime.now().toIso8601String(),
      'tables': {
        'products': [
          {
            'id': 'p-202',
            'code': 'CODE-202',
            'name': 'Maize Flour 10kg',
            'base_unit': 'bag',
            'buying_cost_minor': 1200,
            'selling_price_minor': 1500,
            'minimum_quantity': 5,
            'active': 1,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'sync_state': 'synced',
          }
        ]
      }
    });

    final restoredCount = await backupService.restoreFromBackupJson(payload);
    expect(restoredCount, equals(1));

    final rows = await db.query('products', where: "id = 'p-202'");
    expect(rows.length, equals(1));
    expect(rows.first['name'], equals('Maize Flour 10kg'));
  });
}
