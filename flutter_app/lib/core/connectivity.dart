import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network reachability.  This is a hint only: the API call remains the source
/// of truth, because "connected to Wi-Fi" does not mean "server reachable".
abstract class ConnectivityMonitor {
  Future<bool> check();
  Stream<bool> get changes;
  void dispose();
}

class PlatformConnectivity implements ConnectivityMonitor {
  PlatformConnectivity([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  bool _online(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  Future<bool> check() async => _online(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes =>
      _connectivity.onConnectivityChanged.map(_online).distinct();

  @override
  void dispose() {}
}

/// Used by tests and by the Windows desktop build when the platform reports no
/// adapter information: assume the API call will tell us the truth.
class AlwaysOnlineConnectivity implements ConnectivityMonitor {
  @override
  Future<bool> check() async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  void dispose() {}
}
