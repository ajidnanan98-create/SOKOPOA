import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalDatabase {
  LocalDatabase._();

  static final instance = LocalDatabase._();

  Database? _db;

  Future<void> initialize() async {
    if (_db != null) return;

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);

    final databasePath = p.join(directory.path, 'sokopoa_local.db');

    _db = await openDatabase(
      databasePath,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        final schema = await _loadSchema();

        for (final statement in schema.split(';')) {
          final sql = statement.trim();
          if (sql.isNotEmpty) {
            await db.execute(sql);
          }
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Preserve the existing version 1 -> 2 migration.
        if (oldVersion < 2) {
          await db.execute('''
            ALTER TABLE stock_movements
            ADD COLUMN entered_quantity REAL NOT NULL DEFAULT 0
          ''');

          await db.execute('''
            ALTER TABLE stock_movements
            ADD COLUMN conversion_factor REAL NOT NULL DEFAULT 1
          ''');

          await db.execute('''
            UPDATE stock_movements
            SET entered_quantity = ABS(quantity_base),
                conversion_factor = 1
          ''');

          await db.execute('''
            INSERT OR IGNORE INTO product_units (
              id,
              product_id,
              unit_name,
              base_units_per_unit
            )
            SELECT
              'base-' || id,
              id,
              base_unit,
              1
            FROM products
          ''');
        }

        // Version 2 -> 3: add an optional local product-image reference.
        // Existing products remain valid and simply have no image.
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE products ADD COLUMN image_path TEXT',
          );
        }

        // Version 3 -> 4: add stocktaking and reconciliation.
        // Existing products and stock movements are left unchanged.
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE stocktakes (
              id TEXT PRIMARY KEY,
              status TEXT NOT NULL DEFAULT 'draft'
                CHECK(status IN ('draft', 'completed', 'cancelled')),
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              reason TEXT,
              started_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              completed_at TEXT,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE stocktake_lines (
              id TEXT PRIMARY KEY,
              stocktake_id TEXT NOT NULL
                REFERENCES stocktakes(id) ON DELETE CASCADE,
              product_id TEXT NOT NULL REFERENCES products(id),
              system_quantity_base REAL NOT NULL,
              counted_quantity_base REAL NOT NULL
                CHECK(counted_quantity_base >= 0),
              variance_quantity_base REAL NOT NULL,
              unit_name TEXT NOT NULL,
              entered_quantity REAL NOT NULL
                CHECK(entered_quantity >= 0),
              conversion_factor REAL NOT NULL
                CHECK(conversion_factor > 0),
              reason TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              UNIQUE(stocktake_id, product_id)
            )
          ''');

          await db.execute('''
            CREATE INDEX idx_stocktakes_status
            ON stocktakes(status, started_at)
          ''');

          await db.execute('''
            CREATE INDEX idx_stocktake_lines_session
            ON stocktake_lines(stocktake_id)
          ''');

          await db.execute('''
            CREATE INDEX idx_stocktake_lines_product
            ON stocktake_lines(product_id)
          ''');
        }
      },
    );
  }

  Future<String> _loadSchema() async {
    return _schema;
  }

  Database get db {
    final value = _db;

    if (value == null) {
      throw StateError(
        'LocalDatabase.initialize() must run first.',
      );
    }

    return value;
  }

  static const _schema = '''
    CREATE TABLE app_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

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
    );

    CREATE TABLE product_units (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL REFERENCES products(id),
      unit_name TEXT NOT NULL,
      base_units_per_unit REAL NOT NULL
        CHECK(base_units_per_unit > 0),
      UNIQUE(product_id, unit_name)
    );

    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      credit_limit_minor INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE suppliers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      address TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE sales (
      id TEXT PRIMARY KEY,
      receipt_number TEXT NOT NULL UNIQUE,
      customer_id TEXT,
      cashier_user_id TEXT NOT NULL,
      subtotal_minor INTEGER NOT NULL,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      total_minor INTEGER NOT NULL,
      paid_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      device_id TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

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
    );

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
    );

    CREATE TABLE stocktakes (
      id TEXT PRIMARY KEY,
      status TEXT NOT NULL DEFAULT 'draft'
        CHECK(status IN ('draft', 'completed', 'cancelled')),
      actor_user_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      reason TEXT,
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE stocktake_lines (
      id TEXT PRIMARY KEY,
      stocktake_id TEXT NOT NULL
        REFERENCES stocktakes(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL REFERENCES products(id),
      system_quantity_base REAL NOT NULL,
      counted_quantity_base REAL NOT NULL
        CHECK(counted_quantity_base >= 0),
      variance_quantity_base REAL NOT NULL,
      unit_name TEXT NOT NULL,
      entered_quantity REAL NOT NULL
        CHECK(entered_quantity >= 0),
      conversion_factor REAL NOT NULL
        CHECK(conversion_factor > 0),
      reason TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(stocktake_id, product_id)
    );

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
    );

    CREATE TABLE expenses (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      payment_method TEXT NOT NULL,
      description TEXT,
      actor_user_id TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE workers (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      phone TEXT,
      role TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      hired_at TEXT,
      created_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE worker_payments (
      id TEXT PRIMARY KEY,
      worker_id TEXT NOT NULL REFERENCES workers(id),
      payment_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      description TEXT,
      paid_at TEXT NOT NULL,
      recorded_by TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

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
    );

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
    );

    CREATE INDEX idx_stock_product_time
      ON stock_movements(product_id, occurred_at);

    CREATE INDEX idx_stocktakes_status
      ON stocktakes(status, started_at);

    CREATE INDEX idx_stocktake_lines_session
      ON stocktake_lines(stocktake_id);

    CREATE INDEX idx_stocktake_lines_product
      ON stocktake_lines(product_id);

    CREATE INDEX idx_sales_time
      ON sales(occurred_at);

    CREATE INDEX idx_outbox_status
      ON sync_outbox(status, created_at);
  ''';
}
