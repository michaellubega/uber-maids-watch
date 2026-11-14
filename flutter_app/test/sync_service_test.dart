import 'package:flutter_test/flutter_test.dart';
import 'package:uber_maids_watch/core/api_client.dart';
import 'package:uber_maids_watch/core/local_database.dart';
import 'package:uber_maids_watch/core/sync_service.dart';

class FakeTransport implements SyncTransport {
  FakeTransport({
    this.pushHandler,
    this.pullHandler,
  });

  final Map<String, dynamic> Function(List<Map<String, dynamic>> mutations)?
      pushHandler;
  final Map<String, dynamic> Function(int since, int limit)? pullHandler;

  int pushCalls = 0;
  int pullCalls = 0;
  List<Map<String, dynamic>> lastMutations = const [];

  @override
  Future<Map<String, dynamic>> push({
    required List<Map<String, dynamic>> mutations,
  }) async {
    pushCalls++;
    lastMutations = mutations;
    if (pushHandler == null) return {'results': const []};
    return pushHandler!(mutations);
  }

  @override
  Future<Map<String, dynamic>> pull({
    required int since,
    required int limit,
  }) async {
    pullCalls++;
    if (pullHandler == null) {
      return {
        'changes': const [],
        'next_since': since,
        'has_more': false,
      };
    }
    return pullHandler!(since, limit);
  }
}

void main() {
  group('SyncService', () {
    test('uploads queued writes then downloads changes', () async {
      final db = LocalDatabase.memory();
      db.writeLocal(
        entity: 'worker',
        id: 'w1',
        data: {'full_name': 'Amina'},
      );
      final transport = FakeTransport(
        pushHandler: (mutations) => {
          'results': [
            {
              'mutation_id': mutations.single['mutation_id'],
              'status': 'applied',
              'record': {
                'id': 'w1',
                'full_name': 'Amina',
                'server_version': 1,
                'change_seq': 4,
              },
            },
          ],
        },
        pullHandler: (since, limit) => {
          'changes': [
            {
              'entity': 'client',
              'id': 'c1',
              'change_seq': 5,
              'deleted': false,
              'data': {
                'id': 'c1',
                'full_name': 'Nakato',
                'server_version': 1,
              },
            },
          ],
          'next_since': 5,
          'has_more': false,
        },
      );

      final outcome = await SyncService(database: db, transport: transport)
          .sync();

      expect(outcome.succeeded, isTrue);
      expect(outcome.applied, 1);
      expect(outcome.pulled, 1);
      expect(db.pendingCount, 0);
      expect(db.find('client', 'c1')!.data['full_name'], 'Nakato');
      expect(db.cursor, 5);
      expect(transport.pushCalls, 1);
      expect(transport.pullCalls, 1);
    });

    test('surfaces a conflict and keeps the local copy', () async {
      final db = LocalDatabase.memory();
      db.applyServerChange(
        entity: 'worker',
        id: 'w1',
        data: {'id': 'w1', 'full_name': 'Server', 'server_version': 2},
        changeSeq: 2,
        deleted: false,
      );
      db.writeLocal(
        entity: 'worker',
        id: 'w1',
        data: {'id': 'w1', 'full_name': 'Local', 'server_version': 2},
      );

      final transport = FakeTransport(
        pushHandler: (mutations) => {
          'results': [
            {
              'mutation_id': mutations.single['mutation_id'],
              'status': 'conflict',
              'detail': 'The worker was edited on another device.',
              'record': {
                'id': 'w1',
                'full_name': 'Remote',
                'server_version': 3,
              },
            },
          ],
        },
      );

      final outcome = await SyncService(database: db, transport: transport)
          .sync();

      expect(outcome.conflicts, 1);
      expect(db.conflictCount, 1);
      final record = db.find('worker', 'w1')!;
      expect(record.data['full_name'], 'Local');
      expect(record.serverData!['full_name'], 'Remote');
    });

    test('marks rejected mutations with the server error', () async {
      final db = LocalDatabase.memory();
      db.writeLocal(entity: 'payment', id: 'p1', data: {'amount_ugx': '0'});
      final transport = FakeTransport(
        pushHandler: (mutations) => {
          'results': [
            {
              'mutation_id': mutations.single['mutation_id'],
              'status': 'rejected',
              'errors': {
                'amount_ugx': ['Ensure this value is greater than or equal to 0.01.'],
              },
            },
          ],
        },
      );

      final outcome = await SyncService(database: db, transport: transport)
          .sync();

      expect(outcome.rejected, 1);
      expect(db.rejected, hasLength(1));
      expect(
        db.rejected.single.error,
        contains('amount ugx: Ensure this value'),
      );
    });

    test('does not re-send a mutation after it is applied', () async {
      final db = LocalDatabase.memory();
      db.writeLocal(entity: 'client', id: 'c1', data: {'full_name': 'A'});
      final transport = FakeTransport(
        pushHandler: (mutations) => {
          'results': [
            {
              'mutation_id': mutations.single['mutation_id'],
              'status': 'duplicate',
              'record': {
                'id': 'c1',
                'full_name': 'A',
                'server_version': 1,
                'change_seq': 1,
              },
            },
          ],
        },
      );
      final service = SyncService(database: db, transport: transport);

      final first = await service.sync();
      final second = await service.sync();

      expect(first.applied, 1);
      expect(second.applied, 0);
      expect(transport.pushCalls, 1);
      expect(db.pendingCount, 0);
    });

    test('reports offline errors without losing queued writes', () async {
      final db = LocalDatabase.memory();
      db.writeLocal(entity: 'worker', id: 'w1', data: {'full_name': 'Amina'});
      final transport = FakeTransport(
        pushHandler: (_) => throw ApiException.network(),
      );

      final outcome = await SyncService(database: db, transport: transport)
          .sync();

      expect(outcome.succeeded, isFalse);
      expect(outcome.offline, isTrue);
      expect(outcome.error, contains('Cannot reach the server'));
      expect(db.pendingCount, 1);
    });
  });
}
