import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    setUpCore();
    now = DateTime.utc(2026, 11, 11, 9);
  });

  const summary = {
    'totalItems': 42,
    'alerts': [
      {'itemId': 'a-1', 'onHand': 3},
    ],
  };

  final stores = <String, SessionCacheStore Function()>{
    'MemorySessionCache': () => MemorySessionCache(clock: clock),
    'SecureSessionCache':
        () => SecureSessionCache(storageKey: 'test', clock: clock),
  };

  for (final MapEntry(key: name, value: create) in stores.entries) {
    group(name, () {
      late SessionCacheStore cache;

      setUp(() => cache = create());

      Future<void> save(String key, Map<String, dynamic> json) =>
          cache.write(key, json, generation: cache.generation);

      test('round trip, with savedAt from the clock', () async {
        cache.onSessionStarted();
        await save('home', summary);
        now = now.add(const Duration(hours: 1));

        final entry = await cache.read('home');

        expect(entry?.json, summary);
        expect(entry?.savedAt, DateTime.utc(2026, 11, 11, 9));
        expect(entry?.savedAt.isUtc, isTrue);
      });

      test('absent: null', () async {
        cache.onSessionStarted();

        expect(await cache.read('home'), isNull);
      });

      test('older than maxAge: null, and deleted', () async {
        cache.onSessionStarted();
        await save('home', summary);

        now = now.add(const Duration(hours: 12));
        expect(
          await cache.read('home', maxAge: const Duration(hours: 12)),
          isNotNull,
          reason: 'exactly maxAge old is still served',
        );

        now = now.add(const Duration(seconds: 1));
        expect(
          await cache.read('home', maxAge: const Duration(hours: 12)),
          isNull,
        );
        expect(await _raw(cache, 'home'), isNull);
        expect(await cache.read('home'), isNull, reason: 'deleted, not hidden');
      });

      test('saved "in the future" (the clock moved back): null', () async {
        cache.onSessionStarted();
        await save('home', summary);

        now = now.subtract(const Duration(minutes: 5));

        expect(await cache.read('home'), isNull);
        expect(await _raw(cache, 'home'), isNull);
      });

      for (final (label, raw) in [
        ('corrupt JSON', '{"v":1,"savedAt":'),
        (
          'another format version',
          '{"v":2,"savedAt":"2026-11-11T09:00:00.000Z","data":{}}',
        ),
        ('no envelope', '{"totalItems":42}'),
        ('not an object', '[1,2,3]'),
        ('a bad savedAt', '{"v":1,"savedAt":"yesterday","data":{}}'),
        (
          'data that is not an object',
          '{"v":1,"savedAt":"2026-11-11T09:00:00.000Z","data":[1]}',
        ),
      ]) {
        test('$label: null, and deleted', () async {
          cache.onSessionStarted();
          await _plant(cache, 'home', raw);

          expect(await cache.read('home'), isNull);
          expect(await _raw(cache, 'home'), isNull);
        });
      }

      test('writes are ignored before onSessionStarted', () async {
        await save('home', summary);
        cache.onSessionStarted();

        expect(await cache.read('home'), isNull);
        expect(await _raw(cache, 'home'), isNull);
      });

      test('a write whose generation was taken before onSessionEnded is '
          'dropped, even after a later onSessionStarted', () async {
        cache.onSessionStarted();
        final before = cache.generation;

        await cache.onSessionEnded();
        cache.onSessionStarted();
        await cache.write('home', summary, generation: before);

        expect(await cache.read('home'), isNull);

        await save('home', summary);
        expect(await cache.read('home'), isNotNull, reason: 'a fresh one is');
      });

      test('a write whose generation was taken while signed out is dropped '
          'after the next onSessionStarted', () async {
        cache.onSessionStarted();
        await cache.onSessionEnded();
        // Taken during sign-out, with the last user's token still in hand.
        final whileOut = cache.generation;

        cache.onSessionStarted();
        await cache.write('home', summary, generation: whileOut);

        expect(await cache.read('home'), isNull);
        expect(await _raw(cache, 'home'), isNull);
      });

      test('onSessionEnded empties the cache and refuses reads and writes '
          'until the next start', () async {
        cache.onSessionStarted();
        await save('home', summary);
        await save('cards', summary);

        await cache.onSessionEnded();
        expect(await cache.read('home'), isNull);
        await save('home', summary);

        cache.onSessionStarted();
        expect(await cache.read('home'), isNull);
        expect(await cache.read('cards'), isNull);
      });

      test('onSessionStarted again (a renewal) keeps entries and the '
          'generation', () async {
        cache.onSessionStarted();
        await save('home', summary);
        final generation = cache.generation;

        cache.onSessionStarted();

        expect(cache.generation, generation);
        expect(await cache.read('home'), isNotNull);
      });

      test('over 64 KiB: not written; just under: written', () async {
        cache.onSessionStarted();

        await save('big', {'blob': 'x' * (64 * 1024)});
        await save('fits', {'blob': 'x' * (63 * 1024)});

        expect(await cache.read('big'), isNull);
        expect(await _raw(cache, 'big'), isNull);
        expect(await cache.read('fits'), isNotNull);
      });

      test('write never throws', () async {
        cache.onSessionStarted();

        await expectLater(
          save('home', {'when': DateTime.utc(2026)}),
          completes,
          reason: 'not JSON-encodable',
        );
        expect(await cache.read('home'), isNull);
      });
    });
  }

  group('SessionCacheStore', () {
    test(
      'a write still on its way when the session ends is taken back',
      () async {
        final cache = _SlowStore(clock: clock)..onSessionStarted();

        final pending = cache.write(
          'home',
          summary,
          generation: cache.generation,
        );
        await cache.onSessionEnded();
        cache.held.complete();
        await pending;

        expect(cache.entries, isEmpty);
      },
    );

    test('a store that fails: write and read never throw, and '
        'onSessionEnded still closes the cache', () async {
      final cache = _FailingStore(clock: clock)..onSessionStarted();
      final opened = cache.generation;

      await expectLater(
        cache.write('home', summary, generation: cache.generation),
        completes,
      );
      expect(await cache.read('home'), isNull);
      await expectLater(cache.onSessionEnded(), completes);
      expect(cache.generation, greaterThan(opened));
    });
  });

  test('a store whose clear failed hands out nothing while signed out, and '
      'takes no writes', () async {
    final cache = _StickyStore(clock: clock)..onSessionStarted();
    await cache.write('home', summary, generation: cache.generation);

    await cache.onSessionEnded();
    expect(cache.entries, isNotEmpty, reason: 'the clear failed');

    expect(await cache.read('home'), isNull);
    await cache.write('cards', summary, generation: cache.generation);
    expect(cache.entries.keys, ['home']);
  });

  test('after a failed clear, the next session in the same run reads and '
      'writes nothing until a retried clear succeeds', () async {
    final cache = _StickyStore(clock: clock)..onSessionStarted();
    await cache.write('home', summary, generation: cache.generation);
    await cache.onSessionEnded();

    cache.onSessionStarted();
    expect(await cache.read('home'), isNull, reason: "the last user's copy");
    await cache.write('cards', summary, generation: cache.generation);
    expect(cache.entries.keys, ['home']);

    cache.sticky = false;
    expect(await cache.read('home'), isNull);
    expect(cache.entries, isEmpty, reason: 'swept before reading');
    await cache.write('cards', summary, generation: cache.generation);
    expect(await cache.read('cards'), isNotNull);
  });

  group('SecureSessionCache', () {
    test('keeps entries under its own prefix', () async {
      final cache = SecureSessionCache(storageKey: 'test', clock: clock)
        ..onSessionStarted();

      await cache.write('home', summary, generation: cache.generation);

      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.keys, ['test.cache.home']);
    });

    test('onSessionEnded deletes only test.cache. keys and leaves the '
        'session keys', () async {
      FlutterSecureStorage.setMockInitialValues({
        'test.session.accessToken': 'access-1',
        'test.session.refreshToken': 'refresh-1',
        'other.cache.home': 'another flavor',
      });
      final cache = SecureSessionCache(storageKey: 'test', clock: clock)
        ..onSessionStarted();
      await cache.write('home', summary, generation: cache.generation);
      await cache.write('cards', summary, generation: cache.generation);

      await cache.onSessionEnded();

      final stored = await const FlutterSecureStorage().readAll();
      expect(stored, {
        'test.session.accessToken': 'access-1',
        'test.session.refreshToken': 'refresh-1',
        'other.cache.home': 'another flavor',
      });
    });
  });
}

