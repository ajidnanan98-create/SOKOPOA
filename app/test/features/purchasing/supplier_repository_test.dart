import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sokopoa/features/purchasing/repositories/supplier_repository.dart';

void main() {
  late Database database;
  late SupplierRepository repository;

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
            CREATE TABLE suppliers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              email TEXT,
              address TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
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

    repository = SupplierRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('SupplierRepository', () {
    test('creates a supplier and records sync and audit entries', () async {
      final supplier = await repository.createSupplier(
        name: '  Sunrise Distributors  ',
        phone: ' 0712345678 ',
        email: ' sales@sunrise.co.ke ',
        address: ' Nairobi ',
        actorUserId: actor,
        deviceId: device,
      );

      expect(supplier.name, 'Sunrise Distributors');
      expect(supplier.phone, '0712345678');
      expect(supplier.email, 'sales@sunrise.co.ke');
      expect(supplier.address, 'Nairobi');
      expect(supplier.syncState, 'pending');

      final rows = await database.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplier.id],
      );

      expect(rows, hasLength(1));

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [supplier.id],
      );

      expect(events, hasLength(1));
      expect(events.first['event_type'], 'supplier.created');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [supplier.id],
      );

      expect(audits, hasLength(1));
      expect(audits.first['action'], 'create');
      expect(audits.first['entity_type'], 'supplier');
      expect(audits.first['actor_user_id'], actor);
      expect(audits.first['device_id'], device);
    });

    test('creates a supplier without optional contact details', () async {
      final supplier = await repository.createSupplier(
        name: '  Fresh Foods Ltd ',
        actorUserId: actor,
        deviceId: device,
      );

      expect(supplier.name, 'Fresh Foods Ltd');
      expect(supplier.phone, isNull);
      expect(supplier.email, isNull);
      expect(supplier.address, isNull);
    });

    test('rejects an empty supplier name', () async {
      await expectLater(
        repository.createSupplier(
          name: '   ',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      expect(await database.query('suppliers'), isEmpty);
    });

    test('rejects missing actor or device identifiers', () async {
      await expectLater(
        repository.createSupplier(
          name: 'Valid Supplier',
          actorUserId: '',
          deviceId: device,
        ),
        throwsArgumentError,
      );

      await expectLater(
        repository.createSupplier(
          name: 'Valid Supplier',
          actorUserId: actor,
          deviceId: ' ',
        ),
        throwsArgumentError,
      );

      expect(await database.query('suppliers'), isEmpty);
    });

    test('lists suppliers alphabetically', () async {
      for (final name in ['Zulu Traders', 'Alpha Supplies']) {
        await repository.createSupplier(
          name: name,
          actorUserId: actor,
          deviceId: device,
        );
      }

      final suppliers = await repository.getSuppliers();

      expect(
        suppliers.map((supplier) => supplier.name).toList(),
        ['Alpha Supplies', 'Zulu Traders'],
      );
    });

    test('searches suppliers by name, phone and email', () async {
      await repository.createSupplier(
        name: 'Sunrise Distributors',
        phone: '0712345678',
        email: 'sales@sunrise.co.ke',
        actorUserId: actor,
        deviceId: device,
      );

      expect(
        await repository.getSuppliers(search: 'SUNRISE'),
        hasLength(1),
      );

      expect(
        await repository.getSuppliers(search: '0712345678'),
        hasLength(1),
      );

      expect(
        await repository.getSuppliers(search: 'sunrise.co.ke'),
        hasLength(1),
      );

      expect(
        await repository.getSuppliers(search: 'not-found'),
        isEmpty,
      );
    });

    test('retrieves a supplier by ID', () async {
      final created = await repository.createSupplier(
        name: 'Meru Wholesale',
        actorUserId: actor,
        deviceId: device,
      );

      final found = await repository.getSupplierById(created.id);

      expect(found, isNotNull);
      expect(found!.id, created.id);
      expect(found.name, 'Meru Wholesale');

      expect(
        await repository.getSupplierById('missing-supplier'),
        isNull,
      );
    });

    test('updates supplier details and records sync and audit entries',
        () async {
      final created = await repository.createSupplier(
        name: 'Old Supplier Name',
        phone: '0700000000',
        actorUserId: actor,
        deviceId: device,
      );

      final updated = await repository.updateSupplier(
        supplierId: created.id,
        name: '  New Supplier Name ',
        phone: ' 0722222222 ',
        email: ' new@example.com ',
        address: ' Meru ',
        actorUserId: actor,
        deviceId: device,
      );

      expect(updated.name, 'New Supplier Name');
      expect(updated.phone, '0722222222');
      expect(updated.email, 'new@example.com');
      expect(updated.address, 'Meru');
      expect(updated.syncState, 'pending');
      expect(updated.updatedAt.isAfter(created.updatedAt), isTrue);

      final events = await database.query(
        'sync_outbox',
        where: 'aggregate_id = ?',
        whereArgs: [created.id],
        orderBy: 'created_at ASC',
      );

      expect(events, hasLength(2));
      expect(events.last['event_type'], 'supplier.updated');

      final audits = await database.query(
        'audit_log',
        where: 'entity_id = ?',
        whereArgs: [created.id],
        orderBy: 'occurred_at ASC',
      );

      expect(audits, hasLength(2));
      expect(audits.last['action'], 'update');
      expect(audits.last['previous_value_json'], isNotNull);
      expect(audits.last['new_value_json'], isNotNull);
    });

    test('rejects updating a supplier with an empty name', () async {
      final created = await repository.createSupplier(
        name: 'Valid Supplier',
        actorUserId: actor,
        deviceId: device,
      );

      await expectLater(
        repository.updateSupplier(
          supplierId: created.id,
          name: ' ',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsArgumentError,
      );

      final unchanged = await repository.getSupplierById(created.id);

      expect(unchanged!.name, 'Valid Supplier');
    });

    test('rejects updating a supplier that does not exist', () async {
      await expectLater(
        repository.updateSupplier(
          supplierId: 'missing-supplier',
          name: 'New Name',
          actorUserId: actor,
          deviceId: device,
        ),
        throwsStateError,
      );
    });
  });
}
