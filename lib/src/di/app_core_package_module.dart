import 'dart:async';

import 'package:dio/dio.dart';
import 'package:app_network/app_network.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

import '../config/app_config.dart';
import '../error/app_failure_converter.dart';
import '../session/session_service.dart';
import '../settings/app_settings_cubit.dart';

/// What `app_core` registers into an app's container.
///
/// Named in the app's `@InjectableInit(externalPackageModulesBefore: ...)`.
/// Written by hand rather than generated, so this package has no build step.
///
/// * [SessionService], also as the [TokenStore] and [SessionRefresher]
/// * [AppSettingsCubit], also as the [LocaleProvider]
/// * [NetworkErrorConverter]
/// * the unnamed [Dio], pointed at [AppConfig.baseUrl], renewing on 401
class AppCorePackageModule extends MicroPackageModule {
  @override
  FutureOr<void> init(GetItHelper gh) {
    gh.lazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
    gh.lazySingleton<SessionService>(
      () => SessionService(gh<FlutterSecureStorage>()),
    );
    gh.lazySingleton<TokenStore>(() => gh<SessionService>());
    gh.lazySingleton<SessionRefresher>(() => gh<SessionService>());
    gh.lazySingleton<AppSettingsCubit>(() => AppSettingsCubit());
    gh.lazySingleton<LocaleProvider>(() => gh<AppSettingsCubit>());
    gh.lazySingleton<NetworkErrorConverter>(() => const AppFailureConverter());
    gh.lazySingleton<Dio>(() {
      final app = AppConfig.instance;
      return DioManager.createDio(
        config: NetworkConfig(
          baseUrl: app.baseUrl,
          enableLogging: app.enableLogging,
        ),
        tokenStore: gh<TokenStore>(),
        errorConverter: gh<NetworkErrorConverter>(),
        localeProvider: gh<LocaleProvider>(),
        sessionRefresher: gh<SessionRefresher>(),
      );
    });
  }
}
