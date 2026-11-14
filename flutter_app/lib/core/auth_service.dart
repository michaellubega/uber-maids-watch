import 'api_client.dart';
import 'models.dart';
import 'session_store.dart';

class AuthResult {
  const AuthResult({
    required this.session,
    required this.offline,
    this.message,
  });

  final Session session;
  final bool offline;
  final String? message;
}

/// Login, token refresh and offline session fallback.
class AuthService {
  AuthService({
    required this.api,
    required this.sessionStore,
  });

  final ApiClient api;
  final SessionStore sessionStore;

  Session? session;

  String get baseUrl => api.baseUrl;

  void setBaseUrl(String value) {
    api.baseUrl = value;
  }

  Future<AuthResult> signIn(String username, String password) async {
    final trimmed = username.trim();
    try {
      final token = await api.post(
        '/auth/token/',
        body: {'username': trimmed, 'password': password},
        authenticated: false,
      );
      final access = '${token['access'] ?? ''}';
      final refresh = '${token['refresh'] ?? ''}';
      if (access.isEmpty || refresh.isEmpty) {
        throw ApiException(message: 'The server did not return a session.');
      }

      session = Session(
        user: AppUser(
          id: '',
          username: trimmed,
          displayName: trimmed,
          role: 'READONLY',
        ),
        accessToken: access,
        refreshToken: refresh,
        savedAt: DateTime.now(),
      );

      final me = await api.get('/auth/me/');
      final userJson = me['user'] is Map
          ? Map<String, dynamic>.from(me['user'] as Map)
          : <String, dynamic>{};
      final capabilities = me['capabilities'] is Map
          ? Map<String, dynamic>.from(me['capabilities'] as Map)
          : <String, dynamic>{};

      session = session!.copyWith(
        user: AppUser.fromJson(userJson, capabilities: capabilities),
        savedAt: DateTime.now(),
      );
      await sessionStore.saveSession(session!);
      return AuthResult(session: session!, offline: false);
    } on ApiException catch (error) {
      if (!error.isNetwork) rethrow;
      final cached = await sessionStore.readSession();
      if (cached != null &&
          cached.user.username.toLowerCase() == trimmed.toLowerCase()) {
        session = cached;
        return AuthResult(
          session: cached,
          offline: true,
          message:
              'No connection. Signed in with the offline copy stored on this device.',
        );
      }
      throw ApiException.network(
        'No connection, and there is no offline session for "$trimmed" on this '
        'device. Sign in once while online to enable offline access.',
      );
    }
  }

  /// Load a previous session without contacting the server.
  Future<Session?> restore() async {
    session = await sessionStore.readSession();
    return session;
  }

  Future<Map<String, dynamic>> loadMe() async {
    final me = await api.get('/auth/me/');
    final current = session;
    if (current != null) {
      final userJson = me['user'] is Map
          ? Map<String, dynamic>.from(me['user'] as Map)
          : <String, dynamic>{};
      final capabilities = me['capabilities'] is Map
          ? Map<String, dynamic>.from(me['capabilities'] as Map)
          : <String, dynamic>{};
      session = current.copyWith(
        user: AppUser.fromJson(userJson, capabilities: capabilities),
        savedAt: DateTime.now(),
      );
      await sessionStore.saveSession(session!);
    }
    return me;
  }

  /// Refresh callback used by [ApiClient].  Returns null while offline; the
  /// caller then decides whether to fall back to cached data.
  Future<String?> refreshAccess() async {
    final current = session;
    if (current == null || current.refreshToken.isEmpty) return null;
    try {
      final response = await api.post(
        '/auth/token/refresh/',
        body: {'refresh': current.refreshToken},
        authenticated: false,
      );
      final access = '${response['access'] ?? ''}';
      if (access.isEmpty) return null;
      final refresh = '${response['refresh'] ?? current.refreshToken}';
      session = current.copyWith(
        accessToken: access,
        refreshToken: refresh,
        savedAt: DateTime.now(),
      );
      await sessionStore.saveSession(session!);
      return access;
    } on ApiException catch (error) {
      if (error.isNetwork) return null;
      // The refresh token is no longer valid: end the session cleanly.
      session = null;
      await sessionStore.clearSession();
      return null;
    }
  }

  Future<void> signOut() async {
    session = null;
    await sessionStore.clearSession();
  }
}
