import 'package:app_core/app_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Every test runs in fake time: the grace, settle, cooldown and platform
/// timeouts are real timers, and the clock follows the elapsed time.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final epoch = DateTime.utc(2026, 11, 11, 9);

  late FakeNetworkInterfaces interfaces;
  late NetworkMonitor monitor;
  late int reconnects;
  late int notifications;

  /// How far the wall clock is off the elapsed time: NTP moving it.
  var clockSkew = Duration.zero;

  /// A monitor over [interfaces], already started unless [start] is false.
  void setUpMonitor(FakeAsync async, {bool up = true, bool start = true}) {
    interfaces = FakeNetworkInterfaces(up: up);
    clockSkew = Duration.zero;
    monitor = NetworkMonitor(
      interfaces,
      clock: () => epoch.add(async.elapsed).add(clockSkew),
    );
    reconnects = 0;
    notifications = 0;
    monitor.reconnected.listen((_) => reconnects++);
    monitor.addListener(() => notifications++);
    if (start) {
      monitor.start();
      async.flushMicrotasks();
    }
  }

  /// [NetworkMonitor.hasNetwork]'s answer once fake time has run [elapse].
  bool? hasNetwork(FakeAsync async, {Duration elapse = Duration.zero}) {
    bool? answer;
    monitor.hasNetwork().then((value) => answer = value);
    async.elapse(elapse);
    return answer;
  }

  test('online before start(); start() with the interface down is offline '
      'at once, with nothing announced', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false, start: false);
      expect(monitor.reachability, NetworkReachability.online);

      monitor.start();
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.offline);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('start() with the interface up stays online', () {
    fakeAsync((async) {
      setUpMonitor(async);

      expect(monitor.reachability, NetworkReachability.online);
      expect(notifications, 0);
      expect(interfaces.hasListener, isTrue);
      monitor.dispose();
    });
  });

  test('a down event is offline only after the 2 s grace', () {
    fakeAsync((async) {
      setUpMonitor(async);

      interfaces.emit(false);
      async.elapse(const Duration(milliseconds: 1999));
      expect(monitor.reachability, NetworkReachability.online);

      async.elapse(const Duration(milliseconds: 1));
      expect(monitor.reachability, NetworkReachability.offline);
      expect(notifications, 1);
      monitor.dispose();
    });
  });

  test('a down-up flap within the grace changes nothing and announces '
      'nothing', () {
    fakeAsync((async) {
      setUpMonitor(async);

      interfaces.emit(false);
      async.elapse(const Duration(seconds: 1));
      interfaces.emit(true);
      async.elapse(const Duration(seconds: 10));

      expect(monitor.reachability, NetworkReachability.online);
      expect(notifications, 0);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('a request refused during the grace gets one reconnected when the '
      'interface returns, and the banner never shows', () {
    fakeAsync((async) {
      setUpMonitor(async);

      interfaces.emit(false);
      async.flushMicrotasks();
      expect(hasNetwork(async), isFalse, reason: 'the gate refuses');
      async.elapse(const Duration(milliseconds: 1500));
      interfaces.emit(true);
      async.elapse(const Duration(milliseconds: 999));
      expect(reconnects, 0, reason: 'the settle still applies');

      async.elapse(const Duration(milliseconds: 1));
      expect(reconnects, 1);
      expect(monitor.reconnectedByRequest, isFalse);
      expect(monitor.reachability, NetworkReachability.online);
      expect(notifications, 0);

      // Announced once: a later flap with nothing refused stays quiet.
      async.elapse(const Duration(seconds: 10));
      interfaces.emit(false);
      async.elapse(const Duration(seconds: 1));
      interfaces.emit(true);
      async.elapse(const Duration(seconds: 10));
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('a request refused during the grace, then one getting through: '
      'reconnected by a request', () {
    fakeAsync((async) {
      setUpMonitor(async);
      interfaces.emit(false);
      async.flushMicrotasks();
      expect(hasNetwork(async), isFalse);

      monitor.onReachable();
      async.flushMicrotasks();

      expect(reconnects, 1);
      expect(monitor.reconnectedByRequest, isTrue);
      expect(notifications, 0);
      monitor.dispose();
    });
  });

  test('down, then up: online after a 1 s settle, with one reconnected', () {
    fakeAsync((async) {
      setUpMonitor(async);
      interfaces.emit(false);
      async.elapse(const Duration(seconds: 2));
      expect(monitor.reachability, NetworkReachability.offline);

      interfaces.emit(true);
      async.elapse(const Duration(milliseconds: 999));
      expect(monitor.reachability, NetworkReachability.offline);
      expect(reconnects, 0);

      async.elapse(const Duration(milliseconds: 1));
      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);

      async.elapse(const Duration(seconds: 10));
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('an interface that drops again during the settle stays offline', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);

      interfaces.emit(true);
      async.elapse(const Duration(milliseconds: 500));
      interfaces.emit(false);
      async.elapse(const Duration(seconds: 5));

      expect(monitor.reachability, NetworkReachability.offline);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('a flap during the settle starts the settle again', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);

      interfaces.emit(true);
      async.elapse(const Duration(milliseconds: 500));
      interfaces.emit(false);
      async.elapse(const Duration(milliseconds: 300));
      interfaces.emit(true);

      async.elapse(const Duration(milliseconds: 999));
      expect(monitor.reachability, NetworkReachability.offline);

      async.elapse(const Duration(milliseconds: 1));
      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('onUnreachable with the interface up is unreachable; onReachable then '
      'recovers at once and announces', () {
    fakeAsync((async) {
      setUpMonitor(async);

      monitor.onUnreachable();
      expect(monitor.reachability, NetworkReachability.unreachable);
      expect(reconnects, 0);

      monitor.onReachable();
      async.flushMicrotasks();
      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('onUnreachable while the OS says down is offline', () {
    fakeAsync((async) {
      setUpMonitor(async);
      interfaces.emit(false);
      async.flushMicrotasks();

      monitor.onUnreachable();

      expect(monitor.reachability, NetworkReachability.offline);
      monitor.dispose();
    });
  });

  test('a pending settle survives an older request failing', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);

      interfaces.emit(true);
      async.elapse(const Duration(milliseconds: 500));
      monitor.onUnreachable();
      expect(monitor.reachability, NetworkReachability.unreachable);

      async.elapse(const Duration(milliseconds: 500));
      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('onReachable while the OS says down: hasNetwork is true with no '
      'platform call', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);
      expect(monitor.reachability, NetworkReachability.offline);
      final readsBefore = interfaces.reads;

      monitor.onReachable();
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      expect(hasNetwork(async), isTrue);
      expect(interfaces.reads, readsBefore);
      monitor.dispose();
    });
  });

  test('onReachable cancels a pending offline grace', () {
    fakeAsync((async) {
      setUpMonitor(async);
      interfaces.emit(false);
      async.elapse(const Duration(seconds: 1));

      monitor.onReachable();
      async.elapse(const Duration(seconds: 5));

      expect(monitor.reachability, NetworkReachability.online);
      expect(notifications, 0);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('reconnected is throttled by the cooldown', () {
    fakeAsync((async) {
      setUpMonitor(async);

      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 1);

      async.elapse(const Duration(milliseconds: 2999));
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 1, reason: 'within the 3 s cooldown');
      expect(monitor.reachability, NetworkReachability.online);

      async.elapse(const Duration(milliseconds: 1));
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 2);
      monitor.dispose();
    });
  });

  test('a wall clock moved back does not hold back the next reconnected', () {
    fakeAsync((async) {
      setUpMonitor(async);
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 1);

      // NTP corrects a clock that ran ahead.
      clockSkew = const Duration(minutes: -5);
      async.elapse(const Duration(seconds: 30));
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();

      expect(reconnects, 2);
      monitor.dispose();
    });
  });

  test('the cause of the last reconnected: a request, or the network', () {
    fakeAsync((async) {
      setUpMonitor(async);

      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(monitor.reconnectedByRequest, isTrue);

      async.elapse(const Duration(seconds: 3));
      monitor.onUnreachable();
      monitor.recheck();
      async.flushMicrotasks();
      expect(reconnects, 2);
      expect(monitor.reconnectedByRequest, isFalse);
      monitor.dispose();
    });
  });

  test('listeners are notified once per change', () {
    fakeAsync((async) {
      setUpMonitor(async);

      monitor
        ..onUnreachable()
        ..onUnreachable();
      expect(notifications, 1);

      monitor
        ..onReachable()
        ..onReachable();
      expect(notifications, 2);
      monitor.dispose();
    });
  });

  test('hasNetwork makes no platform call while the interface is up', () {
    fakeAsync((async) {
      setUpMonitor(async);
      final readsBefore = interfaces.reads;

      expect(hasNetwork(async), isTrue);
      expect(hasNetwork(async), isTrue);
      monitor.onUnreachable();
      expect(hasNetwork(async), isTrue, reason: 'unreachable is not offline');

      expect(interfaces.reads, readsBefore);
      monitor.dispose();
    });
  });

  test('while down, hasNetwork re-reads, returns the fresh answer and '
      'applies it', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);
      final readsBefore = interfaces.reads;

      expect(hasNetwork(async), isFalse);
      expect(interfaces.reads, readsBefore + 1);

      interfaces.up = true;
      expect(hasNetwork(async), isTrue);
      expect(interfaces.reads, readsBefore + 2);

      // Applied as an OS "up": no further reading, and online after the
      // settle.
      expect(hasNetwork(async), isTrue);
      expect(interfaces.reads, readsBefore + 2);
      async.elapse(const Duration(seconds: 1));
      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('concurrent hasNetwork calls while down share one reading', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);
      final readsBefore = interfaces.reads;
      interfaces.delay = const Duration(milliseconds: 100);

      final answers = <bool>[];
      for (var i = 0; i < 3; i++) {
        monitor.hasNetwork().then(answers.add);
      }
      async.elapse(const Duration(milliseconds: 100));

      expect(answers, [false, false, false]);
      expect(interfaces.reads, readsBefore + 1);
      monitor.dispose();
    });
  });

  test('isUp throwing or slower than 500 ms counts as network, and changes '
      'nothing', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false);

      interfaces.error = StateError('no plugin');
      expect(hasNetwork(async), isTrue);

      interfaces
        ..error = null
        ..delay = const Duration(seconds: 2);
      bool? slow;
      monitor.hasNetwork().then((value) => slow = value);
      async.elapse(const Duration(milliseconds: 499));
      expect(slow, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(slow, isTrue);

      async.elapse(const Duration(seconds: 5));
      expect(monitor.reachability, NetworkReachability.offline);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('recheck() while unreachable and up: online plus reconnected', () {
    fakeAsync((async) {
      setUpMonitor(async);
      monitor.onUnreachable();

      monitor.recheck();
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('recheck() while online does nothing', () {
    fakeAsync((async) {
      setUpMonitor(async);

      monitor.recheck();
      async.elapse(const Duration(seconds: 5));

      expect(monitor.reachability, NetworkReachability.online);
      expect(notifications, 0);
      expect(reconnects, 0);
      monitor.dispose();
    });
  });

  test('recheck() that finds no interface is applied as an OS "none"', () {
    fakeAsync((async) {
      setUpMonitor(async);
      interfaces.up = false;

      monitor.recheck();
      async.elapse(const Duration(milliseconds: 1999));
      expect(monitor.reachability, NetworkReachability.online);

      async.elapse(const Duration(milliseconds: 1));
      expect(monitor.reachability, NetworkReachability.offline);
      monitor.dispose();
    });
  });

  /// Walks the app through [states], one valid transition at a time.
  void lifecycle(List<AppLifecycleState> states) {
    for (final state in states) {
      binding.handleAppLifecycleStateChanged(state);
    }
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  test('a return from the background while not online rechecks', () {
    fakeAsync((async) {
      lifecycle([AppLifecycleState.resumed]);
      setUpMonitor(async, up: false);
      expect(monitor.reachability, NetworkReachability.offline);
      interfaces.up = true;

      lifecycle([...toBackground, ...toForeground]);
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('a focus-only interruption (Control Center, the notification shade) '
      'does not recheck', () {
    fakeAsync((async) {
      lifecycle([AppLifecycleState.resumed]);
      setUpMonitor(async);
      monitor.onUnreachable();
      final readsBefore = interfaces.reads;

      lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.unreachable);
      expect(reconnects, 0);
      expect(interfaces.reads, readsBefore);
      monitor.dispose();
    });
  });

  test('started in the background: the first resume rechecks', () {
    fakeAsync((async) {
      lifecycle([AppLifecycleState.resumed, ...toBackground]);
      setUpMonitor(async, up: false);
      interfaces.up = true;

      lifecycle(toForeground);
      async.flushMicrotasks();

      expect(monitor.reachability, NetworkReachability.online);
      expect(reconnects, 1);
      monitor.dispose();
    });
  });

  test('start() is idempotent', () {
    fakeAsync((async) {
      setUpMonitor(async, start: false);

      final first = monitor.start();
      expect(monitor.start(), same(first));
      async.flushMicrotasks();

      expect(interfaces.reads, 1);
      monitor.dispose();
    });
  });

  test('start() survives an isUp that throws: online, and still listening', () {
    fakeAsync((async) {
      setUpMonitor(async, start: false);
      interfaces.error = StateError('MissingPluginException');

      var started = false;
      monitor.start().then((_) => started = true);
      async.flushMicrotasks();

      expect(started, isTrue);
      expect(monitor.reachability, NetworkReachability.online);

      interfaces.emit(false);
      async.elapse(const Duration(seconds: 2));
      expect(monitor.reachability, NetworkReachability.offline);
      monitor.dispose();
    });
  });

  test('start() whose reading never answers stays online', () {
    fakeAsync((async) {
      setUpMonitor(async, up: false, start: false);
      interfaces.delay = const Duration(minutes: 1);

      var started = false;
      monitor.start().then((_) => started = true);
      async.elapse(const Duration(milliseconds: 500));

      expect(started, isTrue);
      expect(monitor.reachability, NetworkReachability.online);
      monitor.dispose();
    });
  });

  test('dispose cancels the subscription and the timers, and closes '
      'reconnected', () {
    fakeAsync((async) {
      setUpMonitor(async);
      var closed = false;
      monitor.reconnected.listen(null, onDone: () => closed = true);
      interfaces.emit(false);
      async.flushMicrotasks();
      expect(async.pendingTimers, isNotEmpty);

      monitor.dispose();
      async.flushMicrotasks();

      expect(interfaces.hasListener, isFalse);
      expect(async.pendingTimers, isEmpty);
      expect(closed, isTrue);
      expect(hasNetwork(async), isTrue);
      monitor
        ..onUnreachable()
        ..onReachable();
      expect(monitor.reachability, NetworkReachability.online);
    });
  });
}
