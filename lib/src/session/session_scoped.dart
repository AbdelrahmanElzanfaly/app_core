/// Holds the signed-in user's data, so must not outlive the session.
///
/// Handed to `SessionService`, which starts it when a session exists and
/// ends it, before the tokens are deleted, when the session ends.
abstract interface class SessionScoped {
  /// A session exists (restored or saved). Idempotent: a token renewal
  /// calls it again and must not change anything.
  void onSessionStarted();

  /// Forget everything and refuse writes until the next start. Must not throw.
  Future<void> onSessionEnded();
}
