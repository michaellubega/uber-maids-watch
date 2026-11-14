import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Key/value storage for the session.  Tests inject an in-memory version.
abstract class SessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySessionStorage implements SessionStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class SessionStore {
  SessionStore(this._storage);

  final SessionStorage _storage;

  static const _sessionKey = 'umw.session';
  static const _baseUrlKey = 'umw.base_url';

  Future<Session?> readSession() async {
    final raw = await _storage.read(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    return Session.decode(raw);
  }

  Future<void> saveSession(Session session) =>
      _storage.write(_sessionKey, session.encode());

  Future<void> clearSession() => _storage.delete(_sessionKey);

  Future<String?> readBaseUrl() => _storage.read(_baseUrlKey);

  Future<void> saveBaseUrl(String value) =>
      _storage.write(_baseUrlKey, value);
}
