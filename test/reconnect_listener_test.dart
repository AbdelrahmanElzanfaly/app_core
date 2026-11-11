import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late NetworkMonitor monitor;
  late ValueNotifier<bool> busy;
  late int reloads;

  NetworkMonitor newMonitor() => NetworkMonitor(
    FakeNetworkInterfaces(),
    // Every announcement counts: the cooldown has its own tests.
    reconnectCooldown: Duration.zero,
  );

  setUp(() {
    monitor = newMonitor();
    busy = ValueNotifier(false);
    reloads = 0;
  });

  tearDown(() {
    monitor.dispose();
    busy.dispose();
  });

  Widget listener({required bool enabled, ValueListenable<bool>? busy}) =>
      ReconnectListener(
        enabled: enabled,
        busy: busy,
        onReconnect: () => reloads++,
        child: const SizedBox(),
      );

  Future<void> pumpListener(
    WidgetTester tester, {
    required bool enabled,
    ValueListenable<bool>? busy,
    NetworkMonitor? scope,
  }) => tester.pumpWidget(
    NetworkScope(
      monitor: scope ?? monitor,
      child: listener(enabled: enabled, busy: busy),
    ),
  );

  /// A request got through after a failure: the monitor announces.
  Future<void> announce(WidgetTester tester, [NetworkMonitor? on]) async {
    (on ?? monitor)
      ..onUnreachable()
      ..onReachable();
    await tester.pump();
  }

  /// The network came back (here, a resume finding the interface up): the
  /// monitor announces with no request involved.
  Future<void> comeBack(WidgetTester tester) async {
    monitor.onUnreachable();
    await monitor.recheck();
    await tester.pump();
  }

  group('ReconnectListener', () {
    testWidgets('enabled and not busy: fires once per announcement', (
      tester,
    ) async {
      await pumpListener(tester, enabled: true, busy: busy);

      await announce(tester);
      expect(reloads, 1);

      await announce(tester);
      expect(reloads, 2);
    });

    testWidgets('disabled: nothing', (tester) async {
      await pumpListener(tester, enabled: false, busy: busy);

      await announce(tester);

      expect(reloads, 0);
    });

    testWidgets('without busy, an enabled listener fires at once', (
      tester,
    ) async {
      await pumpListener(tester, enabled: true);

      await announce(tester);

      expect(reloads, 1);
    });

    testWidgets('the network coming back while busy fires once after the '
        'frame in which the load ended', (tester) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);

      await comeBack(tester);
      expect(reloads, 0, reason: 'never on top of a running load');

      busy.value = false;
      expect(reloads, 0, reason: 'waits for the page to rebuild');

      await tester.pump();
      expect(reloads, 1);

      busy
        ..value = true
        ..value = false;
      await tester.pump();
      expect(reloads, 1, reason: 'the missed reconnect fires only once');
    });

    testWidgets('a request getting through while busy, still online when the '
        'load ends: nothing, as that request may have been the load', (
      tester,
    ) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);

      // The load's own 503 is an answer: the monitor recovers and announces.
      await announce(tester);
      busy.value = false;
      await tester.pump();

      expect(reloads, 0);
    });

    testWidgets('a request getting through while busy, then the load fails '
        'on the transport: fires once', (tester) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);

      await announce(tester);
      monitor.onUnreachable();
      busy.value = false;
      await tester.pump();

      expect(reloads, 1);
    });

    testWidgets('a request and the network both coming back while busy: '
        'fires once, even still online', (tester) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);

      await comeBack(tester);
      await announce(tester);
      busy.value = false;
      await tester.pump();

      expect(reloads, 1);
    });

    testWidgets('busy false while the screen no longer needs it: nothing, '
        'and the missed reconnect is forgotten', (tester) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);
      await comeBack(tester);

      // The load succeeded: the page rebuilds in the same frame with nothing
      // left to recover.
      busy.value = false;
      await pumpListener(tester, enabled: false, busy: busy);
      expect(reloads, 0);

      // The screen fails again later; the old reconnect is not replayed.
      await pumpListener(tester, enabled: true, busy: busy);
      busy
        ..value = true
        ..value = false;
      await tester.pump();
      expect(reloads, 0);
    });

    testWidgets('no NetworkScope: nothing', (tester) async {
      await tester.pumpWidget(listener(enabled: true, busy: busy));

      await announce(tester);

      expect(reloads, 0);
    });

    testWidgets('unmounted: nothing, even for a reconnect missed while busy', (
      tester,
    ) async {
      busy.value = true;
      await pumpListener(tester, enabled: true, busy: busy);
      await comeBack(tester);

      await tester.pumpWidget(
        NetworkScope(monitor: monitor, child: const SizedBox()),
      );
      busy.value = false;
      await tester.pump();
      await announce(tester);

      expect(reloads, 0);
    });

    testWidgets('follows a swapped monitor', (tester) async {
      final other = newMonitor();
      addTearDown(other.dispose);
      await pumpListener(tester, enabled: true, busy: busy);

      await pumpListener(tester, enabled: true, busy: busy, scope: other);
      await announce(tester, monitor);
      expect(reloads, 0);

      await announce(tester, other);
      expect(reloads, 1);
    });

    testWidgets('follows a swapped busy signal', (tester) async {
      final other = ValueNotifier(true);
      addTearDown(other.dispose);
      await pumpListener(tester, enabled: true, busy: busy);

      await pumpListener(tester, enabled: true, busy: other);
      await comeBack(tester);
      expect(reloads, 0, reason: 'the new signal is busy');

      busy
        ..value = true
        ..value = false;
      await tester.pump();
      expect(reloads, 0, reason: 'the old signal is no longer heard');

      other.value = false;
      await tester.pump();
      expect(reloads, 1);
    });
  });

  group('NetworkScope', () {
    testWidgets('reachabilityOf is online without a scope', (tester) async {
      NetworkReachability? seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = NetworkScope.reachabilityOf(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, NetworkReachability.online);
    });

    testWidgets('dependents rebuild when reachability changes', (tester) async {
      NetworkReachability? seen;
      var builds = 0;
      await tester.pumpWidget(
        NetworkScope(
          monitor: monitor,
          child: Builder(
            builder: (context) {
              builds++;
              seen = NetworkScope.reachabilityOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, NetworkReachability.online);

      monitor.onUnreachable();
      await tester.pump();
      expect(seen, NetworkReachability.unreachable);
      expect(builds, 2);

      monitor.onUnreachable();
      await tester.pump();
      expect(builds, 2, reason: 'no change, no rebuild');
    });

    testWidgets('maybeOf finds the monitor without a rebuild dependency', (
      tester,
    ) async {
      NetworkMonitor? found;
      var builds = 0;
      await tester.pumpWidget(
        NetworkScope(
          monitor: monitor,
          child: Builder(
            builder: (context) {
              builds++;
              found = NetworkScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );

      monitor.onUnreachable();
      await tester.pump();

      expect(found, same(monitor));
      expect(builds, 1);
    });
  });
}
