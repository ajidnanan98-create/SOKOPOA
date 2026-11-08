import 'package:intl/intl.dart';

/// Immutable business report data calculated from the local database.
///
/// Monetary values are stored in integer minor units (KES cents).
class BusinessReport {
  const BusinessReport({
    required this.from,
    required this.to,
    required this.generatedAt,
    required this.sales,
    required this.collections,
    required this.debts,
    required this.profit,
    required this.expenses,
    required this.inventory,
    required this.workers,
    required this.suppliers,
  });

  final DateTime from;
  final DateTime to;
  final DateTime generatedAt;

  final SalesReport sales;
  final CollectionsReport collections;
  final DebtsReport debts;
  final ProfitReport profit;
  final ExpensesReport expenses;
  final InventoryReport inventory;
  final WorkersReport workers;
  final SuppliersReport suppliers;

  String get periodLabel {
    final formatter = DateFormat('dd MMM yyyy');
    return '${formatter.format(from)} - ${formatter.format(to)}';
  }
}

class SalesReport {
  const SalesReport({
    required this.subtotalMinor,
    required this.discountMinor,
    required this.netSalesMinor,
    required this.transactionCount,
    required this.averageSaleMinor,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int netSalesMinor;
  final int transactionCount;
  final int averageSaleMinor;
}

class CollectionsReport {
  const CollectionsReport({
    required this.totalMinor,
    required this.paymentCount,
    required this.byMethodMinor,
  });

  final int totalMinor;
  final int paymentCount;

  /// Keys: cash, mpesa, card and bank.
  final Map<String, int> byMethodMinor;
}

class DebtsReport {
  const DebtsReport({
    required this.outstandingMinor,
    required this.customerCount,
  });

  final int outstandingMinor;
  final int customerCount;
}

class ProfitReport {
  const ProfitReport({
    required this.salesRevenueMinor,
    required this.costOfGoodsMinor,
    required this.grossProfitMinor,
  });

  final int salesRevenueMinor;
  final int costOfGoodsMinor;
  final int grossProfitMinor;
}

class ExpensesReport {
  const ExpensesReport({
    required this.totalMinor,
    required this.expenseCount,
    required this.byCategoryMinor,
  });

  final int totalMinor;
  final int expenseCount;
  final Map<String, int> byCategoryMinor;
}

class InventoryReport {
  const InventoryReport({
    required this.productCount,
    required this.totalQuantityBase,
    required this.stockValueMinor,
    required this.potentialSalesMinor,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final int productCount;
  final double totalQuantityBase;
  final int stockValueMinor;
  final int potentialSalesMinor;
  final int lowStockCount;
  final int outOfStockCount;
}

class WorkersReport {
  const WorkersReport({
    required this.workerCount,
    required this.unassignedSalesCount,
    required this.salesByWorker,
  });

  final int workerCount;
  final int unassignedSalesCount;
  final List<WorkerSalesSummary> salesByWorker;
}

class WorkerSalesSummary {
  const WorkerSalesSummary({
    required this.workerId,
    required this.workerName,
    required this.transactionCount,
    required this.salesMinor,
  });

  final String workerId;
  final String workerName;
  final int transactionCount;
  final int salesMinor;
}

class SuppliersReport {
  const SuppliersReport({
    required this.supplierCount,
    required this.invoiceCount,
    required this.invoiceTotalMinor,
    required this.amountPaidMinor,
    required this.outstandingMinor,
    required this.paymentsByMethodMinor,
  });

  final int supplierCount;
  final int invoiceCount;
  final int invoiceTotalMinor;
  final int amountPaidMinor;
  final int outstandingMinor;
  final Map<String, int> paymentsByMethodMinor;
}

/// Formats integer KES minor units as a readable currency amount.
String formatKes(int amountMinor) {
  final amount = amountMinor / 100;
  return 'KES ${NumberFormat('#,##0.00').format(amount)}';
}
