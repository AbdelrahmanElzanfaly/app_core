import 'package:dio/dio.dart';
import 'package:app_core/app_core.dart';
import 'package:app_network/app_network.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The whole path a feature's request takes, with only the server and the
/// identity server faked: `SessionService`, `DioManager`, its interceptors
/// and `AppFailureConverter` are the real ones, and failures are read back
/// the way a repository reads them — through `Result.guard`.
void main() {
  late SessionService sessionService;
  late FakeServer server;
  late Dio dio;

  setUp(() async {
    setUpCore();
    sessionService = SessionService(
      const FlutterSecureStorage(),
      retryDelay: Duration.zero,
    );
    await sessionService.save(session('expired'));
    server = FakeServer('fresh');
    dio = DioManager.createDio(
      config: const NetworkConfig(baseUrl: 'https://api.test'),
      tokenStore: sessionService,
      errorConverter: const AppFailureConverter(),
      sessionRefresher: sessionService,
    )..httpClientAdapter = server;
  });

  Future<Result<int>> loadItems() => Result.guard(() async {
    final response = await dio.get<Map<String, dynamic>>('/items');
    return response.data!['items'] as int;
  });

  test('renewed: the repository gets its data and never sees the 401',
      () async {
    sessionService.refresher = FakeRefresher([session('fresh', 'refresh-2')]);

    final result = await loadItems();

    expect(result.isSuccess, isTrue);
    expect(result.data, 42);
    expect(server.requests, 2);
    expect(sessionService.session?.accessToken, 'fresh');
  });

  test('renewed on the second attempt after a network blip', () async {
    sessionService.refresher = FakeRefresher([offline, session('fresh')]);

    expect((await loadItems()).data, 42);
  });

  test('invalid_grant: the session ends and the request fails as '
      'unauthorized', () async {
    sessionService.refresher = FakeRefresher([rejected]);

    final result = await loadItems();

    expect(result.error?.type, FailureType.unauthorized);
    expect(sessionService.isAuthenticated, isFalse);
  });

  test('network down on both attempts: the session stays and the request '
      'fails as no connection', () async {
    sessionService.refresher = FakeRefresher([offline, offline]);

    final result = await loadItems();

    expect(result.error?.type, FailureType.network);
    expect(sessionService.isAuthenticated, isTrue);
  });

  test('three requests failing together renew once and all succeed',
      () async {
    final hold = gate();
    final refresher = FakeRefresher([session('fresh')], gate: hold.future);
    sessionService.refresher = refresher;

    final results = Future.wait([loadItems(), loadItems(), loadItems()]);
    await Future<void>.delayed(Duration.zero);
    hold.complete();

    expect((await results).map((r) => r.data), [42, 42, 42]);
    expect(refresher.calls, 1);
  });
}
