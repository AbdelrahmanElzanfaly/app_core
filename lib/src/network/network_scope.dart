import 'package:flutter/widgets.dart';

import 'network_monitor.dart';
import 'network_reachability.dart';

/// Puts the app's NetworkMonitor in the tree; widgets below rebuild when
/// reachability changes.
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

  /// No rebuild dependency: for widgets that subscribe themselves.
  static NetworkMonitor? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NetworkScope>()?.notifier;
}
