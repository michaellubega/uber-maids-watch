import 'api_client.dart';
import 'local_database.dart';
import 'models.dart';

/// The two server calls the sync engine needs.  Abstracted so tests can run
/// the full push/pull/conflict logic without a network.
abstract class SyncTransport {
  Future<Map<String, dynamic>> pull({required int since, required int limit});

  Future<Map<String, dynamic>> push({
    required List<Map<String, dynamic>> mutations,
  });
}

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this.api);

  final ApiClient api;

  @override
  Future<Map<String, dynamic>> pull({
    required int since,
    required int limit,
  }) {
    return api.get('/sync/pull/', query: {
      'since': '$since',
      'limit': '$limit',
    });
  }

  @override
  Future<Map<String, dynamic>> push({
    required List<Map<String, dynamic>> mutations,
  }) {
    return api.post('/sync/push/', body: {'mutations': mutations});
  }
}

class SyncOutcome {
  const SyncOutcome({
    this.pulled = 0,
    this.applied = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.error,
    this.offline = false,
  });

  final int pulled;
  final int applied;
  final int conflicts;
  final int rejected;
  final String? error;
  final bool offline;

  bool get succeeded => error == null;

  String get summary {
    if (error != null) return error!;
    return 'Downloaded $pulled change${pulled == 1 ? '' : 's'} · '
        'uploaded $applied · $conflicts conflict${conflicts == 1 ? '' : 's'}';
  }
}

/// Pushes queued writes, then downloads every change since the last cursor.
///
/// The engine is intentionally sequential and idempotent: a mutation carries a
/// UUID, so retrying after a dropped connection cannot duplicate data.  When
/// the server reports a conflict the local copy is kept and surfaced to the
/// user rather than silently overwritten.
class SyncService {
  SyncService({
    required this.database,
    required this.transport,
  });

  final LocalDatabase database;
  final SyncTransport transport;

  Future<SyncOutcome>? _active;

  Future<SyncOutcome> sync() {
    final running = _active;
    if (running != null) return running;
    final future = _run();
    _active = future;
    return future.whenComplete(() => _active = null);
  }

  Future<SyncOutcome> _run() async {
    var applied = 0;
    var conflicts = 0;
    var rejected = 0;
    var pulled = 0;

    try {
      // 1. Upload local writes first so the pull includes their server state.
      for (var round = 0; round < 10; round++) {
        final pending = database.pendingMutations;
        if (pending.isEmpty) break;
        final batch = pending.take(100).toList();
        final before = database.pendingCount;
        final response = await transport.push(
          mutations: batch.map((mutation) => mutation.toPayload()).toList(),
        );
        final results = response['results'];
        if (results is! List || results.isEmpty) break;

        for (final raw in results) {
          if (raw is! Map) continue;
          final result = Map<String, dynamic>.from(raw);
          final mutationId = '${result['mutation_id'] ?? ''}';
          if (mutationId.isEmpty) continue;
          final record = _mapOrNull(result['record']);
          switch ('${result['status']}') {
            case 'applied':
            case 'duplicate':
              applied++;
              database.markApplied(mutationId, serverRecord: record);
              break;
            case 'conflict':
              conflicts++;
              database.markConflict(
                mutationId,
                serverRecord: record,
                message: '${result['detail'] ?? 'Changed on the server.'}',
              );
              break;
            case 'rejected':
              rejected++;
              database.markRejected(
                mutationId,
                _errorText(result['errors']) ??
                    'The server rejected this change.',
              );
              break;
            default:
              break;
          }
        }

        // Defensive: stop if the server answered but nothing moved.
        if (database.pendingCount >= before) break;
      }

      // 2. Download changes page by page.
      var since = database.cursor;
      for (var page = 0; page < 60; page++) {
        final response =
            await transport.pull(since: since, limit: 500);
        final changes = response['changes'];
        if (changes is List) {
          for (final raw in changes) {
            if (raw is! Map) continue;
            final change = Map<String, dynamic>.from(raw);
            final entity = '${change['entity'] ?? ''}';
            final id = '${change['id'] ?? ''}';
            final data = _mapOrNull(change['data']);
            if (entity.isEmpty || id.isEmpty || data == null) continue;
            database.applyServerChange(
              entity: entity,
              id: id,
              data: data,
              changeSeq: asInt(change['change_seq']),
              deleted: change['deleted'] == true,
            );
            pulled++;
          }
        }
        final next = asInt(response['next_since']);
        if (next > since) {
          since = next;
          database.setCursor(next);
        }
        if (response['has_more'] != true) break;
      }

      return SyncOutcome(
        pulled: pulled,
        applied: applied,
        conflicts: conflicts,
        rejected: rejected,
      );
    } on ApiException catch (error) {
      return SyncOutcome(
        pulled: pulled,
        applied: applied,
        conflicts: conflicts,
        rejected: rejected,
        error: error.message,
        offline: error.isNetwork,
      );
    } catch (error) {
      return SyncOutcome(
        pulled: pulled,
        applied: applied,
        conflicts: conflicts,
        rejected: rejected,
        error: 'Sync failed: $error',
      );
    }
  }

  static Map<String, dynamic>? _mapOrNull(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _errorText(Object? errors) {
    if (errors == null) return null;
    if (errors is String) return errors;
    if (errors is List) {
      return errors.map((row) => '$row').join(' ');
    }
    if (errors is Map) {
      for (final entry in errors.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          final label = '${entry.key}'.replaceAll('_', ' ');
          return '$label: ${value.first}';
        }
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return '$errors';
  }
}
