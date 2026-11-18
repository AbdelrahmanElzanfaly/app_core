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
      expect(reconnects, 2, reason: 'held back until the cooldown ended');

      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 2, reason: 'a new cooldown runs from the second');
      async.elapse(const Duration(seconds: 3));
      expect(reconnects, 3);
      monitor.dispose();
    });
  });

  test('a recovery inside the cooldown is announced when it ends: a request '
      'refused during a second quick drop still gets its reconnected', () {
    fakeAsync((async) {
      setUpMonitor(async);

      // A first drop and return, announced with nothing on screen needing it.
      interfaces.emit(false);
      async.elapse(const Duration(seconds: 2));
      interfaces.emit(true);
      async.elapse(const Duration(seconds: 1));
      expect(reconnects, 1);

      // A second drop half a second later, and a request refused during it.
      async.elapse(const Duration(milliseconds: 500));
      interfaces.emit(false);
      async.flushMicrotasks();
      expect(hasNetwork(async), isFalse, reason: 'the gate refuses');
      async.elapse(const Duration(milliseconds: 200));
      interfaces.emit(true);

      // The settle ends 1.7 s after the first announcement.
      async.elapse(const Duration(seconds: 1));
      expect(reconnects, 1, reason: 'inside the cooldown');
      expect(monitor.reachability, NetworkReachability.online);

      async.elapse(const Duration(milliseconds: 1299));
      expect(reconnects, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(reconnects, 2, reason: 'the refused screen is told');
      expect(monitor.reconnectedByRequest, isFalse);
      monitor.dispose();
    });
  });

  test('a held-back reconnected is dropped when the network is lost again '
      'before the cooldown ends', () {
    fakeAsync((async) {
      setUpMonitor(async);
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(reconnects, 1);

      async.elapse(const Duration(seconds: 1));
      monitor
        ..onUnreachable()
        ..onReachable();
      async.elapse(const Duration(seconds: 1));
      monitor.onUnreachable();
      async.elapse(const Duration(seconds: 10));
      expect(reconnects, 1, reason: 'nothing to reload against');

      // The next recovery announces as usual.
      monitor.onReachable();
      async.flushMicrotasks();
      expect(reconnects, 2);
      monitor.dispose();
    });
  });

  test('a held-back reconnected is by a request only if every recovery it '
      'stands for was', () {
    fakeAsync((async) {
      setUpMonitor(async);
      monitor
        ..onUnreachable()
        ..onReachable();
      async.flushMicrotasks();
      expect(monitor.reconnectedByRequest, isTrue);

      // The network comes back (a resume finding the interface up), then a
      // request gets through, both inside the cooldown.
      async.elapse(const Duration(seconds: 1));
      monitor
        ..onUnreachable()
        ..recheck();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 500));
      monitor
        ..onUnreachable()
        ..onReachable();
      async.elapse(const Duration(milliseconds: 1500));

      expect(reconnects, 2, reason: 'one for both');
      expect(monitor.reconnectedByRequest, isFalse);
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

  group('looking for itself', () {
    /// When each look sent its request, in elapsed fake time.
    late List<Duration> looks;

    /// A started monitor in the foreground whose probe records each look
    /// and then reports [answer], as the client it goes through would.
    void setUpProbing(
      FakeAsync async, {
      bool up = true,
      void Function()? answer,
    }) {
      lifecycle([AppLifecycleState.resumed]);
      setUpMonitor(async, up: up, start: false);
      looks = [];
      monitor.probe = () async {
        looks.add(async.elapsed);
        answer?.call();
      };
      monitor.start();
      async.flushMicrotasks();
    }

    const s5 = Duration(seconds: 5);

    test('without a probe it never looks', () {
      fakeAsync((async) {
        lifecycle([AppLifecycleState.resumed]);
        setUpMonitor(async);
        monitor.onUnreachable();
        final readsBefore = interfaces.reads;

        async.elapse(const Duration(minutes: 10));

        expect(monitor.reachability, NetworkReachability.unreachable);
        expect(interfaces.reads, readsBefore);
        expect(async.pendingTimers, isEmpty);
        monitor.dispose();
      });
    });

    test('unreachable: looks after 5, 10 and 20 s, then every 30 s', () {
      fakeAsync((async) {
        setUpProbing(async, answer: () => monitor.onUnreachable());
        monitor.onUnreachable();

        async.elapse(const Duration(milliseconds: 4999));
        expect(looks, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(looks, [s5]);

        async.elapse(const Duration(seconds: 90));
        expect(looks, [
          s5,
          const Duration(seconds: 15),
          const Duration(seconds: 35),
          const Duration(seconds: 65),
          const Duration(seconds: 95),
        ]);
        expect(monitor.reachability, NetworkReachability.unreachable);
        expect(reconnects, 0);
        monitor.dispose();
      });
    });

    test('Wi-Fi stayed connected and its internet came back: the look gets '
        'an answer, and the app is online with one reconnected', () {
      fakeAsync((async) {
        var serverAnswers = false;
        setUpProbing(
          async,
          answer:
              () =>
                  serverAnswers
                      ? monitor.onReachable()
                      : monitor.onUnreachable(),
        );
        monitor.onUnreachable();
        async.elapse(s5);
        expect(monitor.reachability, NetworkReachability.unreachable);

        // The interface never changed, so the platform says nothing.
        serverAnswers = true;
        async.elapse(const Duration(seconds: 10));

        expect(monitor.reachability, NetworkReachability.online);
        expect(reconnects, 1);
        expect(monitor.reconnectedByRequest, isTrue);

        // Online: the looks stop.
        async.elapse(const Duration(minutes: 10));
        expect(looks, hasLength(2));
        expect(async.pendingTimers, isEmpty);
        monitor.dispose();
      });
    });

    test('offline, and the platform never announces the interface coming '
        'back: the look reads it again and recovers', () {
      fakeAsync((async) {
        setUpProbing(async, up: false, answer: () => monitor.onUnreachable());
        expect(monitor.reachability, NetworkReachability.offline);

        interfaces.up = true;
        async.elapse(s5);
        expect(looks, [s5]);

        // As when the platform reports it: online after the 1 s settle.
        async.elapse(const Duration(seconds: 1));
        expect(monitor.reachability, NetworkReachability.online);
        expect(reconnects, 1);
        monitor.dispose();
      });
    });

    test('offline for real: each look is sent anyway and changes nothing', () {
      fakeAsync((async) {
        setUpProbing(async, up: false, answer: () => monitor.onUnreachable());

        async.elapse(const Duration(seconds: 15));

        expect(looks, [s5, const Duration(seconds: 15)]);
        expect(monitor.reachability, NetworkReachability.offline);
        expect(reconnects, 0);
        expect(notifications, 1, reason: 'offline, once, at the start');
        monitor.dispose();
      });
    });

    test('a wrong "no network" from the platform: the look that gets an '
        'answer puts the app online', () {
      fakeAsync((async) {
        setUpProbing(async, up: false, answer: () => monitor.onReachable());

        async.elapse(s5);

        expect(monitor.reachability, NetworkReachability.online);
        expect(reconnects, 1);
        expect(hasNetwork(async), isTrue, reason: 'the gate is open again');
        monitor.dispose();
      });
    });

    test('the waits start again from 5 s after a recovery', () {
      fakeAsync((async) {
        var serverAnswers = false;
        setUpProbing(
          async,
          answer:
              () =>
                  serverAnswers
                      ? monitor.onReachable()
                      : monitor.onUnreachable(),
        );
        monitor.onUnreachable();
        async.elapse(const Duration(seconds: 15));
        serverAnswers = true;
        async.elapse(const Duration(seconds: 20));
        expect(monitor.reachability, NetworkReachability.online);
        expect(looks, hasLength(3));

        serverAnswers = false;
        monitor.onUnreachable();
        async.elapse(const Duration(milliseconds: 4999));
        expect(looks, hasLength(3));
        async.elapse(const Duration(milliseconds: 1));
        expect(looks, hasLength(4));
        monitor.dispose();
      });
    });

    test('nothing is sent from the background; the looks start again with '
        'the app', () {
      fakeAsync((async) {
        setUpProbing(async, up: false, answer: () => monitor.onUnreachable());
        lifecycle(toBackground);

        async.elapse(const Duration(minutes: 10));
        expect(looks, isEmpty);
        expect(async.pendingTimers, isEmpty);

        lifecycle(toForeground);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 4999));
        expect(looks, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(looks, hasLength(1));
        monitor.dispose();
      });
    });

    test('a probe that throws is survived, and the next look still runs', () {
      fakeAsync((async) {
        lifecycle([AppLifecycleState.resumed]);
        setUpMonitor(async, start: false);
        var calls = 0;
        monitor.probe = () async {
          calls++;
          throw StateError('no client');
        };
        monitor.start();
        async.flushMicrotasks();
        monitor.onUnreachable();

        async.elapse(const Duration(seconds: 15));

        expect(calls, 2);
        expect(monitor.reachability, NetworkReachability.unreachable);
        monitor.dispose();
      });
    });

    test('a probe set while not online starts the looks; clearing it stops '
        'them', () {
      fakeAsync((async) {
        lifecycle([AppLifecycleState.resumed]);
        setUpMonitor(async);
        monitor.onUnreachable();
        async.elapse(const Duration(minutes: 1));

        var calls = 0;
        monitor.probe = () async => calls++;
        async.elapse(s5);
        expect(calls, 1);

        monitor.probe = null;
        async.elapse(const Duration(minutes: 10));
        expect(calls, 1);
        expect(async.pendingTimers, isEmpty);
        monitor.dispose();
      });
    });

    test('dispose cancels the pending look', () {
      fakeAsync((async) {
        setUpProbing(async, answer: () => monitor.onUnreachable());
        monitor.onUnreachable();
        expect(async.pendingTimers, isNotEmpty);

        monitor.dispose();

        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(minutes: 10));
        expect(looks, isEmpty);
      });
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

  group('whether the server can serve', () {
    test('a 5xx answer says it cannot, the next other answer that it can; '
        'listeners hear each change once', () {
      fakeAsync((async) {
        setUpMonitor(async);
        expect(monitor.isServiceUnavailable, isFalse);

        monitor
          ..onServiceUnavailable()
          ..onServiceUnavailable();
        expect(monitor.isServiceUnavailable, isTrue);
        expect(notifications, 1);

        monitor
          ..onServiceAvailable()
          ..onServiceAvailable();
        expect(monitor.isServiceUnavailable, isFalse);
        expect(notifications, 2);
        monitor.dispose();
      });
    });

    test('it says nothing about reaching the server: still online, nothing '
        'announced, and nothing looks for it', () {
      fakeAsync((async) {
        setUpMonitor(async);
        var looks = 0;
        monitor.probe = () async => looks++;

        monitor.onServiceUnavailable();
        async.elapse(const Duration(minutes: 5));

        expect(monitor.reachability, NetworkReachability.online);
        expect(monitor.isServiceUnavailable, isTrue);
        expect(reconnects, 0);
        // A busy server is not asked again until someone wants it.
        expect(looks, 0);
        monitor.dispose();
      });
    });

    test('a lost connection keeps what the server last said', () {
      fakeAsync((async) {
        setUpMonitor(async);
        monitor
          ..onServiceUnavailable()
          ..onUnreachable();

        expect(monitor.reachability, NetworkReachability.unreachable);
        expect(monitor.isServiceUnavailable, isTrue);

        // It answers again, and can serve.
        monitor
          ..onReachable()
          ..onServiceAvailable();
        expect(monitor.reachability, NetworkReachability.online);
        expect(monitor.isServiceUnavailable, isFalse);
        monitor.dispose();
      });
    });

    test('retry forgets it and announces a reconnect, not by a request, so '
        'every screen showing a failure reloads', () {
      fakeAsync((async) {
        setUpMonitor(async);
        monitor.onServiceUnavailable();

        monitor.retry();
        async.flushMicrotasks();

        expect(monitor.isServiceUnavailable, isFalse);
        expect(reconnects, 1);
        expect(monitor.reconnectedByRequest, isFalse);
        expect(monitor.reachability, NetworkReachability.online);
        monitor.dispose();
      });
    });

    test('retry announces with nothing wrong too: the screens decide', () {
      fakeAsync((async) {
        setUpMonitor(async);

        monitor.retry();
        async.flushMicrotasks();

        expect(reconnects, 1);
        // Nothing changed for a banner to redraw.
        expect(notifications, 0);
        monitor.dispose();
      });
    });

    test('a second retry inside the cooldown is held back until it ends, '
        'not dropped', () {
      fakeAsync((async) {
        setUpMonitor(async);
        monitor.retry();
        async.flushMicrotasks();
        expect(reconnects, 1);

        // The reload failed again, and the customer taps once more.
        async.elapse(const Duration(seconds: 1));
        monitor
          ..onServiceUnavailable()
          ..retry();
        async.flushMicrotasks();
        expect(reconnects, 1);
        expect(monitor.isServiceUnavailable, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(reconnects, 2);
        monitor.dispose();
      });
    });

    test('after dispose, verdicts and retry change nothing', () {
      fakeAsync((async) {
        setUpMonitor(async);
        monitor.dispose();

        monitor
          ..onServiceUnavailable()
          ..retry();
        async.flushMicrotasks();

        expect(monitor.isServiceUnavailable, isFalse);
        expect(reconnects, 0);
      });
    });
  });
}
