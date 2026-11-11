/// A saved copy and when it was saved.
class CachedEntry {
  const CachedEntry(this.json, this.savedAt);

  final Map<String, dynamic> json;

  /// UTC.
  final DateTime savedAt;
}

/// Small read models a screen may show while offline: screen-sized
/// snapshots (kilobytes), never writes, payments or secrets. Emptied when
/// the session ends.
abstract interface class SessionCache {
  static const Duration defaultMaxAge = Duration(hours: 24);

  /// Take before a request starts and pass to [write]: a write carrying an
  /// older generation (the session ended, or another started, meanwhile) is
  /// dropped.
  int get generation;

  /// Null when absent, older than [maxAge], unreadable or of another format
  /// (those are deleted). Never throws.
  Future<CachedEntry?> read(
    String key, {
    Duration maxAge = SessionCache.defaultMaxAge,
  });

  /// Never throws. Ignored while signed out, for a stale [generation], or
  /// above the size cap.
  Future<void> write(
    String key,
    Map<String, dynamic> json, {
    required int generation,
  });
}
