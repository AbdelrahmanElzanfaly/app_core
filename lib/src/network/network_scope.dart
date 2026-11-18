import 'package:flutter/widgets.dart';

import 'network_monitor.dart';
import 'network_reachability.dart';

/// Puts the app's NetworkMonitor in the tree; widgets below rebuild when
/// reachability, or whether the service is available, changes.
class NetworkScope extends InheritedNotifier<NetworkMonitor> {
  const NetworkScope({
    super.key,
    required NetworkMonitor monitor,
    required super.child,
  }) : super(notifier: monitor);

  /// Online when there is no scope (tests, previews): never offline on a guess.
  static NetworkReachability reachabilityOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NetworkScope>()
          ?.notifier
          ?.reachability ??
      NetworkReachability.online;

  /// Whether the server's last answer was a 5xx. False when there is no
  /// scope (tests, previews).
  static bool isServiceUnavailableOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NetworkScope>()
          ?.notifier
          ?.isServiceUnavailable ??
      false;

  /// No rebuild dependency: for widgets that subscribe themselves, or that
  /// call [NetworkMonitor.retry].
  static NetworkMonitor? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NetworkScope>()?.notifier;
}
