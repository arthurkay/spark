import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/storage/cache_service.dart';

void main() {
  group('cacheFirstThenFetch', () {
    test('cache hit: serves stale immediately, then fresh', () async {
      final emissions = await cacheFirstThenFetch<String>(
        readCache: () async => ['stale'],
        fetch: () async => ['fresh'],
      ).toList();
      expect(emissions, [
        ['stale'],
        ['fresh'],
      ]);
    });

    test('cache hit + network failure: stale stands, no error', () async {
      final emissions = await cacheFirstThenFetch<String>(
        readCache: () async => ['stale'],
        fetch: () async => throw Exception('offline'),
      ).toList();
      expect(emissions, [
        ['stale'],
      ]);
    });

    test('no cache + network failure: the error surfaces', () async {
      expect(
        cacheFirstThenFetch<String>(
          readCache: () async => null,
          fetch: () async => throw Exception('offline'),
        ).toList(),
        throwsException,
      );
    });

    test('no cache + network success: one emission', () async {
      final emissions = await cacheFirstThenFetch<String>(
        readCache: () async => null,
        fetch: () async => ['fresh'],
      ).toList();
      expect(emissions, [
        ['fresh'],
      ]);
    });

    test('an empty cached list counts as no cache', () async {
      expect(
        cacheFirstThenFetch<String>(
          readCache: () async => [],
          fetch: () async => throw Exception('offline'),
        ).toList(),
        throwsException,
      );
    });

    test('a corrupt cache read never blocks the network path', () async {
      final emissions = await cacheFirstThenFetch<String>(
        readCache: () async => throw StateError('corrupt'),
        fetch: () async => ['fresh'],
      ).toList();
      expect(emissions, [
        ['fresh'],
      ]);
    });
  });
}
