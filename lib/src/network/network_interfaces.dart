import 'package:connectivity_plus/connectivity_plus.dart';

/// The OS interface list, behind a seam so the monitor is testable without
/// a platform channel.
///
/// "Up" means some interface is connected, which is not proof of internet
/// access: the monitor treats it as a hint and lets real requests decide.
abstract interface class NetworkInterfaces {
  /// Whether any interface is connected right now.
  Future<bool> isUp();

  /// The same answer, each time the interface list changes.
  Stream<bool> get changes;
}

/// [NetworkInterfaces] over connectivity_plus.
class ConnectivityPlusInterfaces implements NetworkInterfaces {
  ConnectivityPlusInterfaces([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// connectivity_plus 7.x reports a list in which `none` only ever appears
  /// alone. Empty or anything other than `none` counts as up (fail-open): a
  /// wrong "down" fails real requests, a wrong "up" costs one attempt.
  static bool _up(List<ConnectivityResult> results) =>
      results.isEmpty || results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isUp() async => _up(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(_up);
}
