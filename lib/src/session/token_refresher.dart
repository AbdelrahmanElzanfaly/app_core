import 'auth_session.dart';

/// Exchanges a refresh token for a new session.
///
/// Declared here, implemented by the login package: renewing is a
/// conversation with the identity server, which `app_core` knows nothing
/// about. Throws on failure — an `AppFailure` with code `invalid_grant` when
/// the refresh token itself is no longer accepted.
abstract interface class TokenRefresher {
  Future<AuthSession> refresh(String refreshToken);
}
