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
///
/// The remembered reconnect belongs to [busy], not to this widget: a layout
/// switch (mobile ↔ tablet) replaces the listener in the middle of a load,
/// and the page's next listener on the same bloc fires it instead. Listeners
/// sharing one [busy] fire it once between them.
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

/// A reconnect that arrived while a load was running, waiting for it to end.
class _Missed {
  _Missed({required this.byRequestOnly});

  /// Every reconnect missed was a request getting through, which may have
  /// been the running load itself.
  bool byRequestOnly;
}

class _ReconnectListenerState extends State<ReconnectListener> {
  /// Kept on the busy signal (the bloc's `loading`), which outlives a
  /// listener replaced by a layout switch. Weak: gone with the bloc.
  static final Expando<_Missed> _missedByBusy = Expando(
    'ReconnectListener.missed',
  );

  NetworkMonitor? _monitor;
  StreamSubscription<void>? _reconnects;

  bool get _busy => widget.busy?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.busy?.addListener(_onBusyChanged);
    // Takes over a reconnect missed by the listener this one replaces, if
    // that load has already ended.
    _onBusyChanged();
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
    final busy = widget.busy;
    if (busy != null && busy.value) {
      final byRequest = _monitor?.reconnectedByRequest ?? false;
      final missed = _missedByBusy[busy];
      if (missed == null) {
        _missedByBusy[busy] = _Missed(byRequestOnly: byRequest);
      } else {
        missed.byRequestOnly = missed.byRequestOnly && byRequest;
      }
    } else if (widget.enabled) {
      widget.onReconnect();
    }
  }

  void _onBusyChanged() {
    final busy = widget.busy;
    if (busy == null || busy.value || _missedByBusy[busy] == null) return;
    // After the frame: the page has rebuilt with the load's outcome, so
    // [ReconnectListener.enabled] says whether there is still anything to
    // recover.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        // Unmounted: left for the page's next listener on this signal.
        if (!mounted || _busy || !identical(widget.busy, busy)) return;
        final missed = _missedByBusy[busy];
        if (missed == null) return;
        // Cleared before firing: a reload that fails again waits for the
        // next reconnect instead of looping, and a second listener on the
        // same signal finds nothing left to fire.
        _missedByBusy[busy] = null;
        // The load has reported its own outcome. Still online after only a
        // request got through: that request may have been this load, which
        // then already ran against the recovered server, so a reload would
        // only repeat it.
        if (missed.byRequestOnly &&
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
