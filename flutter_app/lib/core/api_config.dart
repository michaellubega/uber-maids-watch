/// Default API location.
///
/// The app defaults to the hosted Render service so a phone can sign in
/// without any extra configuration.  Developers can point it elsewhere with
/// `--dart-define=UMW_API_URL=http://127.0.0.1:8000/api` (or the LAN address of
/// a local server).  The login screen also lets the user change it and the
/// choice is remembered on the device.
class ApiConfig {
  static const String renderBaseUrl =
      'https://uber-maids-watch.onrender.com/api';

  static String get defaultBaseUrl {
    const override = String.fromEnvironment('UMW_API_URL');
    if (override.trim().isNotEmpty) return override.trim();
    return renderBaseUrl;
  }

  static bool get isHostedDefault =>
      const String.fromEnvironment('UMW_API_URL').trim().isEmpty;

  /// Render's free service sleeps after inactivity; the first request can take
  /// up to a minute, so the timeout is deliberately generous.
  static const Duration requestTimeout = Duration(seconds: 75);
}
