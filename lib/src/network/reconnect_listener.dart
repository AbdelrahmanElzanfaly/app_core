import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'network_monitor.dart';
import 'network_reachability.dart';
import 'network_scope.dart';

/// Calls [onReconnect] when the network comes back — for a screen showing a
/// failure or a saved copy, the retry the user would do by hand.
///
/// A reconnect that arrives while [busy] (a load is running) is remembered
/// and fired once when that load ends, if the screen is then still
/// [enabled]; otherwise a reconnect during a slow load that then fails would
/// be lost. One announced by a request getting through may be that load's
/// own answer (a 503, say): it is fired only if the load then failed on the
/// transport, which leaves the monitor no longer online. No visuals: returns
/// [child]. Does nothing without a NetworkScope.
class ReconnectListener extends StatefulWidget {
  const ReconnectListener({
    super.key,
    required this.enabled,
    required this.onReconnect,
    required this.child,
    this.busy,
  });

  /// Whether the screen has anything to recover: a failure or a saved copy.
  final bool enabled;

  /// The screen's own reload; never called while [busy].
  final VoidCallback onReconnect;

  /// True while a load is running, such as `BaseBloc.loading`.
  final ValueListenable<bool>? busy;

  final Widget child;

  @override
  State<ReconnectListener> createState() => _ReconnectListenerState();
}

class _ReconnectListenerState extends State<ReconnectListener> {
  NetworkMonitor? _monitor;
  StreamSubscription<void>? _reconnects;

  /// A reconnect arrived while busy; fired once the load has ended.
  bool _missed = false;

  /// Every reconnect missed was a request getting through, which may have
  /// been the running load itself.
  bool _missedByRequestOnly = false;

  bool get _busy => widget.busy?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.busy?.addListener(_onBusyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(ReconnectListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy) {
      oldWidget.busy?.removeListener(_onBusyChanged);
      widget.busy?.addListener(_onBusyChanged);
      _onBusyChanged();
    }
    // The scope gives no rebuild dependency, so a swapped monitor is picked
    // up whenever the page rebuilds.
    _subscribe();
  }

  /// Re-subscribes only when the monitor instance changed.
  void _subscribe() {
    final monitor = NetworkScope.maybeOf(context);
    if (identical(monitor, _monitor)) return;
    unawaited(_reconnects?.cancel());
    _monitor = monitor;
    _reconnects = monitor?.reconnected.listen((_) => _onReconnected());
  }

  void _onReconnected() {
    if (!mounted) return;
    if (_busy) {
      final byRequest = _monitor?.reconnectedByRequest ?? false;
      _missedByRequestOnly = byRequest && (_missedByRequestOnly || !_missed);
      _missed = true;
    } else if (widget.enabled) {
      widget.onReconnect();
    }
  }

  void _onBusyChanged() {
    if (_busy || !_missed) return;
    // After the frame: the page has rebuilt with the load's outcome, so
    // [ReconnectListener.enabled] says whether there is still anything to
    // recover.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || !_missed || _busy) return;
        // Cleared before firing: a reload that fails again waits for the
        // next reconnect instead of looping.
        _missed = false;
        // The load has reported its own outcome. Still online after only a
        // request got through: that request may have been this load, which
        // then already ran against the recovered server, so a reload would
        // only repeat it.
        if (_missedByRequestOnly &&
            _monitor?.reachability == NetworkReachability.online) {
          return;
        }
        if (widget.enabled) widget.onReconnect();
      })
      ..scheduleFrame();
  }

  @override
  void dispose() {
    widget.busy?.removeListener(_onBusyChanged);
    unawaited(_reconnects?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
