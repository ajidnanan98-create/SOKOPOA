import 'package:sqflite/sqflite.dart';

import '../../../data/local_database.dart';
import '../models/business_report.dart';

class BusinessReportRepository {
  BusinessReportRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;

  Database get _db => _testDatabase ?? _localDatabase.db;

  Future<BusinessReport> getBusinessReport({
    DateTime? from,
    DateTime? to,
  }) async {
    final now = DateTime.now();

    final reportFrom = from ??
        DateTime(
          now.year,
          now.month,
          1,
        );

    final reportTo = to ??
        DateTime(
          now.year,
          now.month,
          now.day,
        );

    if (reportTo.isBefore(reportFrom)) {
      throw ArgumentError(
        'The report end date cannot be before the start date.',
      );
    }

    final start = DateTime(
      reportFrom.year,
      reportFrom.month,
      reportFrom.day,
    ).toUtc();

    final endExclusive = DateTime(
      reportTo.year,
      reportTo.month,
      reportTo.day + 1,
    ).toUtc();

    final startText = start.toIso8601String();
    final endText = endExclusive.toIso8601String();

    final results = await Future.wait([
      _getSales(startText, endText),
      _getCollections(startText, endText),
      _getDebts(),
      _getProfit(startText, endText),
      _getExpenses(startText, endText),
      _getInventory(),
      _getWorkers(startText, endText),
      _getSuppliers(startText, endText),
    ]);

    return BusinessReport(
      from: reportFrom,
      to: reportTo,
      generatedAt: DateTime.now(),
      sales: results[0] as SalesReport,
      collections: results[1] as CollectionsReport,
      debts: results[2] as DebtsReport,
      profit: results[3] as ProfitReport,
      expenses: results[4] as ExpensesReport,
      inventory: results[5] as InventoryReport,
      workers: results[6] as WorkersReport,
      suppliers: results[7] as SuppliersReport,
    );
  }

