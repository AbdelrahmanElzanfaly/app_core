import 'package:app_network/app_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../error/app_failure.dart';
import 'auth_session.dart';
import 'token_refresher.dart';

/// Owns the signed-in session: keeps it in secure storage, and tells the
/// router when it changes.
///
/// A [ChangeNotifier] so it can be a `GoRouter.refreshListenable`: signing in
/// or out re-runs the redirect, and the guard moves the user.
///
/// Also the [SessionRefresher] behind every authenticated client: a 401
/// anywhere comes here to be renewed (see [refreshAccessToken]).
class SessionService extends ChangeNotifier
    implements TokenStore, SessionRefresher {
  SessionService(
    this._storage, {
    this.retryDelay = const Duration(milliseconds: 500),
  });

  final FlutterSecureStorage _storage;

  /// The pause before the second renewal attempt.
  final Duration retryDelay;

  /// How the session is renewed. Set by the login package when it is
  /// configured; until then a 401 cannot be recovered from and ends the
  /// session.
  TokenRefresher? refresher;

  /// Attempts per renewal. Only failures that may be transient (network,
  /// timeout, server) are retried; a rejected refresh token is not.
  static const int maxRefreshAttempts = 2;

  AuthSession? _session;

  AuthSession? get session => _session;

  /// Whether a session is stored — not whether its access token is still
  /// valid. An expired access token is renewed on its first 401, so the user
  /// stays signed in for as long as the refresh token is accepted.
  bool get isAuthenticated => _session != null;

  Future<String?>? _refreshing;

  String get _prefix => '${AppConfig.instance.storageKey}.session';

  static const _keys = ['accessToken', 'refreshToken', 'expiresAt'];

  /// Loads the stored session. Run once before `runApp`, so the first frame
  /// already knows whether the user is signed in.
  Future<void> restore() async {
    final values = <String, String?>{
      for (final key in _keys) key: await _storage.read(key: '$_prefix.$key'),
    };
    _session = AuthSession.fromJson(values);
    notifyListeners();
  }

  Future<void> save(AuthSession session) async {
    await _clearStorage();
    for (final entry in session.toJson().entries) {
      await _storage.write(key: '$_prefix.${entry.key}', value: entry.value);
    }
    _session = session;
    notifyListeners();
  }

  Future<void> clear() async {
    await _clearStorage();
    _session = null;
    notifyListeners();
  }

  Future<void> _clearStorage() async {
    for (final key in _keys) {
      await _storage.delete(key: '$_prefix.$key');
    }
  }

  @override
  Future<String?> readAccessToken() async => _session?.accessToken;

  /// Renews the session after a 401.
  ///
  /// * Renewed: saves the new session and returns its access token.
  /// * Refresh token rejected (`invalid_grant`), or nothing to renew with:
  ///   ends the session — the guard takes the user to login — and returns
  ///   null.
  /// * Failed for any other reason on every attempt (no network, timeout,
  ///   server error): **keeps** the session and throws the last failure, so
  ///   the request fails as "no connection" and the next one renews again.
  ///
  /// Concurrent callers share one renewal: refresh tokens are often
  /// single-use, so a second renewal in parallel would invalidate the first.
  @override
  Future<String?> refreshAccessToken() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh() async {
    final refreshToken = _session?.refreshToken;
    final refresher = this.refresher;
    if (refreshToken == null || refresher == null) {
      await clear();
      return null;
    }

    late AppFailure lastFailure;
    for (var attempt = 1; attempt <= maxRefreshAttempts; attempt++) {
      if (attempt > 1) await Future<void>.delayed(retryDelay);
      try {
        final renewed = await refresher.refresh(refreshToken);
        await save(renewed);
        return renewed.accessToken;
      } catch (error) {
        lastFailure = AppFailure.from(error);
        if (_isRejected(lastFailure)) {
          await clear();
          return null;
        }
      }
    }
    throw lastFailure;
  }

  /// The identity server refused the refresh token itself: expired, revoked,
  /// or already used. Retrying cannot help.
  static bool _isRejected(AppFailure failure) =>
      failure.code == 'invalid_grant' ||
      failure.type == FailureType.unauthorized;
}
