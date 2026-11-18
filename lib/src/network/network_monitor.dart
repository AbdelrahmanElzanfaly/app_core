import 'dart:async';

import 'package:app_network/app_network.dart';
import 'package:flutter/widgets.dart';

import 'network_interfaces.dart';
import 'network_reachability.dart';

/// One cheap request to the app's own server, for [NetworkMonitor.probe].
///
/// The monitor does not read what it returns: the client it goes through
/// reports the outcome to the monitor, as it does for every request. Send
/// it past the connectivity gate, and never resend it.
typedef NetworkProbe = Future<void> Function();

/// What the app believes about reaching its servers, from two witnesses:
/// the OS interface list and the outcome of real requests. Real traffic
/// beats the OS. Starts online: nothing is reported offline on a guess.
///
/// Given a [probe], it also looks for itself while it is not online, so a
/// recovery the platform never announces (Wi-Fi that stayed connected while
/// its internet came back) is found without the user asking.
///
/// It also remembers whether the server could serve its last answer
/// ([isServiceUnavailable]): reached, but answering with a 5xx.
///
/// The NetworkStatus, ReachabilityObserver and ServiceObserver behind every
/// client, the same way SessionService is the TokenStore and
/// SessionRefresher.
class NetworkMonitor extends ChangeNotifier
    implements NetworkStatus, ReachabilityObserver, ServiceObserver {
  NetworkMonitor(
    this._interfaces, {
    this.offlineGrace = const Duration(seconds: 2),
    this.reconnectSettle = const Duration(seconds: 1),
    this.reconnectCooldown = const Duration(seconds: 3),
    this.checkTimeout = const Duration(milliseconds: 500),
    this.probeDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ],
    DateTime Function()? clock,
  }) : assert(probeDelays.isNotEmpty),
       _clock = clock ?? DateTime.now;

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

  /// The wait before each look while not online; the last one repeats. They
  /// start again from the first after every recovery.
  final List<Duration> probeDelays;

  NetworkProbe? _probe;

  /// How the monitor looks for itself while it is not online and the app is
  /// in the foreground: it reads the interface again, then sends this, after
  /// each of [probeDelays]. Null (the default): it never looks, and waits
  /// for the platform, a return from the background or a request.
  ///
  /// Set by the app once its client exists, before [start], the way
  /// `SessionService.refresher` is.
  NetworkProbe? get probe => _probe;

  set probe(NetworkProbe? value) {
    _probe = value;
    if (value == null) {
      _stopProbing();
    } else {
      _scheduleProbe();
    }
  }

  final DateTime Function() _clock;
  final StreamController<void> _reconnected = StreamController.broadcast();

  NetworkReachability _reachability = NetworkReachability.online;
  bool _serviceUnavailable = false;

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

  /// A [reconnected] held back until the cooldown ends, and whether every
  /// recovery it stands for came from a request.
  Timer? _announceTimer;
  bool _deferredByRequest = false;

  Timer? _probeTimer;

  /// Looks since the last time online: picks the next of [probeDelays].
  int _probes = 0;
  bool _probing = false;
  StreamSubscription<bool>? _changes;
  AppLifecycleListener? _lifecycle;
  Future<void>? _started;
  Future<bool?>? _reading;
  bool _disposed = false;

  NetworkReachability get reachability => _reachability;

  /// The server's last answer was a 5xx: it is reached, and cannot serve.
  /// Its next answer of any other status clears this, and so does [retry].
  /// Says nothing about reaching it: that is [reachability].
  bool get isServiceUnavailable => _serviceUnavailable;

  /// Worth trying again: a network appeared (or came back from a short drop
  /// during which a request was refused), the app returned from the
  /// background while not online, or a request got through after a failure.
  /// At most once per [reconnectCooldown]: one that falls inside it waits
  /// for its end, and is dropped only if the network is lost again by then.
  /// Broadcast.
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
      onHide: () {
        _backgrounded = true;
        // Nothing is sent from the background.
        _cancelProbeTimer();
      },
      onResume: () {
        if (!_backgrounded) return;
        _backgrounded = false;
        // Still not online after the reading: the looks start again.
        unawaited(recheck().whenComplete(_scheduleProbe));
      },
    );
    if (_backgrounded) {
      _cancelProbeTimer();
    } else {
      _scheduleProbe();
    }
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

  @override
  void onServiceAvailable() => _setServiceUnavailable(false);

  @override
  void onServiceUnavailable() => _setServiceUnavailable(true);

  /// The user asks to try again, from a banner say: announces [reconnected],
  /// so every screen showing a failure reloads, as after a recovery.
  ///
  /// Optimistic about the service: [isServiceUnavailable] is forgotten, and
  /// the reloads' own answers say whether it still is. Nothing looks for a
  /// failing service by itself: a busy server is not asked again until
  /// someone wants it.
  void retry() {
    if (_disposed) return;
    _setServiceUnavailable(false);
    _announce(byRequest: false);
  }

  void _setServiceUnavailable(bool value) {
    if (_disposed || value == _serviceUnavailable) return;
    _serviceUnavailable = value;
    notifyListeners();
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
    if (_announceTimer != null) {
      // One is already waiting for the cooldown to end: it stands for both.
      _deferredByRequest = _deferredByRequest && byRequest;
      return;
    }
    final now = _clock();
    final last = _lastAnnounced;
    if (last != null) {
      final gap = now.difference(last);
      // A wall clock moved back (NTP, NITZ) ends the cooldown instead of
      // stretching it by the size of the jump.
      if (!gap.isNegative && gap < reconnectCooldown) {
        // Held back, not dropped: a screen that failed since the last one
        // is waiting for this recovery, and no other will follow it.
        _deferredByRequest = byRequest;
        _announceTimer = Timer(reconnectCooldown - gap, _announceDeferred);
        return;
      }
    }
    _emitReconnected(now, byRequest: byRequest);
  }

  void _announceDeferred() {
    _announceTimer = null;
    // Lost again meanwhile: the next recovery announces.
    if (_disposed || _reachability != NetworkReachability.online) return;
    _emitReconnected(_clock(), byRequest: _deferredByRequest);
  }

  void _emitReconnected(DateTime now, {required bool byRequest}) {
    _lastAnnounced = now;
    _byRequest = byRequest;
    if (!_reconnected.isClosed) _reconnected.add(null);
  }

  void _setReachability(NetworkReachability value) {
    if (_disposed || value == _reachability) return;
    _reachability = value;
    if (value == NetworkReachability.online) {
      _stopProbing();
    } else {
      _scheduleProbe();
    }
    notifyListeners();
  }

  /// Arms the next look, if there is anything to look for and nothing is
  /// armed or running already.
  void _scheduleProbe() {
    if (_disposed ||
        _probe == null ||
        _backgrounded ||
        _probing ||
        _probeTimer != null ||
        _reachability == NetworkReachability.online) {
      return;
    }
    final index =
        _probes < probeDelays.length ? _probes : probeDelays.length - 1;
    _probeTimer = Timer(probeDelays[index], _runProbe);
  }

  Future<void> _runProbe() async {
    _probeTimer = null;
    final probe = _probe;
    if (_disposed ||
        probe == null ||
        _backgrounded ||
        _reachability == NetworkReachability.online) {
      return;
    }
    _probing = true;
    _probes++;
    try {
      // A change the platform never announced: an event it dropped while
      // the app was in the background, or one it does not send at all.
      final up = await _read();
      if (_disposed) return;
      if (up != null && up != _interfaceUp) _onInterfaceChanged(up);
      // Sent whatever the reading says: only a request can prove it wrong.
      // Its outcome arrives through onReachable or onUnreachable.
      await probe();
    } catch (error) {
      debugPrint('[NetworkMonitor] probe failed: $error');
    } finally {
      _probing = false;
    }
    _scheduleProbe();
  }

  void _stopProbing() {
    _cancelProbeTimer();
    _probes = 0;
  }

  void _cancelProbeTimer() {
    _probeTimer?.cancel();
    _probeTimer = null;
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
    _cancelProbeTimer();
    _announceTimer?.cancel();
    _announceTimer = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_reconnected.close());
    super.dispose();
  }
}
