import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local_database.dart';

/// Handles stocktake sessions independently from day-to-day stock movements.
///
/// Counts are stored in base units, while the original entered unit and
/// conversion factor are retained for audit and reporting.
class StocktakeRepository {
  StocktakeRepository({
    LocalDatabase? localDatabase,
    Database? database,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _testDatabase = database;

  final LocalDatabase _localDatabase;
  final Database? _testDatabase;
  final Uuid _uuid = const Uuid();

  Database get _db => _testDatabase ?? _localDatabase.db;

  /// Starts a draft stocktake session.
  Future<Map<String, dynamic>> startStocktake({
    required String actorUserId,
    required String deviceId,
    String? reason,
  }) async {
    _validateActor(actorUserId, deviceId);
    final now = DateTime.now().toUtc();
    final session = <String, dynamic>{
      'id': _uuid.v4(),
      'status': 'draft',
      'actor_user_id': actorUserId.trim(),
      'device_id': deviceId.trim(),
      'reason': _cleanOptional(reason),
      'started_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'completed_at': null,
      'sync_state': 'pending',
    };

    await _db.transaction((txn) async {
      await txn.insert('stocktakes', session);
      await _addOutboxEvent(
        txn,
        aggregateType: 'stocktake',
        aggregateId: session['id'] as String,
        eventType: 'stocktake.started',
        payload: session,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actorUserId.trim(),
        deviceId: deviceId.trim(),
        action: 'create',
        entityType: 'stocktake',
        entityId: session['id'] as String,
        newValue: session,
        reason: _cleanOptional(reason),
        now: now,
      );
    });

    return session;
  }

  /// Saves or replaces the count for one product in a draft stocktake.
  ///
  /// The system quantity is captured on the first count and retained if the
  /// count is edited later. Finalization checks that the live balance still
  /// matches this snapshot.
  Future<Map<String, dynamic>> recordCount({
    required String stocktakeId,
    required String productId,
    required double enteredQuantity,
    required String unitName,
    String? reason,
  }) async {
    if (!enteredQuantity.isFinite || enteredQuantity < 0) {
      throw ArgumentError('Counted quantity must be zero or greater.');
    }
    final cleanUnit = unitName.trim();
    if (cleanUnit.isEmpty) throw ArgumentError('Unit name is required.');

    final now = DateTime.now().toUtc();
    late Map<String, dynamic> savedLine;

    await _db.transaction((txn) async {
      final sessionRows = await txn.query(
        'stocktakes',
        where: 'id = ?',
        whereArgs: [stocktakeId],
        limit: 1,
      );
      if (sessionRows.isEmpty) throw StateError('Stocktake not found.');
      if (sessionRows.first['status'] != 'draft') {
        throw StateError('Only a draft stocktake can be changed.');
      }

      final productRows = await txn.query(
        'products',
        where: 'id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw StateError('Product does not exist or is archived.');
      }

      final unitRows = await txn.query(
        'product_units',
        where: 'product_id = ? AND LOWER(unit_name) = LOWER(?)',
        whereArgs: [productId, cleanUnit],
        limit: 1,
      );
      if (unitRows.isEmpty) {
        throw StateError(
          'Unit "$cleanUnit" is not configured for this product.',
        );
      }

      final factor = (unitRows.first['base_units_per_unit'] as num).toDouble();
      final countedBase = enteredQuantity * factor;
      if (!countedBase.isFinite || countedBase < 0) {
        throw ArgumentError('Converted counted quantity is invalid.');
      }

      final existingRows = await txn.query(
        'stocktake_lines',
        where: 'stocktake_id = ? AND product_id = ?',
        whereArgs: [stocktakeId, productId],
        limit: 1,
      );

      double systemBase;
      String lineId;
      String createdAt;
      Map<String, dynamic>? previous;
      if (existingRows.isNotEmpty) {
        previous = existingRows.first;
        systemBase = (previous['system_quantity_base'] as num).toDouble();
        lineId = previous['id'] as String;
        createdAt = previous['created_at'] as String;
      } else {
        final balanceRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_base), 0) AS balance
          FROM stock_movements
          WHERE product_id = ?
          ''',
          [productId],
        );
        systemBase = (balanceRows.first['balance'] as num).toDouble();
        lineId = _uuid.v4();
        createdAt = now.toIso8601String();
      }

      savedLine = {
        'id': lineId,
        'stocktake_id': stocktakeId,
        'product_id': productId,
        'system_quantity_base': systemBase,
        'counted_quantity_base': countedBase,
        'variance_quantity_base': countedBase - systemBase,
        'unit_name': cleanUnit,
        'entered_quantity': enteredQuantity,
        'conversion_factor': factor,
        'reason': _cleanOptional(reason),
        'created_at': createdAt,
        'updated_at': now.toIso8601String(),
      };

      if (previous == null) {
        await txn.insert('stocktake_lines', savedLine);
      } else {
        await txn.update(
          'stocktake_lines',
          savedLine,
          where: 'id = ?',
          whereArgs: [lineId],
        );
      }

      await txn.update(
        'stocktakes',
        {
          'updated_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [stocktakeId],
      );

      await _addOutboxEvent(
        txn,
        aggregateType: 'stocktake_line',
        aggregateId: lineId,
        eventType: previous == null
            ? 'stocktake_line.counted'
            : 'stocktake_line.updated',
        payload: savedLine,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: sessionRows.first['actor_user_id'] as String,
        deviceId: sessionRows.first['device_id'] as String,
        action: previous == null ? 'count' : 'update_count',
        entityType: 'stocktake_line',
        entityId: lineId,
        previousValue: previous,
        newValue: savedLine,
        reason: _cleanOptional(reason),
        now: now,
      );
    });

    return savedLine;
  }

  Future<List<Map<String, dynamic>>> getStocktakes({
    String? status,
  }) async {
    final cleanStatus = _cleanOptional(status);
    final rows = await _db.query(
      'stocktakes',
      where: cleanStatus == null ? null : 'status = ?',
      whereArgs: cleanStatus == null ? null : [cleanStatus],
      orderBy: 'started_at DESC',
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getStocktakeLines(
    String stocktakeId,
  ) async {
    return _db.query(
      'stocktake_lines',
      where: 'stocktake_id = ?',
      whereArgs: [stocktakeId],
      orderBy: 'created_at ASC',
    );
  }

  /// Finalizes a draft stocktake and writes only the variance as movements.
  ///
  /// All checks, movements, audit entries, outbox events and status changes
  /// are committed together or rolled back together.
  Future<void> finalizeStocktake({
    required String stocktakeId,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.transaction((txn) async {
      final sessionRows = await txn.query(
        'stocktakes',
        where: 'id = ?',
        whereArgs: [stocktakeId],
        limit: 1,
      );
      if (sessionRows.isEmpty) throw StateError('Stocktake not found.');
      final session = sessionRows.first;
      if (session['status'] != 'draft') {
        throw StateError('Only a draft stocktake can be finalized.');
      }

      final lines = await txn.query(
        'stocktake_lines',
        where: 'stocktake_id = ?',
        whereArgs: [stocktakeId],
        orderBy: 'created_at ASC',
      );
      if (lines.isEmpty) {
        throw StateError('Add at least one product count before finalizing.');
      }

      final actor = session['actor_user_id'] as String;
      final device = session['device_id'] as String;

      for (final line in lines) {
        final productId = line['product_id'] as String;
        final balanceRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(quantity_base), 0) AS balance
          FROM stock_movements
          WHERE product_id = ?
          ''',
          [productId],
        );
        final liveBalance = (balanceRows.first['balance'] as num).toDouble();
        final snapshot = (line['system_quantity_base'] as num).toDouble();
        if ((liveBalance - snapshot).abs() > 0.000001) {
          throw StateError(
            'Stock for product $productId changed after it was counted. '
            'Recount this product before finalizing.',
          );
        }

        final variance = (line['variance_quantity_base'] as num).toDouble();
        if (variance.abs() <= 0.000001) continue;

        final lineReason = _cleanOptional(line['reason'] as String?);
        final sessionReason = _cleanOptional(session['reason'] as String?);
        final movementReason = lineReason ?? sessionReason;
        if (movementReason == null) {
          throw StateError(
            'A reason is required for the stock discrepancy '
            'on product $productId.',
          );
        }

        final factor = (line['conversion_factor'] as num).toDouble();
        final movement = <String, dynamic>{
          'id': _uuid.v4(),
          'product_id': productId,
          'movement_type': variance > 0 ? 'adjustment_in' : 'adjustment_out',
          'quantity_base': variance,
          'unit_name': line['unit_name'],
          'entered_quantity': variance.abs() / factor,
          'conversion_factor': factor,
          'reference_type': 'stocktake',
          'reference_id': stocktakeId,
          'reason': movementReason,
          'actor_user_id': actor,
          'device_id': device,
          'occurred_at': now.toIso8601String(),
          'sync_state': 'pending',
        };

        await txn.insert('stock_movements', movement);
        await _addOutboxEvent(
          txn,
          aggregateType: 'stock_movement',
          aggregateId: movement['id'] as String,
          eventType: 'stock.stocktake_adjustment_recorded',
          payload: movement,
          now: now,
        );
        await _addAuditEntry(
          txn,
          actorUserId: actor,
          deviceId: device,
          action: 'stocktake_adjustment',
          entityType: 'product',
          entityId: productId,
          newValue: movement,
          reason: movementReason,
          now: now,
        );
      }

      final completed = <String, dynamic>{
        ...session,
        'status': 'completed',
        'updated_at': now.toIso8601String(),
        'completed_at': now.toIso8601String(),
        'sync_state': 'pending',
      };
      await txn.update(
        'stocktakes',
        {
          'status': 'completed',
          'updated_at': now.toIso8601String(),
          'completed_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [stocktakeId],
      );

      final completedPayload = {
        'stocktake': completed,
        'lines': lines,
      };
      await _addOutboxEvent(
        txn,
        aggregateType: 'stocktake',
        aggregateId: stocktakeId,
        eventType: 'stocktake.completed',
        payload: completedPayload,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: actor,
        deviceId: device,
        action: 'complete',
        entityType: 'stocktake',
        entityId: stocktakeId,
        previousValue: session,
        newValue: completedPayload,
        reason: _cleanOptional(session['reason'] as String?),
        now: now,
      );
    });
  }

