/// Whether the app can talk to its servers.
enum NetworkReachability {
  /// No evidence of a problem. Also the answer whenever nothing is known.
  online,

  /// The device reports no network interface.
  offline,

  /// An interface is up, but the last request got no answer.
  unreachable,
}
