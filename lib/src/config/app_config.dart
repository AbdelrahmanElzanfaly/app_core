import 'package:flutter/foundation.dart';

/// The backends an app can be built against.
enum Environment { dev, qa, staging, prod }

/// The app's configuration for the flavor it was built with.
///
/// Set once, first thing in `main()`, through [initialize]; [instance] throws
/// until then, so nothing can read configuration that does not exist yet.
class AppConfig {
  const AppConfig({
    required this.environment,
    required this.appName,
    required this.baseUrl,
    required this.applicationId,
    required this.storageKey,
    this.portalUrl = '',
    this.enableLogging = false,
    this.enableAnalytics = false,
    this.enableRemoteConfig = false,
    this.enableDeviceSecurity = false,
    this.apiKey = '',
    this.googleMapsApiKey = '',
    this.persistOfflineCache = false,
  });

  final Environment environment;
  final String appName;
  final String baseUrl;
  final String portalUrl;
  final String applicationId;
  final bool enableLogging;
  final bool enableAnalytics;
  final bool enableRemoteConfig;
  final bool enableDeviceSecurity;

  /// Prefix for everything this app persists, so two flavors on one device
  /// never read each other's data.
  final String storageKey;
  final String apiKey;
  final String googleMapsApiKey;

  /// Whether a screen's offline copy is kept on disk (encrypted, this device
  /// only) or only in memory for this run. Storing account data on the device
  /// is a security and compliance decision, so it is off unless the app says so.
  final bool persistOfflineCache;

  static AppConfig? _instance;

  static AppConfig get instance =>
      _instance ??
      (throw StateError(
        'AppConfig.initialize() has not run. Call it first in main().',
      ));

  /// Builds the configuration for the flavor from `--dart-define=FLAVOR=...`,
  /// falling back to `prod` in release builds and `dev` otherwise.
  static void initialize(AppConfig Function(Environment environment) build) {
    _instance = build(_flavor());
  }

  static Environment _flavor() {
    const flavor = String.fromEnvironment('FLAVOR');
    for (final environment in Environment.values) {
      if (environment.name == flavor) return environment;
    }
    return kReleaseMode ? Environment.prod : Environment.dev;
  }
}
