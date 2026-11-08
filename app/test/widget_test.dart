import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sokopoa/features/dashboard/repositories/dashboard_repository.dart';
import 'package:sokopoa/features/dashboard/screens/dashboard_screen.dart';
import 'package:sokopoa/features/reports/models/business_report.dart';

void main() {
  testWidgets('SOKOPOA dashboard loads successfully', (
    WidgetTester tester,
  ) async {
    final sampleReport = BusinessReport(
      from: DateTime(2026, 11, 7),
      to: DateTime(2026, 11, 7),
      generatedAt: DateTime(2026, 11, 7),
      sales: const SalesReport(
        subtotalMinor: 150000,
        discountMinor: 0,
        netSalesMinor: 150000,
        transactionCount: 3,
        averageSaleMinor: 50000,
      ),
      collections: const CollectionsReport(
        totalMinor: 120000,
        paymentCount: 3,
        byMethodMinor: {'cash': 120000},
      ),
      debts: const DebtsReport(
        outstandingMinor: 30000,
        customerCount: 1,
      ),
      profit: const ProfitReport(
        salesRevenueMinor: 150000,
        costOfGoodsMinor: 100000,
        grossProfitMinor: 50000,
      ),
      expenses: const ExpensesReport(
        totalMinor: 0,
        expenseCount: 0,
        byCategoryMinor: {},
      ),
      inventory: const InventoryReport(
        productCount: 10,
        totalQuantityBase: 100,
        stockValueMinor: 500000,
        potentialSalesMinor: 700000,
        lowStockCount: 2,
        outOfStockCount: 1,
      ),
      workers: const WorkersReport(
        workerCount: 2,
        unassignedSalesCount: 0,
        salesByWorker: [],
      ),
      suppliers: const SuppliersReport(
        supplierCount: 2,
        invoiceCount: 0,
        invoiceTotalMinor: 0,
        amountPaidMinor: 0,
        outstandingMinor: 0,
        paymentsByMethodMinor: {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          loadDashboardData: () async => DashboardData(
            report: sampleReport,
            recentSales: [],
            pendingCount: 0,
            failedCount: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Business overview'), findsOneWidget);
    expect(find.text('Today sales'), findsOneWidget);
    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('Gross profit'), findsOneWidget);
    expect(find.text('Customer debts'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Synchronization status'), findsOneWidget);
  });
}
