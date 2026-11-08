import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/workers/repositories/worker_repository.dart';

void main() {
  late Database database;
  late WorkerRepository repository;

  const actor = 'test-user';
  const device = 'test-device';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE workers (
              id TEXT PRIMARY KEY,
              full_name TEXT NOT NULL,
              phone TEXT,
              role TEXT NOT NULL,
              active INTEGER NOT NULL DEFAULT 1,
              hired_at TEXT,
              created_at TEXT NOT NULL,
              sync_state TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE sync_outbox (
              event_id TEXT PRIMARY KEY,
              aggregate_type TEXT NOT NULL,
              aggregate_id TEXT NOT NULL,
              event_type TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              status TEXT NOT NULL DEFAULT 'pending'
            )
          ''');

          await db.execute('''
            CREATE TABLE audit_log (
              id TEXT PRIMARY KEY,
              actor_user_id TEXT,
              device_id TEXT,
              action TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT,
              previous_value_json TEXT,
              new_value_json TEXT,
              reason TEXT,
              occurred_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );

    repository = WorkerRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('WorkerRepository', () {
    test('creates a worker and records sync and audit entries', () async {
      final worker = await repository.createWorker(
        fullName: '  John Kamau ',
        role: '  Sales Assistant ',
        phone: ' 0712345678 ',
        hiredAt: DateTime.utc(2026, 10, 1),
        actorUserId: actor,
        deviceId: device,
      );

      expect(worker.fullName, 'John Kamau');
      expect(worker.role, 'Sales Assistant');
      expect(worker.phone, '0712345678');
      expect(worker.active, isTrue);
      expect(worker.syncState, 'pending');

      final rows = await database.query(
        'workers',
        where: 'id = ?',
        whereArgs: [worker.id],
      );

      expect(rows, hasLength(1));

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [worker.id],
      );

      expect(events, hasLength(1));
      expect(events.first['event_type'], 'worker.created');
      expect(events.first['aggregate_type'], 'worker');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [worker.id],
      );

      expect(audits, hasLength(1));
      expect(audits.first['action'], 'create');
      expect(audits.first['entity_type'], 'worker');
      expect(audits.first['actor_user_id'], actor);
      expect(audits.first['device_id'], device);
    });

    test('creates a worker without optional details', () async {
      final worker = await repository.createWorker(
        fullName: 'Jane Wanjiku',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      expect(worker.phone, isNull);
      expect(worker.hiredAt, isNull);
      expect(worker.active, isTrue);
    });

    test('rejects invalid worker details', () async {
      await expectLater(
        repository.createWorker(
          fullName: ' ',
          role: 'Cashier',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createWorker(
          fullName: 'John Kamau',
          role: ' ',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('workers'), isEmpty);
    });

    test('rejects missing actor or device identifiers', () async {
      await expectLater(
        repository.createWorker(
          fullName: 'John Kamau',
          role: 'Cashier',
          actorUserId: '',
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createWorker(
          fullName: 'John Kamau',
          role: 'Cashier',
          actorUserId: actor,
          deviceId: ' ',
        ),
        throwsArgumentError,
      );

      expect(await database.query('workers'), isEmpty);
    });

    test('lists workers alphabetically with active workers first', () async {
      await repository.createWorker(
        fullName: 'Zack Mwangi',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      final inactive = await repository.createWorker(
        fullName: 'Alice Wanjiku',
        role: 'Sales Assistant',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.setWorkerActive(
        workerId: inactive.id,
        active: false,
        actorUserId: actor,
        deviceId: device,
      );

      await repository.createWorker(
        fullName: 'Brian Otieno',
        role: 'Storekeeper',
        actorUserId: actor,
        deviceId: device,
      );

      final workers = await repository.getWorkers();

      expect(workers, hasLength(3));
      expect(workers[0].fullName, 'Brian Otieno');
      expect(workers[1].fullName, 'Zack Mwangi');
      expect(workers[2].fullName, 'Alice Wanjiku');
      expect(workers[2].active, isFalse);
    });

    test('filters workers by active status', () async {
      final active = await repository.createWorker(
        fullName: 'Active Worker',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      final inactive = await repository.createWorker(
        fullName: 'Inactive Worker',
        role: 'Storekeeper',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.setWorkerActive(
        workerId: inactive.id,
        active: false,
        actorUserId: actor,
        deviceId: device,
      );

      final activeWorkers = await repository.getWorkers(activeOnly: true);
      final inactiveWorkers = await repository.getWorkers(activeOnly: false);

      expect(activeWorkers, hasLength(1));
      expect(activeWorkers.first.id, active.id);

      expect(inactiveWorkers, hasLength(1));
      expect(inactiveWorkers.first.id, inactive.id);
    });

    test('searches workers by name, role and phone', () async {
      await repository.createWorker(
        fullName: 'John Kamau',
        role: 'Cashier',
        phone: '0712345678',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.createWorker(
        fullName: 'Jane Wanjiku',
        role: 'Storekeeper',
        phone: '0723456789',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getWorkers(search: 'JOHN'),
        hasLength(1),
      );

      expect(
        await repository.getWorkers(search: 'storekeeper'),
        hasLength(1),
      );

      expect(
        await repository.getWorkers(search: '0723456789'),
        hasLength(1),
      );

      expect(
        await repository.getWorkers(search: 'not-found'),
        isEmpty,
      );
    });

    test('retrieves a worker by ID', () async {
      final created = await repository.createWorker(
        fullName: 'John Kamau',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      final found = await repository.getWorkerById(created.id);

      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.fullName, 'John Kamau');

      expect(
        await repository.getWorkerById('missing-worker'),
        isNull,
      );
    });

    test('updates a worker and records sync and audit entries', () async {
      final created = await repository.createWorker(
        fullName: 'John Kamau',
        role: 'Cashier',
        phone: '0711111111',
        actorUserId: actor,
        deviceId: device,
      );

      final updated = await repository.updateWorker(
        workerId: created.id,
        fullName: 'John Mwangi',
        role: 'Storekeeper',
        phone: '0722222222',
        hiredAt: DateTime.utc(2026, 10, 5),
        actorUserId: actor,
        deviceId: device,
      );

      expect(updated.fullName, 'John Mwangi');
      expect(updated.role, 'Storekeeper');
      expect(updated.phone, '0722222222');
      expect(updated.hiredAt, DateTime.utc(2026, 10, 5));
      expect(updated.active, isTrue);
      expect(updated.syncState, 'pending');

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
      );

      expect(events, hasLength(2));
      expect(events.last['event_type'], 'worker.updated');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [created.id],
      );

      expect(audits, hasLength(2));
      expect(audits.last['action'], 'update');
      expect(audits.last['previous_value_json'], isNotNull);
      expect(audits.last['new_value_json'], isNotNull);
    });

    test('rejects updating a worker that does not exist', () async {
      await expectLater(
        repository.updateWorker(
          workerId: 'missing-worker',
          fullName: 'John Kamau',
          role: 'Cashier',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsStateError,
      );
    });

    test('deactivates a worker without deleting the record', () async {
      final created = await repository.createWorker(
        fullName: 'John Kamau',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      final deactivated = await repository.setWorkerActive(
        workerId: created.id,
        active: false,
        actorUserId: actor,
        deviceId: device,
      );

      expect(deactivated.active, isFalse);

      final rows = await database.query(
        'workers',
        where: 'id = ?',
        whereArgs: [created.id],
      );

      expect(rows, hasLength(1));
      expect(rows.first['active'], 0);

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
      );

      expect(events.last['event_type'], 'worker.deactivated');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [created.id],
      );

      expect(audits.last['action'], 'deactivate');
    });

    test('reactivates a previously deactivated worker', () async {
      final created = await repository.createWorker(
        fullName: 'John Kamau',
        role: 'Cashier',
        actorUserId: actor,
        deviceId: device,
      );

      await repository.setWorkerActive(
        workerId: created.id,
        active: false,
        actorUserId: actor,
        deviceId: device,
      );

      final reactivated = await repository.setWorkerActive(
        workerId: created.id,
        active: true,
        actorUserId: actor,
        deviceId: device,
      );

      expect(reactivated.active, isTrue);

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
      );

      expect(events, hasLength(3));
      expect(events.last['event_type'], 'worker.activated');
    });

    test('rejects changing the status of a missing worker', () async {
      await expectLater(
        repository.setWorkerActive(
          workerId: 'missing-worker',
          active: false,
          actorUserId: actor,
          deviceId: device,
        ),
        throwsStateError,
      );
    });
  });
}