  Future<void> cancelStocktake({
    required String stocktakeId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('A cancellation reason is required.');
    }
    final now = DateTime.now().toUtc();

    await _db.transaction((txn) async {
      final rows = await txn.query(
        'stocktakes',
        where: 'id = ?',
        whereArgs: [stocktakeId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Stocktake not found.');
      final session = rows.first;
      if (session['status'] != 'draft') {
        throw StateError('Only a draft stocktake can be cancelled.');
      }

      final cancelled = {
        ...session,
        'status': 'cancelled',
        'reason': cleanReason,
        'updated_at': now.toIso8601String(),
        'sync_state': 'pending',
      };
      await txn.update(
        'stocktakes',
        {
          'status': 'cancelled',
          'reason': cleanReason,
          'updated_at': now.toIso8601String(),
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [stocktakeId],
      );
      await _addOutboxEvent(
        txn,
        aggregateType: 'stocktake',
        aggregateId: stocktakeId,
        eventType: 'stocktake.cancelled',
        payload: cancelled,
        now: now,
      );
      await _addAuditEntry(
        txn,
        actorUserId: session['actor_user_id'] as String,
        deviceId: session['device_id'] as String,
        action: 'cancel',
        entityType: 'stocktake',
        entityId: stocktakeId,
        previousValue: session,
        newValue: cancelled,
        reason: cleanReason,
        now: now,
      );
    });
  }

  void _validateActor(String actorUserId, String deviceId) {
    if (actorUserId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('User and device identifiers are required.');
    }
  }

  String? _cleanOptional(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  Future<void> _addOutboxEvent(
    Transaction txn, {
    required String aggregateType,
    required String aggregateId,
    required String eventType,
    required Map<String, dynamic> payload,
    required DateTime now,
  }) async {
    await txn.insert('sync_outbox', {
      'event_id': _uuid.v4(),
      'aggregate_type': aggregateType,
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
    required String entityType,
    required String entityId,
    Map<String, dynamic>? previousValue,
    Map<String, dynamic>? newValue,
    String? reason,
    required DateTime now,
  }) async {
    await txn.insert('audit_log', {
      'id': _uuid.v4(),
      'actor_user_id': actorUserId,
      'device_id': deviceId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'previous_value_json':
          previousValue == null ? null : jsonEncode(previousValue),
      'new_value_json': newValue == null ? null : jsonEncode(newValue),
      'reason': reason,
      'occurred_at': now.toIso8601String(),
    });
  }
}
