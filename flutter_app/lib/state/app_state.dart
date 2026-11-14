import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/api_config.dart';
import '../core/auth_service.dart';
import '../core/connectivity.dart';
import '../core/local_database.dart';
import '../core/models.dart';
import '../core/permissions.dart';
import '../core/session_store.dart';
import '../core/sync_service.dart';

/// Application state: session, cached records, outbox and sync status.
class AppState extends ChangeNotifier {
  AppState({
    SessionStore? sessionStore,
    ConnectivityMonitor? connectivity,
  })  : sessionStore = sessionStore ?? SessionStore(SecureSessionStorage()),
        _connectivity = connectivity ?? PlatformConnectivity() {
    api = ApiClient(baseUrl: ApiConfig.defaultBaseUrl);
    auth = AuthService(api: api, sessionStore: this.sessionStore);
    api.accessToken = () => auth.session?.accessToken;
    api.onRefresh = auth.refreshAccess;
  }

  final SessionStore sessionStore;
  final ConnectivityMonitor _connectivity;

  late final ApiClient api;
  late final AuthService auth;

  LocalDatabase? _db;
  SyncService? _sync;
  StreamSubscription<bool>? _connectivityWatch;
  Timer? _timer;

  bool _restoring = true;
  bool _busy = false;
  bool _syncing = false;
  bool _online = true;
  bool _offlineMode = false;
  String? _error;
  String? _notice;
  DateTime? _lastSyncAt;
  String? _lastSyncError;

  AppUser? get user => auth.session?.user;
  LocalDatabase? get database => _db;
  bool get restoring => _restoring;
  bool get busy => _busy;
  bool get syncing => _syncing;
  bool get online => _online;
  bool get offlineMode => _offlineMode;
  bool get signedIn => user != null && _db != null;
  bool get canReachServer => user != null && _online && !_offlineMode;
  String? get error => _error;
  String? get notice => _notice;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastSyncError => _lastSyncError;
  String get baseUrl => auth.baseUrl;

  int get pendingCount => _db?.pendingCount ?? 0;

  int get conflictCount {
    final db = _db;
    if (db == null) return 0;
    final records = db.allRecords.where((record) => record.hasConflict).length;
    return db.conflictCount + records;
  }

  List<OutboxMutation> get conflicts => _db?.conflicts ?? const [];
  List<OutboxMutation> get rejectedMutations => _db?.rejected ?? const [];

  static const List<String> pendingBusinessRules = [
    'Free-replacement guarantee length and the exact start/end rule',
    'Pricing and package amounts for every service',
    'Which incidents qualify for a free replacement or are chargeable',
    'Refund, cancellation and transfer rules',
    'Worker training curriculum and pass criteria',
  ];

