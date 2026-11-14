import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uber_maids_watch/core/local_database.dart';
import 'package:uber_maids_watch/core/models.dart';

void main() {
  group('LocalDatabase', () {
    test('queues a local write and hides it from pending count once applied', () {
      final db = LocalDatabase.memory();
      db.writeLocal(
        entity: 'worker',
        id: 'w1',
        data: {'full_name': 'Amina', 'server_version': 3},
      );

      expect(db.recordsFor('worker'), hasLength(1));
      expect(db.pendingCount, 1);
      expect(db.find('worker', 'w1')!.dirty, isTrue);
      expect(db.find('worker', 'w1')!.baseVersion, 0);

      final mutation = db.pendingMutations.single;
      expect(mutation.operation, 'upsert');
      expect(mutation.data['full_name'], 'Amina');

      db.markApplied(
        mutation.mutationId,
        serverRecord: const {
          'id': 'w1',
          'full_name': 'Amina',
          'server_version': 4,
          'change_seq': 12,
        },
      );

      expect(db.pendingCount, 0);
      expect(db.find('worker', 'w1')!.dirty, isFalse);
      expect(db.find('worker', 'w1')!.baseVersion, 4);
      expect(db.cursor, 0);
    });

    test('coalesces repeated edits into one pending mutation', () {
      final db = LocalDatabase.memory();
      db.writeLocal(entity: 'client', id: 'c1', data: {'full_name': 'A'});
      db.writeLocal(entity: 'client', id: 'c1', data: {'full_name': 'B'});

      expect(db.pendingCount, 1);
      expect(db.pendingMutations.single.data['full_name'], 'B');
    });

    test('keeps a local edit when the server changes underneath it', () {
      final db = LocalDatabase.memory();
      db.applyServerChange(
        entity: 'worker',
        id: 'w1',
        data: {'id': 'w1', 'full_name': 'Server', 'server_version': 2},
        changeSeq: 5,
        deleted: false,
      );
      db.writeLocal(
        entity: 'worker',
        id: 'w1',
        data: {'id': 'w1', 'full_name': 'Local', 'server_version': 2},
      );

      db.applyServerChange(
        entity: 'worker',
        id: 'w1',
        data: {'id': 'w1', 'full_name': 'Remote edit', 'server_version': 3},
        changeSeq: 6,
        deleted: false,
      );

      final record = db.find('worker', 'w1')!;
      expect(record.data['full_name'], 'Local');
      expect(record.hasConflict, isTrue);
      expect(record.serverData!['full_name'], 'Remote edit');

      final mutation = db.pendingMutations.single;
      db.markConflict(
        mutation.mutationId,
        serverRecord: record.serverData,
        message: 'Changed elsewhere',
      );
      expect(db.conflictCount, 1);

      db.resolveKeepMine(mutation.mutationId);
      expect(db.conflictCount, 0);
      expect(db.pendingCount, 1);
      expect(db.find('worker', 'w1')!.baseVersion, 3);
      expect(db.find('worker', 'w1')!.serverData, isNull);
    });

    test('discarding a conflict accepts the server copy', () {
      final db = LocalDatabase.memory();
      db.applyServerChange(
        entity: 'client',
        id: 'c1',
        data: {'id': 'c1', 'full_name': 'Server', 'server_version': 1},
        changeSeq: 1,
        deleted: false,
      );
      db.writeLocal(
        entity: 'client',
        id: 'c1',
        data: {'id': 'c1', 'full_name': 'Local', 'server_version': 1},
      );
      final mutation = db.pendingMutations.single;
      db.markConflict(
        mutation.mutationId,
        serverRecord: const {
          'id': 'c1',
          'full_name': 'Server newer',
          'server_version': 2,
        },
      );

      db.resolveUseServer(mutation.mutationId);

      expect(db.pendingCount, 0);
      expect(db.find('client', 'c1')!.data['full_name'], 'Server newer');
      expect(db.find('client', 'c1')!.dirty, isFalse);
    });

    test('deletes are soft and queued as tombstones', () {
      final db = LocalDatabase.memory();
      db.writeLocal(entity: 'service', id: 's1', data: {'name': 'Cleaning'});
      final first = db.pendingMutations.single;
      db.markApplied(
        first.mutationId,
        serverRecord: const {
          'id': 's1',
          'name': 'Cleaning',
          'server_version': 1,
          'change_seq': 2,
        },
      );

      db.deleteLocal(entity: 'service', id: 's1');

      expect(db.recordsFor('service'), isEmpty);
      expect(db.recordsFor('service', includeDeleted: true), hasLength(1));
      final mutation = db.pendingMutations.single;
      expect(mutation.operation, 'delete');
      expect(mutation.baseVersion, 1);
    });

    test('persists records, cursor and outbox to disk', () async {
      final directory = await Directory.systemTemp.createTemp('umw_test_');
      addTearDown(() => directory.delete(recursive: true));

      final db = await LocalDatabase.open(
        userKey: 'user 1',
        directory: directory.path,
      );
      db.setCursor(42);
      db.writeLocal(entity: 'worker', id: 'w1', data: {'full_name': 'Amina'});
      await db.flush();

      final reopened = await LocalDatabase.open(
        userKey: 'user 1',
        directory: directory.path,
      );
      expect(reopened.cursor, 42);
      expect(reopened.find('worker', 'w1')!.data['full_name'], 'Amina');
      expect(reopened.pendingCount, 1);
      expect(
        File(p.join(directory.path, 'user_1', 'cache.json')).existsSync(),
        isTrue,
      );
    });

    test('payload strips server-managed fields', () {
      final payload = payloadForEntity('worker', {
        'full_name': 'Amina',
        'change_seq': 8,
        'server_version': 3,
        'not_a_field': 'x',
      });
      expect(payload, {'full_name': 'Amina'});
      expect(OutboxStatus.pending, 'pending');
    });
  });
}
