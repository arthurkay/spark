import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/message_bubble.dart';

void main() {
  group('unifiedEditDiff', () {
    test('returns empty for identical text', () {
      expect(unifiedEditDiff('a\nb\nc\n', 'a\nb\nc\n'), isEmpty);
    });

    test('marks a single changed line', () {
      final diff = unifiedEditDiff('one\ntwo\nthree\n', 'one\nTWO\nthree\n');
      expect(diff, contains('-two'));
      expect(diff, contains('+TWO'));
      expect(diff, contains(' one'));
      expect(diff, contains(' three'));
      expect(diff, contains('@@'));
    });

    test('marks a pure insertion', () {
      final diff = unifiedEditDiff('a\nc\n', 'a\nb\nc\n');
      expect(diff, contains('+b'));
      // Check body lines only — the hunk header legitimately contains '-'.
      final deletions =
          diff.split('\n').where((l) => l.startsWith('-')).toList();
      expect(deletions, isEmpty,
          reason: 'an insertion should not report deletions');
    });

    test('marks a pure deletion', () {
      final diff = unifiedEditDiff('a\nb\nc\n', 'a\nc\n');
      expect(diff, contains('-b'));
      expect(diff, isNot(contains('+b')));
    });

    test('handles insertion at the very start and end', () {
      expect(unifiedEditDiff('b\n', 'a\nb\n'), contains('+a'));
      expect(unifiedEditDiff('a\n', 'a\nb\n'), contains('+b'));
    });

    test('handles empty old and new text', () {
      expect(unifiedEditDiff('', 'a\n'), contains('+a'));
      expect(unifiedEditDiff('a\n', ''), contains('-a'));
      expect(unifiedEditDiff('', ''), isEmpty);
    });

    test('preserves unchanged head and tail as context', () {
      // 40 identical lines, one changed in the middle. Common-prefix/suffix
      // trimming must not lose or misalign the surrounding context.
      final head = List.generate(20, (i) => 'head$i').join('\n');
      final tail = List.generate(20, (i) => 'tail$i').join('\n');
      final oldText = '$head\nMIDDLE\n$tail\n';
      final newText = '$head\nCHANGED\n$tail\n';

      final diff = unifiedEditDiff(oldText, newText);
      expect(diff, contains('-MIDDLE'));
      expect(diff, contains('+CHANGED'));
      // Only 3 lines of context each side, so distant lines stay out of the diff.
      expect(diff, isNot(contains('head0')));
      expect(diff, isNot(contains('tail19')));
      expect(diff, contains('head19'));
      expect(diff, contains('tail0'));
    });

    test('reports correct hunk line numbers', () {
      final diff = unifiedEditDiff('a\nb\nc\nd\n', 'a\nb\nX\nd\n');
      // The change is on the 3rd line; with 3 lines of context the hunk starts
      // at line 0 and covers all 4 lines of each side.
      expect(diff, contains('@@ -0,4 +0,4 @@'));
    });

    test('degrades to block replacement instead of hanging on huge inputs', () {
      // Well past the LCS cell budget: every line differs, so no prefix/suffix
      // trimming can help. This must return promptly rather than attempting a
      // ~160000+ cell dynamic-programming table.
      final oldText = List.generate(600, (i) => 'old line $i').join('\n');
      final newText = List.generate(600, (i) => 'new line $i').join('\n');

      final sw = Stopwatch()..start();
      final diff = unifiedEditDiff(oldText, newText);
      sw.stop();

      expect(diff, contains('-old line 0'));
      expect(diff, contains('+new line 0'));
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'large diffs must not block the UI thread');
    });

    test('caches repeated calls', () {
      final oldText = List.generate(200, (i) => 'line $i').join('\n');
      final newText = oldText.replaceFirst('line 100', 'changed 100');

      final first = unifiedEditDiff(oldText, newText);
      final second = unifiedEditDiff(oldText, newText);
      expect(second, same(first),
          reason: 'a cache hit should return the identical string instance');
    });
  });
}
