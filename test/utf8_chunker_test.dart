import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spark/shared/utf8_chunker.dart';

void main() {
  group('splitTrailingIncompleteUtf8', () {
    test('passes through pure ASCII', () {
      final bytes = utf8.encode('hello world');
      final split = splitTrailingIncompleteUtf8(bytes);
      expect(split.complete, bytes);
      expect(split.incomplete, isEmpty);
    });

    test('passes through a buffer ending on a complete sequence', () {
      final bytes = utf8.encode('héllo — 🎉');
      final split = splitTrailingIncompleteUtf8(bytes);
      expect(utf8.decode(split.complete), 'héllo — 🎉');
      expect(split.incomplete, isEmpty);
    });

    test('holds back a split 2-byte sequence', () {
      final full = utf8.encode('é'); // 2 bytes
      final bytes = [...utf8.encode('ok'), full.first];
      final split = splitTrailingIncompleteUtf8(bytes);
      expect(utf8.decode(split.complete), 'ok');
      expect(split.incomplete, [full.first]);
    });

    test('holds back a split 4-byte emoji at every boundary', () {
      final emoji = utf8.encode('🎉');
      expect(emoji.length, 4);
      for (var keep = 1; keep < 4; keep++) {
        final bytes = [...utf8.encode('x'), ...emoji.take(keep)];
        final split = splitTrailingIncompleteUtf8(bytes);
        expect(utf8.decode(split.complete), 'x',
            reason: 'with $keep of 4 emoji bytes present');
        expect(split.incomplete, emoji.take(keep).toList());
      }
    });

    test('reassembles across two chunks without replacement chars', () {
      // Simulates two WebSocket frames splitting an emoji.
      final all = utf8.encode('a🎉b');
      final firstFrame = all.sublist(0, 3); // 'a' + 2 of 4 emoji bytes
      final secondFrame = all.sublist(3);

      final pending = <int>[];
      final out = StringBuffer();

      pending.addAll(firstFrame);
      var split = splitTrailingIncompleteUtf8(List.of(pending));
      pending
        ..clear()
        ..addAll(split.incomplete);
      if (split.complete.isNotEmpty) out.write(utf8.decode(split.complete));

      pending.addAll(secondFrame);
      split = splitTrailingIncompleteUtf8(List.of(pending));
      pending
        ..clear()
        ..addAll(split.incomplete);
      if (split.complete.isNotEmpty) out.write(utf8.decode(split.complete));

      expect(out.toString(), 'a🎉b');
      expect(pending, isEmpty);
      expect(out.toString().contains('�'), isFalse);
    });

    test('handles empty input', () {
      final split = splitTrailingIncompleteUtf8(const []);
      expect(split.complete, isEmpty);
      expect(split.incomplete, isEmpty);
    });

    test('does not hold back malformed data indefinitely', () {
      // Continuation bytes with no lead byte: nothing can complete these, so
      // they must be passed through rather than buffered forever.
      final split = splitTrailingIncompleteUtf8(const [0x80, 0x80]);
      expect(split.complete, const [0x80, 0x80]);
      expect(split.incomplete, isEmpty);
    });
  });
}
