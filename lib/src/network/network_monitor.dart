import 'dart:async';

import 'package:app_network/app_network.dart';
import 'package:flutter/widgets.dart';

import 'network_interfaces.dart';
import 'network_reachability.dart';

/// What the app believes about reaching its servers, from two witnesses:
/// the OS interface list and the outcome of real requests. Real traffic
/// beats the OS. Starts online: nothing is reported offline on a guess.
///
/// The NetworkStatus and ReachabilityObserver behind every client, the same
/// way SessionService is the TokenStore and SessionRefresher.
class NetworkMonitor extends ChangeNotifier
    implements NetworkStatus, ReachabilityObserver {
  NetworkMonitor(
    this._interfaces, {
    this.offlineGrace = const Duration(seconds: 2),
    this.reconnectSettle = const Duration(seconds: 1),
    this.reconnectCooldown = const Duration(seconds: 3),
    this.checkTimeout = const Duration(milliseconds: 500),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NetworkInterfaces _interfaces;

  /// How long the OS must keep reporting no network before [reachability]
  /// says offline, so a Wi-Fi to cellular handover never flashes the banner.
  final Duration offlineGrace;

  /// How long a returning interface must stay up before it counts, so a
  /// flapping link does not announce a reconnect for every flap.
  final Duration reconnectSettle;

  /// The shortest gap between two [reconnected] events, so one recovery
  /// seen by several witnesses reloads a screen once.
  final Duration reconnectCooldown;

  /// The longest a platform reading may take; no answer by then counts as
  /// "has network".
  final Duration checkTimeout;

  final DateTime Function() _clock;
  final StreamController<void> _reconnected = StreamController.broadcast();

  NetworkReachability _reachability = NetworkReachability.online;

  /// The raw OS reading that feeds the gate; [reachability] is what is shown.
  bool _interfaceUp = true;

  /// The gate refused a request while the interface read down. Within the
  /// grace [reachability] still says online, so the next recovery must
  /// announce anyway: that request's screen is waiting for a reconnect.
  bool _refused = false;

  /// The app left the foreground (hidden or further) since the last resume.
  bool _backgrounded = false;

  bool _byRequest = false;
  Timer? _offlineTimer;
  Timer? _settleTimer;
  DateTime? _lastAnnounced;
  StreamSubscription<bool>? _changes;
  AppLifecycleListener? _lifecycle;
  Future<void>? _started;
  Future<bool?>? _reading;
  bool _disposed = false;

  NetworkReachability get reachability => _reachability;

  /// Worth trying again: a network appeared (or came back from a short drop
  /// during which a request was refused), the app returned from the
  /// background while not online, or a request got through after a failure.
  /// At most once per [reconnectCooldown]. Broadcast.
  Stream<void> get reconnected => _reconnected.stream;

  /// Whether the last [reconnected] came from a request getting through
  /// ([onReachable]) rather than the network or the app coming back. That
  /// request may be the very load a screen was waiting on.
  bool get reconnectedByRequest => _byRequest;

  /// Idempotent. Reads the interface once (bounded by [checkTimeout]; an
  /// error or timeout leaves it online), subscribes to changes, and listens
  /// for returns from the background. Run once in main(), before runApp.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    final up = await _read();
    if (_disposed) return;
    if (up == false) {
      // Right on the first frame: no grace, and nothing to announce.
      _interfaceUp = false;
      _setReachability(NetworkReachability.offline);
    }
    try {
      _changes = _interfaces.changes.listen(
        _onInterfaceChanged,
        onError: (Object error) => debugPrint('[NetworkMonitor] $error'),
      );
    } catch (error) {
      // No plugin (a test, an unsupported platform): stays online.
      debugPrint('[NetworkMonitor] no interface changes: $error');
    }
    // Android does not deliver changes while the app is in the background, so
    // a return from it reads again. A focus-only interruption (Control
    // Center, the notification shade, a system sheet) goes inactive and back
    // without leaving the foreground, and is not a return. Started in the
    // background (or before the first frame): the first resume is one.
    _backgrounded = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.resumed || AppLifecycleState.inactive => false,
      _ => true,
    };
    _lifecycle = AppLifecycleListener(
      onHide: () => _backgrounded = true,
      onResume: () {
        if (!_backgrounded) return;
        _backgrounded = false;
        unawaited(recheck());
      },
    );
  }

  /// What a return from the background does; public for tests.
  @visibleForTesting
  Future<void> recheck() async {
    final up = await _read();
    if (_disposed || up == null) return;
    if (!up) {
      _onInterfaceChanged(false);
      return;
    }
    // Optimistic: if the reload fails, the state simply flips back.
    _interfaceUp = true;
    _cancelTimers();
    _recover();
  }

  /// True at once while the interface is up. Otherwise reads the platform
  /// again (a stale "none" must not refuse requests), applies the answer and
  /// returns it. Never throws; an error or a slow answer means true.
  @override
  Future<bool> hasNetwork() async {
    if (_interfaceUp || _disposed) return true;
    final up = await _read();
    if (up == null) return true;
    _onInterfaceChanged(up);
    // The gate is about to fail a real request.
    if (!up) _refused = true;
    return up;
  }

  @override
  void onReachable() {
    if (_disposed) return;
    // The evidence is definitive: it corrects a stale "none" and needs no
    // settle.
    _interfaceUp = true;
    _cancelTimers();
    _recover(byRequest: true);
  }

  @override
  void onUnreachable() {
    if (_disposed) return;
    // A pending settle is kept: a new interface deserves one try even if an
    // older request failed.
    _setReachability(
      _interfaceUp
          ? NetworkReachability.unreachable
          : NetworkReachability.offline,
    );
  }

  void _onInterfaceChanged(bool up) {
    if (_disposed) return;
    if (up) {
      _interfaceUp = true;
      _offlineTimer?.cancel();
      _offlineTimer = null;
      // Already online and nothing refused: a flap within the grace, nothing
      // to recover from.
      if (_reachability != NetworkReachability.online || _refused) {
        _settleTimer ??= Timer(reconnectSettle, _onSettled);
      }
    } else {
      _interfaceUp = false;
      _settleTimer?.cancel();
      _settleTimer = null;
      if (_reachability != NetworkReachability.offline) {
        _offlineTimer ??= Timer(offlineGrace, _onGraceEnded);
      }
    }
  }

  void _onGraceEnded() {
    _offlineTimer = null;
    if (!_interfaceUp) _setReachability(NetworkReachability.offline);
  }

  void _onSettled() {
    _settleTimer = null;
    if (_interfaceUp) _recover();
  }

  /// Back online, and worth trying again. Still online after a refusal: the
  /// banner never showed, but the refused screen still needs its reconnect.
  void _recover({bool byRequest = false}) {
    final refused = _refused;
    _refused = false;
    if (_reachability == NetworkReachability.online && !refused) return;
    _setReachability(NetworkReachability.online);
    _announce(byRequest: byRequest);
  }

  void _announce({required bool byRequest}) {
    final now = _clock();
    final last = _lastAnnounced;
    if (last != null) {
      final gap = now.difference(last);
      // A wall clock moved back (NTP, NITZ) ends the cooldown instead of
      // stretching it by the size of the jump.
      if (!gap.isNegative && gap < reconnectCooldown) return;
    }
    _lastAnnounced = now;
    _byRequest = byRequest;
    if (!_reconnected.isClosed) _reconnected.add(null);
  }

  void _setReachability(NetworkReachability value) {
    if (_disposed || value == _reachability) return;
    _reachability = value;
    notifyListeners();
  }

  void _cancelTimers() {
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  /// One platform reading, shared by concurrent callers. Null when the
  /// platform failed or did not answer within [checkTimeout]: unknown, which
  /// every caller treats as "has network".
  Future<bool?> _read() =>
      _reading ??= _readOnce().whenComplete(() => _reading = null);

  Future<bool?> _readOnce() async {
    try {
      return await _interfaces.isUp().timeout(checkTimeout);
    } catch (error) {
      debugPrint('[NetworkMonitor] interface reading failed: $error');
      return null;
    }
  }

  /// Cancels the subscription, the timers and the lifecycle listener, and
  /// closes [reconnected].
  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    unawaited(_changes?.cancel());
    _changes = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_reconnected.close());
    super.dispose();
  }
}