  Future<SalesReport> _getSales(
    String start,
    String end,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(subtotal_minor), 0) AS subtotal,
        COALESCE(SUM(discount_minor), 0) AS discount,
        COALESCE(SUM(total_minor), 0) AS net_sales,
        COUNT(*) AS transaction_count
      FROM sales
      WHERE status != 'void'
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
      [start, end],
    );

    final row = rows.first;
    final netSales = _intValue(row['net_sales']);
    final count = _intValue(row['transaction_count']);

    return SalesReport(
      subtotalMinor: _intValue(row['subtotal']),
      discountMinor: _intValue(row['discount']),
      netSalesMinor: netSales,
      transactionCount: count,
      averageSaleMinor: count == 0 ? 0 : (netSales / count).round(),
    );
  }

  Future<CollectionsReport> _getCollections(
    String start,
    String end,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        method,
        COALESCE(SUM(amount_minor), 0) AS total
      FROM payments
      WHERE related_type = 'sale'
        AND occurred_at >= ?
        AND occurred_at < ?
      GROUP BY method
      ''',
      [start, end],
    );

    final byMethod = <String, int>{};
    var total = 0;
    var paymentCount = 0;

    final countRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS payment_count
      FROM payments
      WHERE related_type = 'sale'
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
      [start, end],
    );

    paymentCount = _intValue(countRows.first['payment_count']);

    for (final row in rows) {
      final method = (row['method'] ?? 'other').toString();
      final amount = _intValue(row['total']);

      byMethod[method] = amount;
      total += amount;
    }

    return CollectionsReport(
      totalMinor: total,
      paymentCount: paymentCount,
      byMethodMinor: byMethod,
    );
  }

  Future<DebtsReport> _getDebts() async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(total_minor - paid_minor), 0) AS outstanding,
        COUNT(DISTINCT customer_id) AS customer_count
      FROM sales
      WHERE status != 'void'
        AND total_minor > paid_minor
        AND customer_id IS NOT NULL
      ''',
    );

    return DebtsReport(
      outstandingMinor: _intValue(rows.first['outstanding']),
      customerCount: _intValue(rows.first['customer_count']),
    );
  }

  Future<ProfitReport> _getProfit(
    String start,
    String end,
  ) async {
    final revenueRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_minor), 0) AS revenue
      FROM sales
      WHERE status != 'void'
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
      [start, end],
    );

    final costRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(sl.cost_minor), 0) AS cost_of_goods
      FROM sale_lines sl
      INNER JOIN sales s ON s.id = sl.sale_id
      WHERE s.status != 'void'
        AND s.occurred_at >= ?
        AND s.occurred_at < ?
      ''',
      [start, end],
    );

    final revenue = _intValue(revenueRows.first['revenue']);
    final cost = _intValue(costRows.first['cost_of_goods']);

    return ProfitReport(
      salesRevenueMinor: revenue,
      costOfGoodsMinor: cost,
      grossProfitMinor: revenue - cost,
    );
  }

  Future<ExpensesReport> _getExpenses(
    String start,
    String end,
  ) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        category,
        COALESCE(SUM(amount_minor), 0) AS total
      FROM expenses
      WHERE occurred_at >= ?
        AND occurred_at < ?
      GROUP BY category
      ''',
      [start, end],
    );

    final byCategory = <String, int>{};
    var total = 0;
    var expenseCount = 0;

    final countRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS expense_count
      FROM expenses
      WHERE occurred_at >= ?
        AND occurred_at < ?
      ''',
      [start, end],
    );

    expenseCount = _intValue(countRows.first['expense_count']);

    for (final row in rows) {
      final category = (row['category'] ?? 'uncategorized').toString();
      final amount = _intValue(row['total']);

      byCategory[category] = amount;
      total += amount;
    }

    return ExpensesReport(
      totalMinor: total,
      expenseCount: expenseCount,
      byCategoryMinor: byCategory,
    );
  }

  Future<InventoryReport> _getInventory() async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        COUNT(*) AS product_count,
        COALESCE(SUM(stock.balance), 0) AS total_quantity,
        COALESCE(
          SUM(stock.balance * p.buying_cost_minor),
          0
        ) AS stock_value,
        COALESCE(
          SUM(stock.balance * p.selling_price_minor),
          0
        ) AS potential_sales,
        COALESCE(
          SUM(
            CASE
              WHEN stock.balance > 0
                AND stock.balance <= p.minimum_quantity
              THEN 1
              ELSE 0
            END
          ),
          0
        ) AS low_stock_count,
        COALESCE(
          SUM(
            CASE
              WHEN COALESCE(stock.balance, 0) <= 0
              THEN 1
              ELSE 0
            END
          ),
          0
        ) AS out_of_stock_count
      FROM products p
      LEFT JOIN (
        SELECT
          product_id,
          COALESCE(SUM(quantity_base), 0) AS balance
        FROM stock_movements
        GROUP BY product_id
      ) stock ON stock.product_id = p.id
      WHERE p.active = 1
      ''',
    );

    final row = rows.first;

    return InventoryReport(
      productCount: _intValue(row['product_count']),
      totalQuantityBase: _doubleValue(row['total_quantity']),
      stockValueMinor: _intValue(row['stock_value']),
      potentialSalesMinor: _intValue(row['potential_sales']),
      lowStockCount: _intValue(row['low_stock_count']),
      outOfStockCount: _intValue(row['out_of_stock_count']),
    );
  }

  Future<WorkersReport> _getWorkers(
    String start,
    String end,
  ) async {
    final countRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS worker_count
      FROM workers
      WHERE active = 1
      ''',
    );

    final unassignedRows = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS unassigned_count
      FROM sales
      WHERE status != 'void'
        AND served_by_worker_id IS NULL
        AND occurred_at >= ?
        AND occurred_at < ?
      ''',
      [start, end],
    );

    final salesRows = await _db.rawQuery(
      '''
      SELECT
        s.served_by_worker_id AS worker_id,
        COALESCE(w.full_name, 'Unknown worker') AS worker_name,
        COUNT(*) AS transaction_count,
        COALESCE(SUM(s.total_minor), 0) AS sales_total
      FROM sales s
      LEFT JOIN workers w
        ON w.id = s.served_by_worker_id
      WHERE s.status != 'void'
        AND s.served_by_worker_id IS NOT NULL
        AND s.occurred_at >= ?
        AND s.occurred_at < ?
      GROUP BY
        s.served_by_worker_id,
        w.full_name
      ORDER BY sales_total DESC
      ''',
      [start, end],
    );

    final summaries = salesRows.map((row) {
      return WorkerSalesSummary(
        workerId: row['worker_id'].toString(),
        workerName: row['worker_name'].toString(),
        transactionCount: _intValue(row['transaction_count']),
        salesMinor: _intValue(row['sales_total']),
      );
    }).toList();

    return WorkersReport(
      workerCount: _intValue(countRows.first['worker_count']),
      unassignedSalesCount: _intValue(unassignedRows.first['unassigned_count']),
      salesByWorker: summaries,
    );
  }

  Future<SuppliersReport> _getSuppliers(
    String start,
    String end,
  ) async {
    final invoiceRows = await _db.rawQuery(
      '''
      SELECT
        COUNT(*) AS invoice_count,
        COUNT(DISTINCT supplier_id) AS supplier_count,
        COALESCE(SUM(total_minor), 0) AS invoice_total
      FROM supplier_invoices
      WHERE status != 'void'
        AND invoice_date >= ?
        AND invoice_date < ?
      ''',
      [start, end],
    );

    final paymentRows = await _db.rawQuery(
      '''
      SELECT
        payment_method,
        COALESCE(SUM(amount_minor), 0) AS total
      FROM supplier_payments
      WHERE occurred_at >= ?
        AND occurred_at < ?
        AND supplier_invoice_id IN (
          SELECT id
          FROM supplier_invoices
          WHERE status != 'void'
        )
      GROUP BY payment_method
      ''',
      [start, end],
    );

    final outstandingRows = await _db.rawQuery(
      '''
      SELECT
        COALESCE(
          SUM(i.total_minor - COALESCE(p.total_paid, 0)),
          0
        ) AS outstanding
      FROM supplier_invoices i
      LEFT JOIN (
        SELECT
          supplier_invoice_id,
          SUM(amount_minor) AS total_paid
        FROM supplier_payments
        GROUP BY supplier_invoice_id
      ) p ON p.supplier_invoice_id = i.id
      WHERE i.status != 'void'
      ''',
    );

    final byMethod = <String, int>{};
    var amountPaid = 0;

    for (final row in paymentRows) {
      final method = (row['payment_method'] ?? 'other').toString();
      final amount = _intValue(row['total']);

      byMethod[method] = amount;
      amountPaid += amount;
    }

    final invoiceRow = invoiceRows.first;

    return SuppliersReport(
      supplierCount: _intValue(invoiceRow['supplier_count']),
      invoiceCount: _intValue(invoiceRow['invoice_count']),
      invoiceTotalMinor: _intValue(invoiceRow['invoice_total']),
      amountPaidMinor: amountPaid,
      outstandingMinor: _intValue(outstandingRows.first['outstanding']),
      paymentsByMethodMinor: byMethod,
    );
  }

  int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
