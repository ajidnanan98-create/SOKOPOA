import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../data/local_database.dart';

class BackupService {
  BackupService({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;

  Database get _db => _testDatabase ?? _localDatabase.db;

  /// Creates a full JSON snapshot export of all critical business data tables.
  Future<String> createBackupJson() async {
    final tables = [
      'products',
      'product_units',
      'customers',
      'suppliers',
      'sales',
      'sale_lines',
      'stock_movements',
      'expenses',
      'workers',
      'worker_payments',
      'audit_log',
    ];

    final backupData = <String, dynamic>{
      'version': '1.0.0',
      'exported_at': DateTime.now().toIso8601String(),
      'tables': <String, dynamic>{},
    };

    for (final table in tables) {
      final rows = await _db.query(table);
      (backupData['tables'] as Map<String, dynamic>)[table] = rows;
    }

    return const JsonEncoder.withIndent('  ').convert(backupData);
  }

  /// Restores records from a JSON snapshot payload.
  Future<int> restoreFromBackupJson(String jsonPayload) async {
    final data = jsonDecode(jsonPayload) as Map<String, dynamic>;

    if (!data.containsKey('tables')) {
      throw FormatException('Invalid backup payload: missing tables section');
    }

    final tablesMap = data['tables'] as Map<String, dynamic>;
    var restoredCount = 0;

    await _db.transaction((txn) async {
      for (final entry in tablesMap.entries) {
        final tableName = entry.key;
        final rows = (entry.value as List).cast<Map<String, dynamic>>();

        for (final row in rows) {
          final copy = Map<String, dynamic>.from(row);
          await txn.insert(
            tableName,
            copy,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredCount++;
        }
      }
    });

    return restoredCount;
  }
}
