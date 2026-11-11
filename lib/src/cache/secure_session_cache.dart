import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_cache_store.dart';

/// Encrypted at rest: Keychain on iOS, Keystore-wrapped AES-GCM on Android.
/// Its own Keychain service and Android namespace, so clearing it, or an
/// Android reset after a key loss (resetOnError), can never touch the
/// session's tokens. *_this_device: never restored to another device.
final class SecureSessionCache extends SessionCacheStore {
  SecureSessionCache({
    required String storageKey,
    FlutterSecureStorage? storage,
    super.clock,
    super.maxEntryBytes,
  }) : _prefix = '$storageKey.cache.',
       _storage =
           storage ??
           FlutterSecureStorage(
             iOptions: IOSOptions(
               accountName: '$storageKey.cache',
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
             aOptions: AndroidOptions(storageNamespace: '$storageKey.cache'),
           );

  final String _prefix;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> load(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> store(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: '$_prefix$key');

  /// Deletes this cache's keys only. The prefix check also keeps the session
  /// keys safe where every option shares one store (`setMockInitialValues`).
  @override
  Future<void> removeAll() async {
    final all = await _storage.readAll();
    // A copy: the store may hand out its live map.
    final keys = [
      for (final key in all.keys)
        if (key.startsWith(_prefix)) key,
    ];
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }
}