  Future<void> init() async {
    _restoring = true;
    notifyListeners();
    try {
      final savedUrl = await sessionStore.readBaseUrl();
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        auth.setBaseUrl(savedUrl.trim());
      }
      try {
        _online = await _connectivity.check();
      } catch (_) {
        _online = true;
      }
      final session = await auth.restore();
      if (session != null) await _openDatabase(session.user.id);
      _listenForConnectivity();
      _timer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (auth.session != null && _online) {
          unawaited(syncNow(silent: true));
        }
      });
      if (session != null) await _verifySessionAndSync();
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  void _listenForConnectivity() {
    _connectivityWatch = _connectivity.changes.listen((online) {
      _online = online;
      notifyListeners();
      if (online && auth.session != null) {
        unawaited(syncNow(silent: true));
      }
    });
  }

  Future<void> _verifySessionAndSync() async {
    if (auth.session == null) return;
    try {
      await auth.loadMe();
      _offlineMode = false;
      _error = null;
      notifyListeners();
      await syncNow(silent: true);
    } on ApiException catch (error) {
      if (auth.session == null) {
        await _expireSession();
        return;
      }
      if (error.isNetwork) {
        _offlineMode = true;
        _lastSyncError = 'Offline — showing the data stored on this device.';
      } else if (error.isUnauthorised) {
        await _expireSession();
        return;
      } else {
        _lastSyncError = error.message;
      }
      notifyListeners();
    }
  }

  Future<void> _openDatabase(String userKey) async {
    _db?.onChange = null;
    try {
      final directory = await getApplicationSupportDirectory();
      _db = await LocalDatabase.open(
        userKey: userKey,
        directory: directory.path,
      );
    } catch (_) {
      _db = LocalDatabase.memory(userKey: userKey);
      _notice =
          'The on-device cache could not be opened; this session is temporary.';
    }
    _sync = SyncService(database: _db!, transport: ApiSyncTransport(api));
    _db!.onChange = notifyListeners;
  }

  Future<bool> signIn({
    required String username,
    required String password,
  }) async {
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final result = await auth.signIn(username, password);
      _offlineMode = result.offline;
      _notice = result.message;
      await _openDatabase(result.session.user.id);
      if (!result.offline) {
        _online = true;
        unawaited(syncNow(silent: true));
      }
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (error) {
      _error = 'Could not sign in: $error';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await auth.signOut();
    _db?.onChange = null;
    _db = null;
    _sync = null;
    _offlineMode = false;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  /// Remove this device's cached records and session (used on shared devices).
  Future<void> forgetDevice() async {
    _db?.clearAll();
    await _db?.flush();
    await signOut();
  }

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    auth.setBaseUrl(trimmed);
    await sessionStore.saveBaseUrl(trimmed);
    notifyListeners();
  }

  void dismissNotice() {
    _notice = null;
    _error = null;
    notifyListeners();
  }

  Future<SyncOutcome?> syncNow({bool silent = false}) async {
    final service = _sync;
    if (service == null || auth.session == null) return null;
    if (_syncing) return null;
    _syncing = true;
    if (!silent) _lastSyncError = null;
    notifyListeners();
    try {
      final outcome = await service.sync();
      if (outcome.succeeded) {
        _lastSyncAt = DateTime.now();
        _lastSyncError = null;
        _offlineMode = false;
        _online = true;
      } else {
        _lastSyncError = outcome.error;
        if (outcome.offline) _offlineMode = true;
      }
      await _db?.flush();
      return outcome;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> rows(String entity) {
    final db = _db;
    if (db == null) return const <Map<String, dynamic>>[];
    return db
        .recordsFor(entity)
        .map((record) => record.data)
        .toList(growable: false);
  }

  Map<String, dynamic>? row(String entity, String id) =>
      _db?.find(entity, id)?.data;

  int count(
    String entity, {
    bool Function(Map<String, dynamic> row)? where,
  }) {
    final rows = this.rows(entity);
    if (where == null) return rows.length;
    return rows.where(where).length;
  }

  Map<String, dynamic>? get myClient {
    final current = user;
    if (current == null || current.role != 'FAMILY') return null;
    final clients = rows('client');
    for (final client in clients) {
      if ('${client['user']}' == current.id) return client;
    }
    return clients.length == 1 ? clients.first : null;
  }

  Map<String, dynamic>? get myWorker {
    final current = user;
    if (current == null || current.role != 'MAID') return null;
    final workers = rows('worker');
    for (final worker in workers) {
      if ('${worker['user']}' == current.id) return worker;
    }
    return workers.length == 1 ? workers.first : null;
  }

  Future<CachedRecord?> createRecord(
    String entity,
    Map<String, dynamic> data,
  ) async {
    final db = _db;
    if (db == null) return null;
    final record = db.writeLocal(
      entity: entity,
      id: const Uuid().v4(),
      data: data,
    );
    notifyListeners();
    unawaited(syncNow(silent: true));
    return record;
  }

  Future<CachedRecord?> updateRecord(
    String entity,
    String id,
    Map<String, dynamic> changes,
  ) async {
    final db = _db;
    if (db == null) return null;
    final existing = db.find(entity, id);
    if (existing == null) return null;
    final merged = <String, dynamic>{...existing.data, ...changes};
    final record = db.writeLocal(entity: entity, id: id, data: merged);
    notifyListeners();
    unawaited(syncNow(silent: true));
    return record;
  }

  Future<void> deleteRecord(String entity, String id) async {
    _db?.deleteLocal(entity: entity, id: id);
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  /// Call a workflow endpoint (verify, confirm, complete, review, assign).
  /// These are administrator actions and therefore require the server.
  Future<Map<String, dynamic>?> action({
    required String method,
    required String path,
    String? entity,
    Object? body,
  }) async {
    if (!_online || _offlineMode) {
      throw ApiException.network(
        'This action needs a connection to the office server.',
      );
    }
    try {
      final response = method == 'PATCH'
          ? await api.patch(path, body: body)
          : await api.post(path, body: body);
      if (entity != null && response['id'] != null) {
        _db?.replaceRecordData(entity, '${response['id']}', response);
        await _db?.flush();
      }
      notifyListeners();
      return response;
    } on ApiException catch (error) {
      if (error.isUnauthorised) {
        await _expireSession();
      } else if (error.isNetwork) {
        _offlineMode = true;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _expireSession() async {
    await auth.signOut();
    _db?.onChange = null;
    _db = null;
    _sync = null;
    _offlineMode = false;
    _notice = 'Your session expired. Please sign in again.';
    notifyListeners();
  }

  Future<void> clearCachedData() async {
    _db?.clearAll();
    await _db?.flush();
    notifyListeners();
    if (_online && !_offlineMode) await syncNow();
  }

  Future<void> resolveUseServer(String mutationId) async {
    _db?.resolveUseServer(mutationId);
    await _db?.flush();
    notifyListeners();
    unawaited(syncNow(silent: true));
  }

  Future<void> resolveKeepMine(String mutationId) async {
    _db?.resolveKeepMine(mutationId);
    await _db?.flush();
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> retryMutation(String mutationId) async {
    _db?.retryRejected(mutationId);
    notifyListeners();
    unawaited(syncNow());
  }

  Future<void> discardMutation(String mutationId) async {
    _db?.discardMutation(mutationId);
    notifyListeners();
  }

  bool canWrite(String entity) => Permissions.canWrite(user, entity);

  bool canDelete(String entity) => Permissions.canDelete(user, entity);

  @override
  void dispose() {
    _timer?.cancel();
    _connectivityWatch?.cancel();
    _db?.onChange = null;
    _connectivity.dispose();
    api.close();
    super.dispose();
  }
}
