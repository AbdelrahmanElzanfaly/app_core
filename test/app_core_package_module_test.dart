import 'package:app_core/app_core.dart';
import 'package:app_network/app_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show GetItHelper;

import 'support.dart';

void main() {
  late GetIt getIt;

  Future<void> register() async {
    getIt = GetIt.asNewInstance();
    await AppCorePackageModule().init(GetItHelper(getIt));
  }

  setUp(setUpCore);

  tearDown(() => getIt.reset());

  test('one NetworkMonitor is the gate and the observer', () async {
    await register();

    final monitor = getIt<NetworkMonitor>();
    expect(getIt<NetworkStatus>(), same(monitor));
    expect(getIt<ReachabilityObserver>(), same(monitor));
  });

  test(
    'the client retries, gates and reports, with a 10 s connect timeout',
    () async {
      await register();

      final dio = getIt<Dio>();

      expect(
        dio.options.connectTimeout,
        NetworkConfig.recommendedConnectTimeout,
      );
      expect(dio.options.receiveTimeout, NetworkConfig.defaultTimeout);
      expect(
        dio.interceptors.map((interceptor) => interceptor.runtimeType),
        containsAllInOrder([
          AuthInterceptor,
          RefreshTokenInterceptor,
          RetryInterceptor,
          ConnectivityInterceptor,
          ErrorHandlerInterceptor,
        ]),
      );
    },
  );

  test('offline copies stay in memory unless the app opts in', () async {
    await register();

    expect(getIt<SessionCacheStore>(), isA<MemorySessionCache>());
    expect(getIt<SessionCache>(), same(getIt<SessionCacheStore>()));
  });

  test('persistOfflineCache keeps them in secure storage', () async {
    AppConfig.initialize(
      (environment) => AppConfig(
        environment: environment,
        appName: 'test',
        baseUrl: 'https://api.test',
        applicationId: 'test',
        storageKey: 'test',
        persistOfflineCache: true,
      ),
    );
    await register();

    expect(getIt<SessionCacheStore>(), isA<SecureSessionCache>());
  });

  test('the session empties the cache when it ends', () async {
    await register();
    final sessionService = getIt<SessionService>();
    final cache = getIt<SessionCache>();
    await sessionService.save(session('access-1'));
    await cache.write('home', {'items': 42}, generation: cache.generation);
    expect(await cache.read('home'), isNotNull);

    await sessionService.clear();

    expect(await cache.read('home'), isNull);
  });
}