/// What the store holds for [key], envelope and all.
// The store's own seam, used here to look beneath the session rules.
// ignore: invalid_use_of_protected_member
Future<String?> _raw(SessionCacheStore cache, String key) => cache.load(key);

/// Puts [raw] where the store keeps [key], bypassing the envelope.
Future<void> _plant(SessionCacheStore cache, String key, String raw) =>
// ignore: invalid_use_of_protected_member
cache.store(key, raw);

/// Holds every store until [held] completes: bytes still on their way to
/// disk when the session ends.
final class _SlowStore extends SessionCacheStore {
  _SlowStore({super.clock});

  final Map<String, String> entries = {};
  final Completer<void> held = Completer();

  @override
  Future<String?> load(String key) async => entries[key];

  @override
  Future<void> store(String key, String value) async {
    await held.future;
    entries[key] = value;
  }

  @override
  Future<void> remove(String key) async => entries.remove(key);

  @override
  Future<void> removeAll() async => entries.clear();
}

/// Storage that is unavailable: every call throws.
final class _FailingStore extends SessionCacheStore {
  _FailingStore({super.clock});

  @override
  Future<String?> load(String key) => throw StateError('locked');

  @override
  Future<void> store(String key, String value) => throw StateError('locked');

  @override
  Future<void> remove(String key) => throw StateError('locked');

  @override
  Future<void> removeAll() => throw StateError('locked');
}

/// Storage whose bulk delete fails while [sticky]: entries outlive a
/// sign-out.
final class _StickyStore extends SessionCacheStore {
  _StickyStore({super.clock});

  final Map<String, String> entries = {};
  bool sticky = true;

  @override
  Future<String?> load(String key) async => entries[key];

  @override
  Future<void> store(String key, String value) async => entries[key] = value;

  @override
  Future<void> remove(String key) async => entries.remove(key);

  @override
  Future<void> removeAll() async {
    if (sticky) throw StateError('locked');
    entries.clear();
  }
}
