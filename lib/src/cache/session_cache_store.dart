import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../session/session_scoped.dart';
import 'session_cache.dart';

/// The session rules every store follows, kept in one place: closed until a
/// session starts, emptied and closed again when it ends (a failed emptying
/// is retried before anything is read or written), and a write taken under
/// an older generation never lands. A store only says where the bytes go.
abstract base class SessionCacheStore implements SessionCache, SessionScoped {
  SessionCacheStore({
    DateTime Function()? clock,
    this.maxEntryBytes = 64 * 1024,
  }) : _clock = clock ?? DateTime.now;

  /// The largest encoded entry kept: a screen-sized snapshot, not a history.
  final int maxEntryBytes;

  /// The envelope's version: `{"v":1,"savedAt":"<iso8601 utc>","data":{...}}`.
  /// An entry of another version is unreadable, so it is deleted.
  static const int format = 1;

  final DateTime Function() _clock;
  bool _open = false;
  int _generation = 0;

  /// The last clear failed: an ended session's entries may still be stored,
  /// so nothing is read or written until a retry succeeds.
  bool _wipePending = false;

  @override
  int get generation => _generation;

  @override
  void onSessionStarted() {
    // A renewal: the store is already open, and nothing changes.
    if (_open) return;
    _open = true;
    // A generation taken while signed out belongs to no session.
    _generation++;
  }

  @override
  Future<void> onSessionEnded() async {
    // Synchronously first: a write already in flight is refused.
    _open = false;
    _generation++;
    await _wiped();
  }

  /// Whether nothing of an ended session is left, retrying a clear that
  /// failed. Until one succeeds the next session gets nothing from this
  /// store, in this run; the next launch without a session sweeps again
  /// (SessionService.restore).
  Future<bool> _wiped() async {
    try {
      await removeAll();
      _wipePending = false;
      return true;
    } catch (error) {
      _wipePending = true;
      debugPrint('[SessionCache] clear failed: $error');
      return false;
    }
  }

  @override
  Future<void> write(
    String key,
    Map<String, dynamic> json, {
    required int generation,
  }) async {
    if (!_accepts(generation)) return;
    // The session may end during the retry.
    if (_wipePending && (!await _wiped() || !_accepts(generation))) return;
    try {
      final encoded = jsonEncode({
        'v': format,
        'savedAt': _clock().toUtc().toIso8601String(),
        'data': json,
      });
      final size = utf8.encode(encoded).length;
      if (size > maxEntryBytes) {
        debugPrint(
          '[SessionCache] $key not saved: $size bytes is over the '
          '$maxEntryBytes-byte cap.',
        );
        return;
      }
      await store(key, encoded);
      // The session ended while the bytes were on their way: take them back.
      if (!_accepts(generation)) await remove(key);
    } catch (error) {
      debugPrint('[SessionCache] $key not saved: $error');
    }
  }

  @override
  Future<CachedEntry?> read(
    String key, {
    Duration maxAge = SessionCache.defaultMaxAge,
  }) async {
    // Signed out: nothing of the last user is handed out, even mid-clear.
    if (!_open) return null;
    // Nor after a clear that failed: the next user's session may be open.
    if (_wipePending && (!await _wiped() || !_open)) return null;
    try {
      final raw = await load(key);
      if (raw == null) return null;
      final entry = _decode(raw);
      if (entry != null) {
        final age = _clock().difference(entry.savedAt);
        // Saved "in the future" means the clock moved: the age is unknown.
        if (!age.isNegative && age <= maxAge) return entry;
      }
      await _forget(key);
      return null;
    } catch (error) {
      debugPrint('[SessionCache] $key not read: $error');
      return null;
    }
  }

  bool _accepts(int generation) => _open && generation == _generation;

  static CachedEntry? _decode(String raw) {
    final Object? envelope;
    try {
      envelope = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (envelope is! Map<String, dynamic> || envelope['v'] != format) {
      return null;
    }
    final savedAt = envelope['savedAt'];
    final data = envelope['data'];
    if (savedAt is! String || data is! Map<String, dynamic>) return null;
    final parsed = DateTime.tryParse(savedAt);
    return parsed == null ? null : CachedEntry(data, parsed.toUtc());
  }

  Future<void> _forget(String key) async {
    try {
      await remove(key);
    } catch (error) {
      debugPrint('[SessionCache] $key not removed: $error');
    }
  }

  /// The stored value for [key], or null.
  @protected
  Future<String?> load(String key);

  @protected
  Future<void> store(String key, String value);

  @protected
  Future<void> remove(String key);

  /// Removes every entry of this cache, and nothing else.
  @protected
  Future<void> removeAll();
}

/// Same rules, nothing on disk: offline copies last for this run only.
final class MemorySessionCache extends SessionCacheStore {
  MemorySessionCache({super.clock, super.maxEntryBytes});

  final Map<String, String> _entries = {};

  @override
  Future<String?> load(String key) async => _entries[key];

  @override
  Future<void> store(String key, String value) async => _entries[key] = value;

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> removeAll() async => _entries.clear();
}
