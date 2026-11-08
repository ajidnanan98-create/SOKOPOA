import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/reports/repositories/business_report_repository.dart';

void main() {
  late Database database;
  late BusinessReportRepository repository;

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
        },
      ),
    );

    repository = BusinessReportRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  String dateAt(int day, [int hour = 10]) {
    return DateTime(2026, 11, day, hour).toUtc().toIso8601String();
  }

  Future<void> insertWorker({
    String id = 'worker-1',
    String name = 'John Worker',
    int active = 1,
  }) async {
    await database.insert('workers', {
      'id': id,
      'full_name': name,
      'role': 'Sales',
      'active': active,
      'created_at': dateAt(1),
    });
  }

  Future<void> insertProduct({
    required String id,
    required String name,
    int buyingCost = 1000,
    int sellingPrice = 1500,
    double minimumQuantity = 5,
    int active = 1,
  }) async {
    await database.insert('products', {
      'id': id,
      'name': name,
      'base_unit': 'piece',
      'buying_cost_minor': buyingCost,
      'selling_price_minor': sellingPrice,
      'minimum_quantity': minimumQuantity,
      'active': active,
      'created_at': dateAt(1),
      'updated_at': dateAt(1),
    });
  }

  Future<void> insertSale({
    required String id,
    required int subtotal,
    required int discount,
    required int total,
    required int paid,
    required String date,
    String? customerId,
    String? workerId,
    String status = 'paid',
  }) async {
    await database.insert('sales', {
      'id': id,
      'receipt_number': 'R-$id',
      'customer_id': customerId,
      'cashier_user_id': 'cashier-1',
      'served_by_worker_id': workerId,
      'subtotal_minor': subtotal,
      'discount_minor': discount,
      'total_minor': total,
      'paid_minor': paid,
      'status': status,
      'occurred_at': date,
      'device_id': 'device-1',
    });
  }

  Future<void> insertSupplier({
    String id = 'supplier-1',
    String name = 'Main Supplier',
  }) async {
    await database.insert('suppliers', {
      'id': id,
      'name': name,
      'created_at': dateAt(1),
      'updated_at': dateAt(1),
    });
  }

  Future<void> insertSupplierInvoice({
    required String id,
    required int total,
    required String date,
    String status = 'open',
  }) async {
    await database.insert('supplier_invoices', {
      'id': id,
      'supplier_id': 'supplier-1',
      'invoice_number': 'INV-$id',
      'invoice_date': date,
      'subtotal_minor': total,
      'tax_minor': 0,
      'other_charges_minor': 0,
      'total_minor': total,
      'status': status,
      'actor_user_id': 'owner',
      'device_id': 'device-1',
      'created_at': dateAt(1),
      'updated_at': dateAt(1),
    });
  }

  group('BusinessReportRepository', () {
    test('returns zero values when the database is empty', () async {
      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.sales.netSalesMinor, 0);
      expect(report.sales.transactionCount, 0);
      expect(report.sales.averageSaleMinor, 0);

      expect(report.collections.totalMinor, 0);
      expect(report.collections.paymentCount, 0);

      expect(report.debts.outstandingMinor, 0);
      expect(report.debts.customerCount, 0);

      expect(report.profit.grossProfitMinor, 0);
      expect(report.expenses.totalMinor, 0);

      expect(report.inventory.productCount, 0);
      expect(report.inventory.totalQuantityBase, 0);

      expect(report.workers.workerCount, 0);
      expect(report.workers.unassignedSalesCount, 0);

      expect(report.suppliers.invoiceCount, 0);
      expect(report.suppliers.outstandingMinor, 0);
    });

    test('calculates sales, discounts, average and gross profit', () async {
      await insertProduct(id: 'product-1', name: 'Soap');

      await insertSale(
        id: 'sale-1',
        subtotal: 10000,
        discount: 1000,
        total: 9000,
        paid: 9000,
        date: dateAt(7),
        customerId: 'customer-1',
      );

      await insertSale(
        id: 'sale-2',
        subtotal: 5000,
        discount: 0,
        total: 5000,
        paid: 3000,
        date: dateAt(7),
        customerId: 'customer-2',
      );

      await insertSale(
        id: 'sale-void',
        subtotal: 8000,
        discount: 0,
        total: 8000,
        paid: 8000,
        date: dateAt(7),
        status: 'void',
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

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.sales.subtotalMinor, 15000);
      expect(report.sales.discountMinor, 1000);
      expect(report.sales.netSalesMinor, 14000);
      expect(report.sales.transactionCount, 2);
      expect(report.sales.averageSaleMinor, 7000);

      expect(report.profit.salesRevenueMinor, 14000);
      expect(report.profit.costOfGoodsMinor, 9000);
      expect(report.profit.grossProfitMinor, 5000);
    });

    test('filters sales and collections by date and payment type', () async {
      await insertSale(
        id: 'sale-in-range',
        subtotal: 5000,
        discount: 0,
        total: 5000,
        paid: 3000,
        date: dateAt(7),
      );

      await insertSale(
        id: 'sale-outside',
        subtotal: 7000,
        discount: 0,
        total: 7000,
        paid: 7000,
        date: dateAt(8),
      );

      await database.insert('payments', {
        'id': 'payment-1',
        'related_type': 'sale',
        'related_id': 'sale-in-range',
        'method': 'cash',
        'amount_minor': 2000,
        'received_by': 'owner',
        'occurred_at': dateAt(7),
      });

      await database.insert('payments', {
        'id': 'payment-2',
        'related_type': 'sale',
        'related_id': 'sale-in-range',
        'method': 'mpesa',
        'amount_minor': 1000,
        'received_by': 'owner',
        'occurred_at': dateAt(7),
      });

      await database.insert('payments', {
        'id': 'payment-3',
        'related_type': 'purchase',
        'related_id': 'purchase-1',
        'method': 'cash',
        'amount_minor': 9000,
        'received_by': 'owner',
        'occurred_at': dateAt(7),
      });

      await database.insert('payments', {
        'id': 'payment-4',
        'related_type': 'sale',
        'related_id': 'sale-outside',
        'method': 'cash',
        'amount_minor': 7000,
        'received_by': 'owner',
        'occurred_at': dateAt(8),
      });

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.sales.netSalesMinor, 5000);
      expect(report.sales.transactionCount, 1);

      expect(report.collections.totalMinor, 3000);
      expect(report.collections.paymentCount, 2);
      expect(report.collections.byMethodMinor['cash'], 2000);
      expect(report.collections.byMethodMinor['mpesa'], 1000);
    });

    test('calculates current customer debt excluding void sales', () async {
      await insertSale(
        id: 'debt-1',
        subtotal: 10000,
        discount: 0,
        total: 10000,
        paid: 4000,
        date: dateAt(5),
        customerId: 'customer-1',
      );

      await insertSale(
        id: 'debt-2',
        subtotal: 8000,
        discount: 0,
        total: 8000,
        paid: 3000,
        date: dateAt(6),
        customerId: 'customer-1',
      );

      await insertSale(
        id: 'debt-3',
        subtotal: 9000,
        discount: 0,
        total: 9000,
        paid: 0,
        date: dateAt(6),
        customerId: 'customer-2',
        status: 'void',
      );

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.debts.outstandingMinor, 11000);
      expect(report.debts.customerCount, 1);
    });

    test('calculates expenses by category and count', () async {
      await database.insert('expenses', {
        'id': 'expense-1',
        'category': 'Transport',
        'amount_minor': 1500,
        'payment_method': 'cash',
        'actor_user_id': 'owner',
        'occurred_at': dateAt(7),
      });

      await database.insert('expenses', {
        'id': 'expense-2',
        'category': 'Transport',
        'amount_minor': 2500,
        'payment_method': 'mpesa',
        'actor_user_id': 'owner',
        'occurred_at': dateAt(7),
      });

      await database.insert('expenses', {
        'id': 'expense-3',
        'category': 'Electricity',
        'amount_minor': 3000,
        'payment_method': 'cash',
        'actor_user_id': 'owner',
        'occurred_at': dateAt(7),
      });

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.expenses.totalMinor, 7000);
      expect(report.expenses.expenseCount, 3);
      expect(report.expenses.byCategoryMinor['Transport'], 4000);
      expect(report.expenses.byCategoryMinor['Electricity'], 3000);
    });

    test('calculates inventory balance, valuation and stock alerts', () async {
      await insertProduct(
        id: 'product-1',
        name: 'Soap',
        buyingCost: 1000,
        sellingPrice: 1500,
        minimumQuantity: 5,
      );

      await insertProduct(
        id: 'product-2',
        name: 'Flour',
        buyingCost: 2000,
        sellingPrice: 2500,
        minimumQuantity: 10,
      );

      await insertProduct(
        id: 'product-3',
        name: 'Sugar',
        buyingCost: 3000,
        sellingPrice: 3500,
        minimumQuantity: 5,
      );

      await insertProduct(
        id: 'product-inactive',
        name: 'Inactive Product',
        active: 0,
      );

      await database.insert('stock_movements', {
        'id': 'stock-1',
        'product_id': 'product-1',
        'movement_type': 'receipt',
        'quantity_base': 3,
        'unit_name': 'piece',
        'actor_user_id': 'owner',
        'device_id': 'device-1',
        'occurred_at': dateAt(7),
      });

      await database.insert('stock_movements', {
        'id': 'stock-2',
        'product_id': 'product-2',
        'movement_type': 'receipt',
        'quantity_base': 20,
        'unit_name': 'piece',
        'actor_user_id': 'owner',
        'device_id': 'device-1',
        'occurred_at': dateAt(7),
      });

      await database.insert('stock_movements', {
        'id': 'stock-3',
        'product_id': 'product-2',
        'movement_type': 'sale',
        'quantity_base': -5,
        'unit_name': 'piece',
        'actor_user_id': 'owner',
        'device_id': 'device-1',
        'occurred_at': dateAt(7),
      });

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.inventory.productCount, 3);
      expect(report.inventory.totalQuantityBase, 18);
      expect(report.inventory.stockValueMinor, 33000);
      expect(report.inventory.potentialSalesMinor, 42000);
      expect(report.inventory.lowStockCount, 1);
      expect(report.inventory.outOfStockCount, 1);
    });

    test('groups sales by worker and counts unassigned sales', () async {
      await insertWorker();
      await insertWorker(
        id: 'worker-2',
        name: 'Jane Worker',
        active: 0,
      );

      await insertSale(
        id: 'worker-sale-1',
        subtotal: 10000,
        discount: 0,
        total: 10000,
        paid: 10000,
        date: dateAt(7),
        workerId: 'worker-1',
      );

      await insertSale(
        id: 'worker-sale-2',
        subtotal: 5000,
        discount: 0,
        total: 5000,
        paid: 5000,
        date: dateAt(7),
        workerId: 'worker-2',
      );

      await insertSale(
        id: 'unassigned-sale',
        subtotal: 3000,
        discount: 0,
        total: 3000,
        paid: 3000,
        date: dateAt(7),
      );

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.workers.workerCount, 1);
      expect(report.workers.unassignedSalesCount, 1);
      expect(report.workers.salesByWorker.length, 2);

      expect(report.workers.salesByWorker[0].workerId, 'worker-1');
      expect(report.workers.salesByWorker[0].workerName, 'John Worker');
      expect(report.workers.salesByWorker[0].salesMinor, 10000);

      expect(report.workers.salesByWorker[1].workerId, 'worker-2');
      expect(report.workers.salesByWorker[1].workerName, 'Jane Worker');
      expect(report.workers.salesByWorker[1].salesMinor, 5000);
    });

    test('calculates supplier invoices, payments and current outstanding',
        () async {
      await insertSupplier();

      await insertSupplierInvoice(
        id: 'invoice-1',
        total: 10000,
        date: dateAt(7),
      );

      await insertSupplierInvoice(
        id: 'invoice-2',
        total: 5000,
        date: dateAt(7),
      );

      await insertSupplierInvoice(
        id: 'invoice-void',
        total: 9000,
        date: dateAt(7),
        status: 'void',
      );

      await database.insert('supplier_payments', {
        'id': 'supplier-payment-1',
        'supplier_invoice_id': 'invoice-1',
        'supplier_id': 'supplier-1',
        'amount_minor': 4000,
        'payment_method': 'mpesa',
        'paid_by': 'owner',
        'device_id': 'device-1',
        'occurred_at': dateAt(7),
        'created_at': dateAt(7),
      });

      await database.insert('supplier_payments', {
        'id': 'supplier-payment-2',
        'supplier_invoice_id': 'invoice-2',
        'supplier_id': 'supplier-1',
        'amount_minor': 2000,
        'payment_method': 'cash',
        'paid_by': 'owner',
        'device_id': 'device-1',
        'occurred_at': dateAt(7),
        'created_at': dateAt(7),
      });

      final report = await repository.getBusinessReport(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 7),
      );

      expect(report.suppliers.supplierCount, 1);
      expect(report.suppliers.invoiceCount, 2);
      expect(report.suppliers.invoiceTotalMinor, 15000);
      expect(report.suppliers.amountPaidMinor, 6000);
      expect(report.suppliers.outstandingMinor, 9000);

      expect(report.suppliers.paymentsByMethodMinor['mpesa'], 4000);
      expect(report.suppliers.paymentsByMethodMinor['cash'], 2000);
    });

    test('rejects a report end date before its start date', () async {
      expect(
        () => repository.getBusinessReport(
          from: DateTime(2026, 11, 7),
          to: DateTime(2026, 11, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
