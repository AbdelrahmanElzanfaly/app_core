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
}
