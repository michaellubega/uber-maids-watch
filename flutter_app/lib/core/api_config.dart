import 'package:flutter/foundation.dart';

/// Default API location.
///
/// The Windows desktop build talks to a local Django server; the Android
/// emulator reaches the host machine through 10.0.2.2.  Users can override the
/// address from the login screen (it is remembered on the device).
class ApiConfig {
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static const Duration requestTimeout = Duration(seconds: 25);
}
