import 'dart:async';

import 'package:dio/dio.dart';
import 'package:app_network/app_network.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

import '../cache/secure_session_cache.dart';
import '../cache/session_cache.dart';
import '../cache/session_cache_store.dart';
import '../config/app_config.dart';
import '../error/app_failure_converter.dart';
import '../network/network_interfaces.dart';
import '../network/network_monitor.dart';
import '../session/session_service.dart';
import '../settings/app_settings_cubit.dart';

/// What `app_core` registers into an app's container.
///
/// Named in the app's `@InjectableInit(externalPackageModulesBefore: ...)`.
/// Written by hand rather than generated, so this package has no build step.
///
/// * [SessionService], also as the [TokenStore] and [SessionRefresher]
/// * [SessionCache], in memory or, with [AppConfig.persistOfflineCache], in
///   secure storage; emptied by [SessionService] when the session ends
/// * [NetworkMonitor], also as the [NetworkStatus], [ReachabilityObserver]
///   and [ServiceObserver]; the app sets [NetworkMonitor.probe] and calls
///   [NetworkMonitor.start] in `main()`
/// * [AppSettingsCubit], also as the [LocaleProvider]
/// * [NetworkErrorConverter]
/// * the unnamed [Dio], pointed at [AppConfig.baseUrl], renewing on 401,
///   retrying safe requests, and failing fast while the device is offline
class AppCorePackageModule extends MicroPackageModule {
  @override
  FutureOr<void> init(GetItHelper gh) {
    gh.lazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
    gh.lazySingleton<SessionCacheStore>(() {
      final app = AppConfig.instance;
      return app.persistOfflineCache
          ? SecureSessionCache(storageKey: app.storageKey)
          : MemorySessionCache();
    });
    gh.lazySingleton<SessionCache>(() => gh<SessionCacheStore>());
    gh.lazySingleton<SessionService>(
      () => SessionService(
        gh<FlutterSecureStorage>(),
        scoped: [gh<SessionCacheStore>()],
      ),
    );
    gh.lazySingleton<TokenStore>(() => gh<SessionService>());
    gh.lazySingleton<SessionRefresher>(() => gh<SessionService>());
    gh.lazySingleton<NetworkMonitor>(
      () => NetworkMonitor(ConnectivityPlusInterfaces()),
      dispose: (monitor) => monitor.dispose(),
    );
    gh.lazySingleton<NetworkStatus>(() => gh<NetworkMonitor>());
    gh.lazySingleton<ReachabilityObserver>(() => gh<NetworkMonitor>());
    gh.lazySingleton<ServiceObserver>(() => gh<NetworkMonitor>());
    gh.lazySingleton<AppSettingsCubit>(() => AppSettingsCubit());
    gh.lazySingleton<LocaleProvider>(() => gh<AppSettingsCubit>());
    gh.lazySingleton<NetworkErrorConverter>(() => const AppFailureConverter());
    gh.lazySingleton<Dio>(() {
      final app = AppConfig.instance;
      return DioManager.createDio(
        config: NetworkConfig(
          baseUrl: app.baseUrl,
          enableLogging: app.enableLogging,
          // Fails dead Wi-Fi in 10 s instead of 30; reads keep 30 s.
          connectTimeout: NetworkConfig.recommendedConnectTimeout,
          // GET/HEAD/OPTIONS only: writes are never resent.
          retryPolicy: const RetryPolicy(),
        ),
        tokenStore: gh<TokenStore>(),
        errorConverter: gh<NetworkErrorConverter>(),
        localeProvider: gh<LocaleProvider>(),
        sessionRefresher: gh<SessionRefresher>(),
        networkStatus: gh<NetworkStatus>(),
        reachabilityObserver: gh<ReachabilityObserver>(),
        serviceObserver: gh<ServiceObserver>(),
      );
    });
  }
}
