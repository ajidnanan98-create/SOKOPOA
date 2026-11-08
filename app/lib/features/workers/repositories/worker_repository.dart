import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/worker.dart';

class WorkerRepository {
  WorkerRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  // CREATE WORKER
  Future<Worker> createWorker({
    required String fullName,
    required String role,
    String? phone,
    DateTime? hiredAt,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = fullName.trim();
    final cleanRole = role.trim();
    final cleanPhone = _cleanOptional(phone);

    if (cleanName.isEmpty) {
      throw ArgumentError('Worker full name is required.');
    }

    if (cleanRole.isEmpty) {
      throw ArgumentError('Worker role is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    final worker = Worker(
      id: _uuid.v4(),
      fullName: cleanName,
      role: cleanRole,
      phone: cleanPhone,
      active: true,
      hiredAt: hiredAt?.toUtc(),
      createdAt: now,
      syncState: 'pending',
    );

    await _db.transaction((txn) async {
      await txn.insert('workers', worker.toMap());

      await _addOutboxEvent(
        txn,
        workerId: worker.id,
        eventType: 'worker.created',
        payload: worker.toMap(),
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        workerId: worker.id,
        newValue: worker.toMap(),
        now: now,
      );
    });

    return worker;
  }

  // GET WORKERS
  Future<List<Worker>> getWorkers({
    String? search,
    bool? activeOnly,
  }) async {
    final conditions = <String>[];
    final arguments = <Object?>[];

    final cleanSearch = search?.trim();

    if (cleanSearch != null && cleanSearch.isNotEmpty) {
      conditions.add('''
        (
          LOWER(full_name) LIKE ?
          OR LOWER(role) LIKE ?
          OR LOWER(COALESCE(phone, '')) LIKE ?
        )
      ''');

      final value = '%${cleanSearch.toLowerCase()}%';
      arguments.addAll([value, value, value]);
    }

    if (activeOnly == true) {
      conditions.add('active = 1');
    } else if (activeOnly == false) {
      conditions.add('active = 0');
    }

    final rows = await _db.query(
      'workers',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: conditions.isEmpty ? null : arguments,
      orderBy: 'active DESC, full_name COLLATE NOCASE ASC',
    );

    return rows.map(Worker.fromMap).toList();
  }

  // GET WORKER BY ID
  Future<Worker?> getWorkerById(String workerId) async {
    final rows = await _db.query(
      'workers',
      where: 'id = ?',
      whereArgs: [workerId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Worker.fromMap(rows.first);
  }

  // UPDATE WORKER
  Future<Worker> updateWorker({
    required String workerId,
    required String fullName,
    required String role,
    String? phone,
    DateTime? hiredAt,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = fullName.trim();
    final cleanRole = role.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Worker full name is required.');
    }

    if (cleanRole.isEmpty) {
      throw ArgumentError('Worker role is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late Worker updatedWorker;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'workers',
        where: 'id = ?',
        whereArgs: [workerId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Worker was not found.');
      }

      final previous = rows.first;

      final updated = {
        ...previous,
        'full_name': cleanName,
        'role': cleanRole,
        'phone': _cleanOptional(phone),
        'hired_at': hiredAt?.toUtc().toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'workers',
        updated,
        where: 'id = ?',
        whereArgs: [workerId],
      );

      updatedWorker = Worker.fromMap(updated);

      await _addOutboxEvent(
        txn,
        workerId: workerId,
        eventType: 'worker.updated',
        payload: updated,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'update',
        workerId: workerId,
        previousValue: previous,
        newValue: updated,
        now: now,
      );
    });

    return updatedWorker;
  }

  // ACTIVATE OR DEACTIVATE WORKER
  Future<Worker> setWorkerActive({
    required String workerId,
    required bool active,
    required String actorUserId,
    required String deviceId,
  }) async {
    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late Worker updatedWorker;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'workers',
        where: 'id = ?',
        whereArgs: [workerId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Worker was not found.');
      }

      final previous = rows.first;

      final updated = {
        ...previous,
        'active': active ? 1 : 0,
        'sync_state': 'pending',
      };

      await txn.update(
        'workers',
        updated,
        where: 'id = ?',
        whereArgs: [workerId],
      );

      updatedWorker = Worker.fromMap(updated);

      await _addOutboxEvent(
        txn,
        workerId: workerId,
        eventType: active ? 'worker.activated' : 'worker.deactivated',
        payload: updated,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: active ? 'activate' : 'deactivate',
        workerId: workerId,
        previousValue: previous,
        newValue: updated,
        now: now,
      );
    });

    return updatedWorker;
  }

  // INTERNAL HELPERS
  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  void _validateActor(String actorUserId, String deviceId) {
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError(
        'User and device identifiers are required.',
      );
    }
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String workerId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': 'worker',
      'aggregate_id': workerId,
      'event_type': eventType,
      'payload_json': jsonEncode(payload),
      'created_at': now.toIso8601String(),
      'status': 'pending',
    });
  }

  Future<void> _addAuditEntry(
    Transaction txn, {
    required String actorUserId,
    required String deviceId,
    required String action,
    required String workerId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': 'worker',
      'entity_id': workerId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json': newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }
}
