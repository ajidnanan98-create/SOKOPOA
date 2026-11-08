import 'package:sqflite/sqflite.dart';

import '../../../data/local_database.dart';
import '../../reports/models/business_report.dart';
import '../../reports/repositories/business_report_repository.dart';

class DashboardData {
  const DashboardData({
    required this.report,
    required this.recentSales,
    required this.pendingCount,
    required this.failedCount,
  });

  final BusinessReport report;
  final List<Map<String, Object?>> recentSales;
  final int pendingCount;
  final int failedCount;
}

class DashboardRepository {
  DashboardRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;

  Database get _db => _testDatabase ?? _localDatabase.db;

  Future<DashboardData> getDashboardData({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);

    final report = await BusinessReportRepository(
      database: _db,
    ).getBusinessReport(
      from: today,
      to: today,
    );

    final recentSales = await _db.rawQuery(
      'SELECT s.receipt_number, s.total_minor, s.paid_minor, '
      's.occurred_at, COALESCE(c.name, \'Walk-in customer\') '
      'AS customer_name FROM sales s '
      'LEFT JOIN customers c ON c.id = s.customer_id '
      'WHERE s.status != \'void\' '
      'ORDER BY s.occurred_at DESC LIMIT 8',
    );

    final syncRows = await _db.rawQuery(
      'SELECT status, COUNT(*) AS record_count '
      'FROM sync_outbox GROUP BY status',
    );

    var pending = 0;
    var failed = 0;

    for (final row in syncRows) {
      final count = (row['record_count'] as num?)?.toInt() ?? 0;
      if (row['status'] == 'pending') pending = count;
      if (row['status'] == 'failed') failed = count;
    }

    return DashboardData(
      report: report,
      recentSales: recentSales,
      pendingCount: pending,
      failedCount: failed,
    );
  }
}
