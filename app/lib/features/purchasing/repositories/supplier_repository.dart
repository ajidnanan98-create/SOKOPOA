import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';
import '../models/supplier.dart';

class SupplierRepository {
  SupplierRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  // CREATE SUPPLIER
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    final supplier = Supplier(
      id: _uuid.v4(),
      name: cleanName,
      phone: _cleanOptional(phone),
      email: _cleanOptional(email),
      address: _cleanOptional(address),
      createdAt: now,
      updatedAt: now,
    );

    await _db.transaction((txn) async {
      await txn.insert('suppliers', supplier.toMap());

      await _addOutboxEvent(
        txn,
        aggregateId: supplier.id,
        eventType: 'supplier.created',
        payload: supplier.toMap(),
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'create',
        entityId: supplier.id,
        newValue: supplier.toMap(),
        now: now,
      );
    });

    return supplier;
  }

  // GET ALL SUPPLIERS
  Future<List<Supplier>> getSuppliers({
    String? search,
  }) async {
    final cleanedSearch = search?.trim();

    final rows = await _db.query(
      'suppliers',
      where: cleanedSearch == null || cleanedSearch.isEmpty
          ? null
          : '''
            LOWER(name) LIKE ?
            OR LOWER(COALESCE(phone, '')) LIKE ?
            OR LOWER(COALESCE(email, '')) LIKE ?
          ''',
      whereArgs: cleanedSearch == null || cleanedSearch.isEmpty
          ? null
          : [
              '%${cleanedSearch.toLowerCase()}%',
              '%${cleanedSearch.toLowerCase()}%',
              '%${cleanedSearch.toLowerCase()}%',
            ],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(Supplier.fromMap).toList();
  }

  // GET SUPPLIER BY ID
  Future<Supplier?> getSupplierById(String supplierId) async {
    final rows = await _db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [supplierId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return Supplier.fromMap(rows.first);
  }

  // UPDATE SUPPLIER
  Future<Supplier> updateSupplier({
    required String supplierId,
    required String name,
    String? phone,
    String? email,
    String? address,
    required String actorUserId,
    required String deviceId,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Supplier name is required.');
    }

    _validateActor(actorUserId, deviceId);

    final now = DateTime.now().toUtc();

    late Supplier updatedSupplier;

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplierId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('Supplier was not found.');
      }

      final previous = rows.first;

      final updated = {
        ...previous,
        'name': cleanName,
        'phone': _cleanOptional(phone),
        'email': _cleanOptional(email),
        'address': _cleanOptional(address),
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };

      await txn.update(
        'suppliers',
        updated,
        where: 'id = ?',
        whereArgs: [supplierId],
      );

      updatedSupplier = Supplier.fromMap(updated);

      await _addOutboxEvent(
        txn,
        aggregateId: supplierId,
        eventType: 'supplier.updated',
        payload: updated,
        now: now,
      );

      await _addAuditEntry(
        txn,
        actorUserId: actorUserId,
        deviceId: deviceId,
        action: 'update',
        entityId: supplierId,
        previousValue: previous,
        newValue: updated,
        now: now,
      );
    });

    return updatedSupplier;
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
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': 'supplier',
      'aggregate_id': aggregateId,
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
    required String entityId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': 'supplier',
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json':
          newValue == null ? null : jsonEncode(newValue),
      'occurred_at': now.toIso8601String(),
    });
  }
}