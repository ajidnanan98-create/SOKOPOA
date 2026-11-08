import 'package:sqflite/sqflite.dart';

import '../../../data/local_database.dart';

class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.name,
    this.phone,
    required this.creditLimitMinor,
  });

  final String id;
  final String name;
  final String? phone;
  final int creditLimitMinor;

  factory PosCustomer.fromMap(Map<String, Object?> map) {
    return PosCustomer(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      creditLimitMinor: (map['credit_limit_minor'] as num).toInt(),
    );
  }
}

class PosWorker {
  const PosWorker({
    required this.id,
    required this.fullName,
    required this.role,
    this.phone,
  });

  final String id;
  final String fullName;
  final String role;
  final String? phone;

  factory PosWorker.fromMap(Map<String, Object?> map) {
    return PosWorker(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      role: map['role'] as String,
      phone: map['phone'] as String?,
    );
  }
}

class PosReadRepository {
  PosReadRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;

  Database get _db => _testDatabase ?? _localDatabase.db;

  Future<List<PosCustomer>> getCustomers({
    String search = '',
  }) async {
    final term = search.trim();

    final rows = await _db.query(
      'customers',
      where: term.isEmpty ? null : '(name LIKE ? OR phone LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(PosCustomer.fromMap).toList();
  }

  Future<List<PosWorker>> getActiveWorkers({
    String search = '',
  }) async {
    final term = search.trim();

    final rows = await _db.query(
      'workers',
      where: term.isEmpty
          ? 'active = 1'
          : 'active = 1 AND (full_name LIKE ? OR phone LIKE ? OR role LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%', '%$term%'],
      orderBy: 'full_name COLLATE NOCASE ASC',
    );

    return rows.map(PosWorker.fromMap).toList();
  }
}
