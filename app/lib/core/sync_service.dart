import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../data/local_database.dart';

enum ConnectionStateStatus {
  online,
  offline,
  syncing,
  error,
}

class SyncStatus {
  SyncStatus({
    required this.status,
    required this.pendingCount,
    required this.failedCount,
    this.lastSyncTimestamp,
    this.errorMessage,
  });

  final ConnectionStateStatus status;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncTimestamp;
  final String? errorMessage;
}

class SyncService extends ChangeNotifier {
  SyncService({
    LocalDatabase? localDatabase,
    http.Client? httpClient,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _client = httpClient ?? http.Client() {
    _initConnectivityListener();
  }

  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService();

  final LocalDatabase _localDatabase;
  final http.Client _client;

  String _serverUrl = 'http://localhost:8000';
  String? _authToken;
  String _deviceId = 'device-local-1';

  ConnectionStateStatus _currentStatus = ConnectionStateStatus.offline;
  int _pendingCount = 0;
  int _failedCount = 0;
  DateTime? _lastSyncTimestamp;
  String? _lastError;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _autoSyncTimer;

  ConnectionStateStatus get status => _currentStatus;
  int get pendingCount => _pendingCount;
  int get failedCount => _failedCount;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;
  String? get lastError => _lastError;
  bool get isOnline => _currentStatus == ConnectionStateStatus.online || _currentStatus == ConnectionStateStatus.syncing;

  void configure({
    required String serverUrl,
    String? authToken,
    required String deviceId,
  }) {
    _serverUrl = serverUrl.replaceAll(RegExp(r'/$'), '');
    _authToken = authToken;
    _deviceId = deviceId;
  }

  void _initConnectivityListener() {
    Connectivity().checkConnectivity().then((results) {
      _handleConnectivityChange(results);
    }).catchError((_) {});

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) => _handleConnectivityChange(results),
    );

    // Periodically check outbox count and trigger sync every 30 seconds
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshOutboxMetrics();
      if (_currentStatus == ConnectionStateStatus.online && _pendingCount > 0) {
        triggerSync();
      }
    });

    refreshOutboxMetrics();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    if (hasNet) {
      if (_currentStatus == ConnectionStateStatus.offline) {
        _currentStatus = ConnectionStateStatus.online;
        notifyListeners();
        triggerSync();
      }
    } else {
      _currentStatus = ConnectionStateStatus.offline;
      notifyListeners();
    }
  }

  Future<void> refreshOutboxMetrics() async {
    try {
      final db = _localDatabase.db;
      final pendingRows = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_outbox WHERE status = 'pending'",
      );
      final failedRows = await db.rawQuery(
        "SELECT COUNT(*) as count FROM sync_outbox WHERE status = 'failed'",
      );

      _pendingCount = (pendingRows.first['count'] as num).toInt();
      _failedCount = (failedRows.first['count'] as num).toInt();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> triggerSync() async {
    if (_currentStatus == ConnectionStateStatus.syncing) return false;

    _currentStatus = ConnectionStateStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      final db = _localDatabase.db;

      // 1. Fetch pending outbox items
      final outboxRows = await db.query(
        'sync_outbox',
        where: "status = 'pending'",
        orderBy: 'created_at ASC',
        limit: 50,
      );

      if (outboxRows.isNotEmpty) {
        final events = outboxRows.map((r) {
          return {
            'event_id': r['id'],
            'aggregate_type': r['aggregate_type'],
            'aggregate_id': r['aggregate_id'],
            'event_type': r['event_type'],
            'payload': jsonDecode(r['payload'] as String),
            'occurred_at': r['created_at'],
          };
        }).toList();

        final response = await _client.post(
          Uri.parse('$_serverUrl/api/sync/push'),
          headers: {
            'Content-Type': 'application/json',
            if (_authToken != null) 'Authorization': 'Bearer $_authToken',
          },
          body: jsonEncode({
            'device_id': _deviceId,
            'events': events,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final resData = jsonDecode(response.body) as Map<String, dynamic>;
          final processedIds = (resData['processed_ids'] as List?)?.cast<String>() ?? [];
          final duplicateIds = (resData['duplicate_ids'] as List?)?.cast<String>() ?? [];

          final syncedIds = [...processedIds, ...duplicateIds];

          if (syncedIds.isNotEmpty) {
            await db.transaction((txn) async {
              for (final id in syncedIds) {
                await txn.update(
                  'sync_outbox',
                  {
                    'status': 'synced',
                    'synced_at': DateTime.now().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
            });
          }
        } else {
          _lastError = 'Server returned HTTP ${response.statusCode}';
          _currentStatus = ConnectionStateStatus.error;
          await refreshOutboxMetrics();
          notifyListeners();
          return false;
        }
      }

      // 2. Pull server changes if endpoint available
      try {
        final pullResponse = await _client.get(
          Uri.parse('$_serverUrl/api/sync/pull'),
          headers: {
            if (_authToken != null) 'Authorization': 'Bearer $_authToken',
          },
        ).timeout(const Duration(seconds: 5));

        if (pullResponse.statusCode == 200) {
          // Sync pull successful
        }
      } catch (_) {}

      _lastSyncTimestamp = DateTime.now();
      _currentStatus = ConnectionStateStatus.online;
      await refreshOutboxMetrics();
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'Sync connection failed: $e';
      _currentStatus = ConnectionStateStatus.error;
      await refreshOutboxMetrics();
      notifyListeners();
      return false;
    }
  }

  Future<void> retryFailedItems() async {
    final db = _localDatabase.db;
    await db.update(
      'sync_outbox',
      {'status': 'pending'},
      where: "status = 'failed'",
    );
    await refreshOutboxMetrics();
    triggerSync();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
