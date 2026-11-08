import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/dashboard/repositories/dashboard_repository.dart';
import 'package:sokopoa/features/pos/models/sale_cart_item.dart';
import 'package:sokopoa/features/pos/models/sale_payment.dart';
import 'package:sokopoa/features/pos/repositories/pos_repository.dart';

void main() {
  late Database database;
  late DashboardRepository repository;

  final testNow = DateTime(2026, 11, 7, 12);

  String dateAt(int day, [int hour = 10]) {
    return DateTime(2026, 11, day, hour).toUtc().toIso8601String();
  }

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
              sync_state TEXT NOT NULL DEFAULT 'pending',
              image_path TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE product_units (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL REFERENCES products(id),
              unit_name TEXT NOT NULL,
              base_units_per_unit REAL NOT NULL,
              UNIQUE(product_id, unit_name)
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
            )
          ''');

          await db.execute('''
            CREATE TABLE sale_lines (
              id TEXT PRIMARY KEY,
              sale_id TEXT NOT NULL REFERENCES sales(id),
              product_id TEXT NOT NULL REFERENCES products(id),
              quantity REAL NOT NULL,
              unit_name TEXT NOT NULL,
              base_quantity REAL NOT NULL,
              unit_price_minor INTEGER NOT NULL,
              cost_minor INTEGER NOT NULL,
              line_total_minor INTEGER NOT NULL
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
            CREATE TABLE payments (
              id TEXT PRIMARY KEY,
              related_type TEXT NOT NULL,
              related_id TEXT NOT NULL,
              method TEXT NOT NULL,
              amount_minor INTEGER NOT NULL,
              reference TEXT,
              received_by TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE expenses (
              id TEXT PRIMARY KEY,
              category TEXT NOT NULL,
              amount_minor INTEGER NOT NULL,
              payment_method TEXT NOT NULL,
              description TEXT,
              actor_user_id TEXT NOT NULL,
              occurred_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

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
            CREATE TABLE supplier_invoices (
              id TEXT PRIMARY KEY,
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              purchase_order_id TEXT,
              invoice_number TEXT NOT NULL,
              invoice_date TEXT NOT NULL,
              due_date TEXT,
              subtotal_minor INTEGER NOT NULL,
              tax_minor INTEGER NOT NULL DEFAULT 0,
              other_charges_minor INTEGER NOT NULL DEFAULT 0,
              total_minor INTEGER NOT NULL,
              status TEXT NOT NULL DEFAULT 'open',
              notes TEXT,
              actor_user_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE supplier_payments (
              id TEXT PRIMARY KEY,
              supplier_invoice_id TEXT NOT NULL
                REFERENCES supplier_invoices(id),
              supplier_id TEXT NOT NULL REFERENCES suppliers(id),
              amount_minor INTEGER NOT NULL,
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
        },
      ),
    );

    repository = DashboardRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertProduct() async {
    await database.insert('products', {
      'id': 'product-1',
      'name': 'Soap',
      'base_unit': 'piece',
      'buying_cost_minor': 6000,
      'selling_price_minor': 9000,
      'minimum_quantity': 5,
      'created_at': dateAt(1),
      'updated_at': dateAt(1),
    });
  }

  Future<void> insertSale({
    required String id,
    required int total,
    required int paid,
    String? customerId,
    String status = 'paid',
  }) async {
    await database.insert('sales', {
      'id': id,
      'receipt_number': 'R-$id',
      'customer_id': customerId,
      'cashier_user_id': 'cashier-1',
      'subtotal_minor': total,
      'discount_minor': 0,
      'total_minor': total,
      'paid_minor': paid,
      'status': status,
      'occurred_at': dateAt(7),
      'device_id': 'device-1',
    });
  }

  test('returns zero dashboard values when there are no transactions',
      () async {
    final data = await repository.getDashboardData(now: testNow);

    expect(data.report.sales.netSalesMinor, 0);
    expect(data.report.collections.totalMinor, 0);
    expect(data.report.profit.grossProfitMinor, 0);
    expect(data.report.debts.outstandingMinor, 0);
    expect(data.recentSales, isEmpty);
    expect(data.pendingCount, 0);
    expect(data.failedCount, 0);
  });

  test('loads real sales, collections, profit and recent customer activity',
      () async {
    await insertProduct();

    await database.insert('customers', {
      'id': 'customer-1',
      'name': 'Mary Customer',
      'created_at': dateAt(1),
      'updated_at': dateAt(1),
    });

    await insertSale(
      id: 'sale-1',
      total: 9000,
      paid: 6000,
      customerId: 'customer-1',
    );

    await insertSale(
      id: 'sale-2',
      total: 5000,
      paid: 5000,
    );

    await database.insert('sale_lines', {
      'id': 'line-1',
      'sale_id': 'sale-1',
      'product_id': 'product-1',
      'quantity': 1,
      'unit_name': 'piece',
      'base_quantity': 1,
      'unit_price_minor': 9000,
      'cost_minor': 6000,
      'line_total_minor': 9000,
    });

    await database.insert('sale_lines', {
      'id': 'line-2',
      'sale_id': 'sale-2',
      'product_id': 'product-1',
      'quantity': 1,
      'unit_name': 'piece',
      'base_quantity': 1,
      'unit_price_minor': 5000,
      'cost_minor': 3000,
      'line_total_minor': 5000,
    });

    await database.insert('payments', {
      'id': 'payment-1',
      'related_type': 'sale',
      'related_id': 'sale-1',
      'method': 'cash',
      'amount_minor': 6000,
      'received_by': 'owner',
      'occurred_at': dateAt(7),
    });

    await database.insert('sync_outbox', {
      'event_id': 'event-pending',
      'aggregate_type': 'sale',
      'aggregate_id': 'sale-1',
      'event_type': 'sale.completed',
      'payload_json': '{}',
      'created_at': dateAt(7),
      'status': 'pending',
    });

    await database.insert('sync_outbox', {
      'event_id': 'event-failed',
      'aggregate_type': 'sale',
      'aggregate_id': 'sale-2',
      'event_type': 'sale.completed',
      'payload_json': '{}',
      'created_at': dateAt(7),
      'status': 'failed',
    });

    final data = await repository.getDashboardData(now: testNow);

    expect(data.report.sales.netSalesMinor, 14000);
    expect(data.report.sales.transactionCount, 2);
    expect(data.report.collections.totalMinor, 6000);
    expect(data.report.profit.grossProfitMinor, 5000);
    expect(data.report.debts.outstandingMinor, 3000);

    expect(data.recentSales, hasLength(2));
    expect(data.recentSales.first['customer_name'], 'Mary Customer');
    expect(data.recentSales.last['customer_name'], 'Walk-in customer');

    expect(data.pendingCount, 1);
    expect(data.failedCount, 1);
  });

  test('excludes voided sales from recent activity', () async {
    await insertSale(
      id: 'sale-valid',
      total: 3000,
      paid: 3000,
    );

    await insertSale(
      id: 'sale-void',
      total: 7000,
      paid: 7000,
      status: 'void',
    );

    final data = await repository.getDashboardData(now: testNow);

    expect(data.recentSales, hasLength(1));
    expect(data.recentSales.single['receipt_number'], 'R-sale-valid');
    expect(data.report.sales.netSalesMinor, 3000);
  });

  test('reflects a completed POS sale in the dashboard', () async {
    final posRepository = PosRepository(database: database);

    await database.insert('products', {
      'id': 'pos-product-1',
      'code': 'SOAP-001',
      'name': 'Test Soap',
      'base_unit': 'piece',
      'buying_cost_minor': 5000,
      'selling_price_minor': 7000,
      'minimum_quantity': 5,
      'active': 1,
      'created_at': dateAt(6),
      'updated_at': dateAt(6),
    });

    await database.insert('customers', {
      'id': 'pos-customer-1',
      'name': 'Test Customer',
      'credit_limit_minor': 100000,
      'created_at': dateAt(6),
      'updated_at': dateAt(6),
    });

    await database.insert('stock_movements', {
      'id': 'pos-opening-stock-1',
      'product_id': 'pos-product-1',
      'movement_type': 'adjustment_in',
      'quantity_base': 100,
      'unit_name': 'piece',
      'entered_quantity': 100,
      'conversion_factor': 1,
      'reference_type': 'opening_stock',
      'actor_user_id': 'test-user',
      'device_id': 'test-device',
      'occurred_at': dateAt(6),
    });

    final sale = await posRepository.completeSale(
      cartItems: [
        SaleCartItem(
          productId: 'pos-product-1',
          productName: 'Test Soap',
          unitName: 'piece',
          quantity: 1,
          conversionFactor: 1,
          unitPriceMinor: 7000,
          costPerBaseUnitMinor: 5000,
        ),
      ],
      payments: const [SalePayment(method: 'cash', amountMinor: 2000)],
      cashierUserId: 'test-user',
      deviceId: 'test-device',
      customerId: 'pos-customer-1',
      occurredAt: DateTime.utc(2026, 11, 6, 14, 30),
    );

    final data = await repository.getDashboardData(
      now: DateTime.utc(2026, 11, 6, 23, 59),
    );

    expect(sale.totalMinor, 7000);
    expect(sale.paidMinor, 2000);
    expect(sale.balanceMinor, 5000);
    expect(data.report.sales.netSalesMinor, 7000);
    expect(data.report.sales.transactionCount, 1);
    expect(data.report.collections.totalMinor, 2000);
    expect(data.report.profit.grossProfitMinor, 2000);
    expect(data.report.debts.outstandingMinor, 5000);
    expect(data.recentSales, hasLength(1));
    expect(data.recentSales.single['receipt_number'], sale.receiptNumber);
    expect(data.recentSales.single['customer_name'], 'Test Customer');
    expect(data.pendingCount, 3);
    expect(data.failedCount, 0);
  });
}
