import 'package:app_core/app_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late SessionService service;

  setUp(() async {
    setUpCore();
    service = SessionService(
      const FlutterSecureStorage(),
      retryDelay: Duration.zero,
    );
    await service.save(session('access-1'));
  });

  test('renewed on the first attempt', () async {
    service.refresher = FakeRefresher([session('access-2', 'refresh-2')]);

    expect(await service.refreshAccessToken(), 'access-2');
    expect(service.session?.refreshToken, 'refresh-2');
  });

  test('a network failure is retried once, then succeeds', () async {
    final refresher = FakeRefresher([offline, session('access-2')]);
    service.refresher = refresher;

    expect(await service.refreshAccessToken(), 'access-2');
    expect(refresher.calls, 2);
  });

  test('two network failures keep the session and surface the failure', () async {
    final refresher = FakeRefresher([offline, offline]);
    service.refresher = refresher;

    await expectLater(
      service.refreshAccessToken(),
      throwsA(isA<AppFailure>().having((f) => f.type, 'type', FailureType.network)),
    );
    expect(refresher.calls, 2);
    expect(service.isAuthenticated, isTrue);
    expect(service.session?.accessToken, 'access-1');
  });

  test('invalid_grant ends the session at once, without a retry', () async {
    final refresher = FakeRefresher([rejected]);
    service.refresher = refresher;
    var notified = false;
    service.addListener(() => notified = true);

    expect(await service.refreshAccessToken(), isNull);
    expect(refresher.calls, 1);
    expect(service.isAuthenticated, isFalse);
    expect(notified, isTrue, reason: 'the router guard must re-run');
  });

  test('concurrent 401s share one renewal', () async {
    final hold = gate();
    final refresher = FakeRefresher([session('access-2')], gate: hold.future);
    service.refresher = refresher;

    final results = Future.wait([
      service.refreshAccessToken(),
      service.refreshAccessToken(),
      service.refreshAccessToken(),
    ]);
    hold.complete();

    expect(await results, ['access-2', 'access-2', 'access-2']);
    expect(refresher.calls, 1);
  });

  test('with no way to renew, the session ends', () async {
    expect(await service.refreshAccessToken(), isNull);
    expect(service.isAuthenticated, isFalse);
  });

  test('an expired access token still counts as signed in after restore',
      () async {
    await service.save(
      AuthSession(
        accessToken: 'stale',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    final restored = SessionService(const FlutterSecureStorage());
    await restored.restore();

    expect(restored.session?.isExpired, isTrue);
    expect(restored.isAuthenticated, isTrue);
  });

  group('session-scoped stores', () {
    late List<String> log;

    SessionService withStores(List<SessionScoped> stores) => SessionService(
      const FlutterSecureStorage(),
      retryDelay: Duration.zero,
      scoped: stores,
    );

    Future<String?> storedAccessToken() =>
        const FlutterSecureStorage().read(key: 'test.session.accessToken');

    setUp(() => log = []);

    test('clear() ends them before the tokens are deleted and before '
        'listeners are notified', () async {
      final scoped = withStores([
        RecordingScoped(
          log,
          onEnd: () async => log.add('token: ${await storedAccessToken()}'),
        ),
      ]);
      await scoped.save(session('access-1'));
      log.clear();
      scoped.addListener(() => log.add('notified'));

      await scoped.clear();

      expect(log, ['ended', 'token: access-1', 'notified']);
      expect(await storedAccessToken(), isNull);
      expect(scoped.isAuthenticated, isFalse);
    });

    test('restore() with a stored session starts them', () async {
      final scoped = withStores([RecordingScoped(log)]);
      scoped.addListener(() => log.add('notified'));

      await scoped.restore();

      expect(scoped.isAuthenticated, isTrue);
      expect(log, ['started', 'notified']);
    });

    test('restore() with no stored session ends them', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final scoped = withStores([RecordingScoped(log)]);
      scoped.addListener(() => log.add('notified'));

      await scoped.restore();

      expect(scoped.isAuthenticated, isFalse);
      expect(log, ['ended', 'notified']);
    });

    test('save() on renewal starts them without ending them', () async {
      final scoped = withStores([RecordingScoped(log)]);
      await scoped.restore();
      scoped.refresher = FakeRefresher([session('access-2', 'refresh-2')]);

      expect(await scoped.refreshAccessToken(), 'access-2');

      expect(log, ['started', 'started']);
    });

    test('invalid_grant ends them', () async {
      final scoped = withStores([RecordingScoped(log)]);
      await scoped.restore();
      scoped.refresher = FakeRefresher([rejected]);

      expect(await scoped.refreshAccessToken(), isNull);

      expect(log, ['started', 'ended']);
      expect(scoped.isAuthenticated, isFalse);
    });

    test('a renewal that keeps the session leaves them alone', () async {
      final scoped = withStores([RecordingScoped(log)]);
      await scoped.restore();
      scoped.refresher = FakeRefresher([offline, offline]);

      await expectLater(
        scoped.refreshAccessToken(),
        throwsA(isA<AppFailure>()),
      );

      expect(log, ['started']);
    });

    test('a store whose onSessionEnded throws still lets logout complete '
        'and notify', () async {
      final scoped = withStores([
        RecordingScoped(
          log,
          name: 'first ',
          onEnd: () => throw StateError('store unavailable'),
        ),
        RecordingScoped(log, name: 'second '),
      ]);
      await scoped.restore();
      log.clear();
      scoped.addListener(() => log.add('notified'));

      await scoped.clear();

      expect(log, ['first ended', 'second ended', 'notified']);
      expect(scoped.isAuthenticated, isFalse);
      expect(await storedAccessToken(), isNull);
    });
  });
}
