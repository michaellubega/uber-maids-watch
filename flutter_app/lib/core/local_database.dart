import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'models.dart';

/// On-device mirror of every record this user is allowed to see, plus the
/// outbox of writes that still need to reach the server.
///
/// The store is deliberately small and dependency-free for the MVP: a single
/// JSON document per user, written atomically.  All access goes through this
/// class, so it can later be swapped for SQLite/Drift without touching the UI.
class LocalDatabase {
  LocalDatabase._(this.userKey, this._file, Map<String, dynamic>? data) {
    _restore(data);
  }

  factory LocalDatabase.memory({
    String userKey = 'memory',
    Map<String, dynamic>? data,
  }) {
    return LocalDatabase._(userKey, null, data);
  }

  static Future<LocalDatabase> open({
    required String userKey,
    required String directory,
  }) async {
    final folder = Directory(p.join(directory, _safeSegment(userKey)));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, 'cache.json'));
    Map<String, dynamic>? data;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // A corrupt cache must never stop the app from starting; the next sync
        // rebuilds it from the server.
      }
    }
    return LocalDatabase._(userKey, file, data);
  }

  final String userKey;
  final File? _file;
  final Map<String, CachedRecord> _records = <String, CachedRecord>{};
  final List<OutboxMutation> _outbox = <OutboxMutation>[];
  int _cursor = 0;
  Future<void> _writeChain = Future<void>.value();

  /// Called after every local change so the UI can rebuild.
  void Function()? onChange;

  int get cursor => _cursor;

  set cursor(int value) {
    if (value == _cursor) return;
    _cursor = value;
    _changed();
  }

  List<CachedRecord> get allRecords => _records.values.toList();

  List<CachedRecord> recordsFor(String entity, {bool includeDeleted = false}) {
    return _records.values
        .where((record) =>
            record.entity == entity && (includeDeleted || !record.deleted))
        .toList();
  }

  CachedRecord? find(String entity, String id) => _records['$entity:$id'];

  List<OutboxMutation> get outbox => List<OutboxMutation>.unmodifiable(_outbox);

  List<OutboxMutation> get pendingMutations =>
      _outbox.where((mutation) => mutation.isPending).toList();

  List<OutboxMutation> get conflicts => _outbox
      .where((mutation) => mutation.status == OutboxStatus.conflict)
      .toList();

  List<OutboxMutation> get rejected => _outbox
      .where((mutation) => mutation.status == OutboxStatus.rejected)
      .toList();

  int get pendingCount => _outbox.where((m) => m.isPending).length;

  int get conflictCount =>
      _outbox.where((m) => m.status == OutboxStatus.conflict).length;

  bool get hasRecordConflicts => _records.values.any((r) => r.hasConflict);

  /// Replace the local mirror with a change coming from the server.
  void applyServerChange({
    required String entity,
    required String id,
    required Map<String, dynamic> data,
    required int changeSeq,
    required bool deleted,
  }) {
    final key = '$entity:$id';
    final existing = _records[key];
    final serverVersion = asInt(data['server_version']);

    if (existing != null && existing.dirty) {
      // Somebody edited this record on another device.  Keep the local value
      // but remember the server copy so the user can resolve the difference.
      if (existing.baseVersion != serverVersion) {
        existing.serverData = Map<String, dynamic>.from(data);
        existing.serverVersion = serverVersion;
      }
      if (changeSeq > existing.changeSeq) existing.changeSeq = changeSeq;
      _changed();
      return;
    }

    _records[key] = CachedRecord(
      entity: entity,
      id: id,
      data: Map<String, dynamic>.from(data),
      changeSeq: changeSeq,
      deleted: deleted,
      dirty: false,
      baseVersion: serverVersion,
      serverVersion: serverVersion,
    );
    _changed();
  }

  /// Store a local edit immediately (so the UI shows it) and queue it.
  CachedRecord writeLocal({
    required String entity,
    required String id,
    required Map<String, dynamic> data,
    bool enqueue = true,
  }) {
    final key = '$entity:$id';
    final existing = _records[key];
    final record = existing ??
        CachedRecord(entity: entity, id: id, data: <String, dynamic>{});

    record.data = Map<String, dynamic>.from(data);
    record.dirty = true;
    record.deleted = false;
    record.baseVersion = existing?.baseVersion ?? 0;
    record.serverData = null;
    record.serverVersion = null;
    _records[key] = record;

    if (enqueue) _enqueue(record);
    _changed();
    return record;
  }

  /// Soft-delete a record locally and queue the tombstone for the server.
  void deleteLocal({required String entity, required String id}) {
    final record = find(entity, id);
    if (record == null) return;
    record.data = {
      ...record.data,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    };
    record.deleted = true;
    record.dirty = true;
    _outbox.removeWhere((mutation) =>
        mutation.entity == entity &&
        mutation.id == id &&
        mutation.status == OutboxStatus.pending);
    _outbox.add(
      OutboxMutation(
        mutationId: _uuid(),
        entity: entity,
        id: id,
        operation: 'delete',
        baseVersion: record.baseVersion,
        data: const <String, dynamic>{},
        createdAt: DateTime.now(),
      ),
    );
    _changed();
  }

  void setCursor(int value) {
    _cursor = value;
    _changed();
  }

  void _enqueue(CachedRecord record) {
    // Coalesce repeated edits of the same record into one queued mutation.
    _outbox.removeWhere((mutation) =>
        mutation.entity == record.entity &&
        mutation.id == record.id &&
        mutation.status == OutboxStatus.pending);

    _outbox.add(
      OutboxMutation(
        mutationId: _uuid(),
        entity: record.entity,
        id: record.id,
        operation: 'upsert',
        baseVersion: record.baseVersion,
        data: payloadForEntity(record.entity, record.data),
        createdAt: DateTime.now(),
      ),
    );
  }

  void markApplied(String mutationId, {Map<String, dynamic>? serverRecord}) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    _outbox.removeWhere((row) => row.mutationId == mutationId);

    if (serverRecord != null) {
      final record = find(mutation.entity, mutation.id);
      if (record != null) {
        record.data = Map<String, dynamic>.from(serverRecord);
        record.baseVersion = asInt(serverRecord['server_version']);
        record.serverVersion = record.baseVersion;
        record.changeSeq = asInt(serverRecord['change_seq']);
        record.deleted = serverRecord['deleted_at'] != null;
        record.serverData = null;
        record.dirty = _outbox.any((row) =>
            row.entity == mutation.entity &&
            row.id == mutation.id &&
            row.isPending);
      }
    }
    _changed();
  }

  void markConflict(
    String mutationId, {
    required Map<String, dynamic>? serverRecord,
    String? message,
  }) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    mutation.status = OutboxStatus.conflict;
    mutation.serverRecord = serverRecord;
    mutation.error = message ?? 'The record changed on another device.';

    final record = find(mutation.entity, mutation.id);
    if (record != null && serverRecord != null) {
      record.serverData = Map<String, dynamic>.from(serverRecord);
      record.serverVersion = asInt(serverRecord['server_version']);
    }
    _changed();
  }

  void markRejected(String mutationId, String error) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    mutation.status = OutboxStatus.rejected;
    mutation.error = error;
    _changed();
  }

  /// Keep the device version and retry against the current server version.
  void resolveKeepMine(String mutationId) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    final record = find(mutation.entity, mutation.id);
    final version = record?.serverVersion ?? mutation.baseVersion;
    mutation.baseVersion = version;
    mutation.status = OutboxStatus.pending;
    mutation.error = null;
    mutation.serverRecord = null;
    if (record != null) {
      record.baseVersion = version;
      record.serverData = null;
      record.serverVersion = null;
    }
    _changed();
  }

  /// Discard the device version and accept the server's copy.
  void resolveUseServer(String mutationId) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    final server = mutation.serverRecord;
    final record = find(mutation.entity, mutation.id);
    if (record != null && server != null) {
      record.data = Map<String, dynamic>.from(server);
      record.baseVersion = asInt(server['server_version']);
      record.serverVersion = record.baseVersion;
      record.deleted = server['deleted_at'] != null;
      record.serverData = null;
    }
    if (record != null) record.dirty = false;
    _outbox.removeWhere((row) =>
        row.entity == mutation.entity && row.id == mutation.id);
    _changed();
  }

  /// Re-queue a rejected mutation (for example after fixing permissions).
  void retryRejected(String mutationId) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    mutation.status = OutboxStatus.pending;
    mutation.error = null;
    _changed();
  }

  void discardMutation(String mutationId) {
    final mutation = _mutation(mutationId);
    if (mutation == null) return;
    _outbox.removeWhere((row) => row.mutationId == mutationId);
    final record = find(mutation.entity, mutation.id);
    if (record != null &&
        !_outbox.any(
            (row) => row.entity == mutation.entity && row.id == mutation.id)) {
      record.dirty = false;
      record.serverData = null;
    }
    _changed();
  }

  void replaceRecordData(
    String entity,
    String id,
    Map<String, dynamic> data, {
    int? baseVersion,
  }) {
    final record = find(entity, id);
    if (record == null) return;
    record.data = Map<String, dynamic>.from(data);
    record.baseVersion = baseVersion ?? asInt(data['server_version']);
    record.serverVersion = record.baseVersion;
    record.dirty = false;
    record.serverData = null;
    record.deleted = data['deleted_at'] != null;
    _changed();
  }

  void removeRecord(String entity, String id) {
    _records.remove('$entity:$id');
    _outbox.removeWhere(
        (row) => row.entity == entity && row.id == id && row.isPending);
    _changed();
  }

  void clearAll() {
    _records.clear();
    _outbox.clear();
    _cursor = 0;
    _changed();
  }

  /// Persist pending changes and wait for the file write to finish.
  Future<void> flush() async {
    await _writeChain;
  }

  OutboxMutation? _mutation(String mutationId) {
    for (final mutation in _outbox) {
      if (mutation.mutationId == mutationId) return mutation;
    }
    return null;
  }

  void _changed() {
    onChange?.call();
    _persistSoon();
  }

  void _persistSoon() {
    if (_file == null) return;
    _writeChain = _writeChain.then((_) => _writeSnapshot()).catchError((_) {});
  }

  Future<void> _writeSnapshot() async {
    final file = _file;
    if (file == null) return;
    final encoded = jsonEncode({
      'schema': 1,
      'user_key': userKey,
      'cursor': _cursor,
      'records': _records.map((key, value) => MapEntry(key, value.toJson())),
      'outbox': _outbox.map((mutation) => mutation.toJson()).toList(),
    });
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    try {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      // Antivirus / OneDrive can briefly lock the file.  Fall back to a direct
      // write so the local cache is never lost.
      await file.writeAsString(encoded, flush: true);
    }
  }

  void _restore(Map<String, dynamic>? data) {
    if (data == null) return;
    _cursor = asInt(data['cursor']);
    final records = data['records'];
    if (records is Map) {
      records.forEach((key, value) {
        if (value is Map) {
          final record = CachedRecord.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (record.entity.isNotEmpty && record.id.isNotEmpty) {
            _records[key.toString()] = record;
          }
        }
      });
    }
    final outbox = data['outbox'];
    if (outbox is List) {
      for (final row in outbox) {
        if (row is Map) {
          _outbox.add(
            OutboxMutation.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
  }

  static String _safeSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned.isEmpty ? 'user' : cleaned;
  }

  static const Uuid _uuidGenerator = Uuid();

  static String _uuid() => _uuidGenerator.v4();
}
