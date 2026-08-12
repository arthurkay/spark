import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/tts_cache.dart';

void main() {
  group('NarrationCache.keyFor', () {
    test('the same message and text always map to the same key', () {
      expect(
        NarrationCache.keyFor('msg_1', 'hello there'),
        NarrationCache.keyFor('msg_1', 'hello there'),
      );
    });

    test('different messages never share a key', () {
      expect(
        NarrationCache.keyFor('msg_1', 'same text'),
        isNot(NarrationCache.keyFor('msg_2', 'same text')),
      );
    });

    test('a message whose text grew gets a new key', () {
      // Narration started mid-stream must not be served for the finished
      // message — the text it was generated from was shorter.
      final partial = NarrationCache.keyFor('msg_1', 'The answer is');
      final complete = NarrationCache.keyFor('msg_1', 'The answer is 42.');
      expect(partial, isNot(complete));
    });

    test('the key is stable across runs, not a Dart hashCode', () {
      // Pinned so a future refactor can't silently invalidate every stored
      // narration by swapping the hash.
      expect(NarrationCache.keyFor('msg_abc', 'hello'), 'msg_abc:4f9f2cab');
    });

    test('keys carry the message id verbatim', () {
      expect(
        NarrationCache.keyFor('msg_xyz', 'anything').startsWith('msg_xyz:'),
        isTrue,
      );
    });

    test('empty text still yields a usable key', () {
      expect(NarrationCache.keyFor('msg_1', ''), startsWith('msg_1:'));
    });
  });

  group('NarrationCacheStats.sizeLabel', () {
    test('bytes', () {
      expect(
          const NarrationCacheStats(count: 1, bytes: 512).sizeLabel, '512 B');
    });

    test('kilobytes', () {
      expect(
        const NarrationCacheStats(count: 1, bytes: 4096).sizeLabel,
        '4 KB',
      );
    });

    test('megabytes', () {
      expect(
        const NarrationCacheStats(count: 1, bytes: 2 * 1024 * 1024).sizeLabel,
        '2.0 MB',
      );
    });
  });
}
