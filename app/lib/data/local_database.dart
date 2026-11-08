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
      version: 6,
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
        // Version 4 -> 5: Purchasing, goods receiving and supplier accounts.
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS purchase_orders (
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
            CREATE TABLE IF NOT EXISTS purchase_order_lines (
              id TEXT PRIMARY KEY,
              purchase_order_id TEXT NOT NULL
                REFERENCES purchase_orders(id) ON DELETE CASCADE,
              product_id TEXT NOT NULL REFERENCES products(id),
              product_name TEXT NOT NULL,
              product_code TEXT,
              entered_quantity REAL NOT NULL
                CHECK(entered_quantity > 0),
              unit_name TEXT NOT NULL,
              conversion_factor REAL NOT NULL
                CHECK(conversion_factor > 0),
              base_quantity REAL NOT NULL
                CHECK(base_quantity > 0),
              unit_cost_minor INTEGER NOT NULL
                CHECK(unit_cost_minor >= 0),
              line_total_minor INTEGER NOT NULL
                CHECK(line_total_minor >= 0),
              created_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS goods_receipts (
              id TEXT PRIMARY KEY,
              receipt_number TEXT NOT NULL UNIQUE,
              purchase_order_id TEXT NOT NULL
                REFERENCES purchase_orders(id),
              status TEXT NOT NULL DEFAULT 'draft'
                CHECK(status IN ('draft', 'posted', 'cancelled')),
              received_at TEXT NOT NULL,
              notes TEXT,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              posted_at TEXT,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS goods_receipt_lines (
              id TEXT PRIMARY KEY,
              goods_receipt_id TEXT NOT NULL
                REFERENCES goods_receipts(id) ON DELETE CASCADE,
              purchase_order_line_id TEXT NOT NULL
                REFERENCES purchase_order_lines(id),
              product_id TEXT NOT NULL REFERENCES products(id),
              product_name TEXT NOT NULL,
              entered_quantity REAL NOT NULL
                CHECK(entered_quantity > 0),
              unit_name TEXT NOT NULL,
              conversion_factor REAL NOT NULL
                CHECK(conversion_factor > 0),
              received_quantity_base REAL NOT NULL
                CHECK(received_quantity_base > 0),
              accepted_quantity_base REAL NOT NULL
                CHECK(accepted_quantity_base >= 0),
              damaged_quantity_base REAL NOT NULL
                CHECK(damaged_quantity_base >= 0),
              rejected_quantity_base REAL NOT NULL
                CHECK(rejected_quantity_base >= 0),
              cost_per_base_unit_minor REAL NOT NULL
                CHECK(cost_per_base_unit_minor >= 0),
              created_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS supplier_invoices (
              id TEXT PRIMARY KEY,
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              purchase_order_id TEXT
                REFERENCES purchase_orders(id),
              invoice_number TEXT NOT NULL,
              invoice_date TEXT NOT NULL,
              due_date TEXT,
              subtotal_minor INTEGER NOT NULL
                CHECK(subtotal_minor >= 0),
              tax_minor INTEGER NOT NULL DEFAULT 0
                CHECK(tax_minor >= 0),
              other_charges_minor INTEGER NOT NULL DEFAULT 0
                CHECK(other_charges_minor >= 0),
              total_minor INTEGER NOT NULL
                CHECK(total_minor > 0),
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
            CREATE TABLE IF NOT EXISTS supplier_payments (
              id TEXT PRIMARY KEY,
              supplier_invoice_id TEXT NOT NULL
                REFERENCES supplier_invoices(id),
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              amount_minor INTEGER NOT NULL
                CHECK(amount_minor > 0),
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
            CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_date
            ON purchase_orders(supplier_id, created_at)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_purchase_orders_status_date
            ON purchase_orders(status, created_at)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_order
            ON purchase_order_lines(purchase_order_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_product
            ON purchase_order_lines(product_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_goods_receipts_order_date
            ON goods_receipts(purchase_order_id, received_at)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_goods_receipts_status
            ON goods_receipts(status, received_at)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_receipt
            ON goods_receipt_lines(goods_receipt_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_product
            ON goods_receipt_lines(product_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_supplier_invoices_supplier_date
            ON supplier_invoices(supplier_id, invoice_date)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_supplier_invoices_order
            ON supplier_invoices(purchase_order_id)
          ''');

          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_supplier_payments_invoice_date
            ON supplier_payments(supplier_invoice_id, occurred_at)
          ''');

                    await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier_date
            ON supplier_payments(supplier_id, occurred_at)
          ''');
        }

        // Version 5 -> 6: identify the worker who served each sale.
        // Nullable so existing sales remain valid.
        if (oldVersion < 6) {
          await db.execute('''
            ALTER TABLE sales
            ADD COLUMN served_by_worker_id TEXT
            REFERENCES workers(id)
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
      served_by_worker_id TEXT REFERENCES workers(id),
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
    );

    CREATE TABLE purchase_order_lines (
      id TEXT PRIMARY KEY,
      purchase_order_id TEXT NOT NULL
        REFERENCES purchase_orders(id) ON DELETE CASCADE,
      product_id TEXT NOT NULL REFERENCES products(id),
      product_name TEXT NOT NULL,
      product_code TEXT,
      entered_quantity REAL NOT NULL
        CHECK(entered_quantity > 0),
      unit_name TEXT NOT NULL,
      conversion_factor REAL NOT NULL
        CHECK(conversion_factor > 0),
      base_quantity REAL NOT NULL
        CHECK(base_quantity > 0),
      unit_cost_minor INTEGER NOT NULL
        CHECK(unit_cost_minor >= 0),
      line_total_minor INTEGER NOT NULL
        CHECK(line_total_minor >= 0),
      created_at TEXT NOT NULL
    );

    CREATE TABLE goods_receipts (
      id TEXT PRIMARY KEY,
      receipt_number TEXT NOT NULL UNIQUE,
      purchase_order_id TEXT NOT NULL
        REFERENCES purchase_orders(id),
      status TEXT NOT NULL DEFAULT 'draft'
        CHECK(status IN ('draft', 'posted', 'cancelled')),
      received_at TEXT NOT NULL,
      notes TEXT,
      actor_user_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      posted_at TEXT,
      sync_state TEXT NOT NULL DEFAULT 'pending'
    );

    CREATE TABLE goods_receipt_lines (
      id TEXT PRIMARY KEY,
      goods_receipt_id TEXT NOT NULL
        REFERENCES goods_receipts(id) ON DELETE CASCADE,
      purchase_order_line_id TEXT NOT NULL
        REFERENCES purchase_order_lines(id),
      product_id TEXT NOT NULL REFERENCES products(id),
      product_name TEXT NOT NULL,
      entered_quantity REAL NOT NULL
        CHECK(entered_quantity > 0),
      unit_name TEXT NOT NULL,
      conversion_factor REAL NOT NULL
        CHECK(conversion_factor > 0),
      received_quantity_base REAL NOT NULL
        CHECK(received_quantity_base > 0),
      accepted_quantity_base REAL NOT NULL
        CHECK(accepted_quantity_base >= 0),
      damaged_quantity_base REAL NOT NULL
        CHECK(damaged_quantity_base >= 0),
      rejected_quantity_base REAL NOT NULL
        CHECK(rejected_quantity_base >= 0),
      cost_per_base_unit_minor REAL NOT NULL
        CHECK(cost_per_base_unit_minor >= 0),
      created_at TEXT NOT NULL
    );

    CREATE TABLE supplier_invoices (
      id TEXT PRIMARY KEY,
      supplier_id TEXT NOT NULL REFERENCES suppliers(id),
      purchase_order_id TEXT
        REFERENCES purchase_orders(id),
      invoice_number TEXT NOT NULL,
      invoice_date TEXT NOT NULL,
      due_date TEXT,
      subtotal_minor INTEGER NOT NULL
        CHECK(subtotal_minor >= 0),
      tax_minor INTEGER NOT NULL DEFAULT 0
        CHECK(tax_minor >= 0),
      other_charges_minor INTEGER NOT NULL DEFAULT 0
        CHECK(other_charges_minor >= 0),
      total_minor INTEGER NOT NULL
        CHECK(total_minor > 0),
      status TEXT NOT NULL DEFAULT 'open'
        CHECK(status IN ('open', 'part_paid', 'paid', 'void')),
      notes TEXT,
      actor_user_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending',
      UNIQUE(supplier_id, invoice_number)
    );

    CREATE TABLE supplier_payments (
      id TEXT PRIMARY KEY,
      supplier_invoice_id TEXT NOT NULL
        REFERENCES supplier_invoices(id),
      supplier_id TEXT NOT NULL REFERENCES suppliers(id),
      amount_minor INTEGER NOT NULL
        CHECK(amount_minor > 0),
      payment_method TEXT NOT NULL,
      reference TEXT,
      paid_by TEXT NOT NULL,
      device_id TEXT NOT NULL,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'pending'
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
        CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_date
      ON purchase_orders(supplier_id, created_at);

    CREATE INDEX IF NOT EXISTS idx_purchase_orders_status_date
      ON purchase_orders(status, created_at);

    CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_order
      ON purchase_order_lines(purchase_order_id);

    CREATE INDEX IF NOT EXISTS idx_purchase_order_lines_product
      ON purchase_order_lines(product_id);

    CREATE INDEX IF NOT EXISTS idx_goods_receipts_order_date
      ON goods_receipts(purchase_order_id, received_at);

    CREATE INDEX IF NOT EXISTS idx_goods_receipts_status
      ON goods_receipts(status, received_at);

    CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_receipt
      ON goods_receipt_lines(goods_receipt_id);

    CREATE INDEX IF NOT EXISTS idx_goods_receipt_lines_product
      ON goods_receipt_lines(product_id);

    CREATE INDEX IF NOT EXISTS idx_supplier_invoices_supplier_date
      ON supplier_invoices(supplier_id, invoice_date);

    CREATE INDEX IF NOT EXISTS idx_supplier_invoices_order
      ON supplier_invoices(purchase_order_id);

    CREATE INDEX IF NOT EXISTS idx_supplier_payments_invoice_date
      ON supplier_payments(supplier_invoice_id, occurred_at);

    CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier_date
      ON supplier_payments(supplier_id, occurred_at); 

    CREATE INDEX idx_sales_time
      ON sales(occurred_at);

    CREATE INDEX idx_outbox_status
      ON sync_outbox(status, created_at);
  ''';
}
