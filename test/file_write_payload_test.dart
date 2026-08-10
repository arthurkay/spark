import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/files/file_write_service.dart';

void main() {
  group('wrapBase64Lines', () {
    test('returns empty for empty input', () {
      expect(wrapBase64Lines(''), '');
    });

    test('wraps at the requested width and terminates every line', () {
      final wrapped = wrapBase64Lines('a' * 10, width: 4);
      expect(wrapped, 'aaaa\naaaa\naa\n');
    });

    test('round-trips content of every length through base64', () {
      for (final length in [1, 2, 3, 75, 76, 77, 4096, 20001]) {
        final content = 'x' * length;
        final wrapped = wrapBase64Lines(base64Encode(utf8.encode(content)));
        expect(
          utf8.decode(base64Decode(wrapped.replaceAll('\n', ''))),
          content,
          reason: 'length $length',
        );
      }
    });

    test('no line exceeds the TTY-safe width', () {
      final wrapped =
          wrapBase64Lines(base64Encode(utf8.encode('y' * 50000)), width: 76);
      for (final line in wrapped.split('\n')) {
        expect(line.length, lessThanOrEqualTo(76));
      }
    });

    test('preserves multi-byte content exactly', () {
      const content = 'héllo 🌍\r\nno trailing newline';
      final wrapped = wrapBase64Lines(base64Encode(utf8.encode(content)));
      expect(utf8.decode(base64Decode(wrapped.replaceAll('\n', ''))), content);
    });
  });

  group('chunkPayload', () {
    test('returns nothing for empty input', () {
      expect(chunkPayload(''), isEmpty);
    });

    test('chunks end on line boundaries and stay under the limit', () {
      final payload = wrapBase64Lines('z' * 5000, width: 76);
      final chunks = chunkPayload(payload, maxBytes: 512);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.endsWith('\n'), isTrue);
        expect(chunk.length, lessThanOrEqualTo(512 + 77));
      }
      expect(chunks.join(), payload);
    });

    test('emits an over-long line on its own rather than splitting it', () {
      final chunks = chunkPayload('${'q' * 100}\n', maxBytes: 10);
      expect(chunks, ['${'q' * 100}\n']);
    });
  });

  group('MarkerTail', () {
    final marker = RegExp(r'SPARK_FW_DONE:abc:(-?\d+):(\d+)');

    test('matches a marker split across two appends', () {
      final tail = MarkerTail()
        ..append('noise SPARK_FW_DO')
        ..append('NE:abc:0:1234\r\n');
      final match = tail.match(marker);
      expect(match?.group(1), '0');
      expect(match?.group(2), '1234');
    });

    test('still matches after the tail has overflowed capacity', () {
      final tail = MarkerTail(capacity: 128);
      for (var i = 0; i < 200; i++) {
        tail.append('junk output line $i\r\n');
      }
      expect(tail.match(marker), isNull);
      tail.append('SPARK_FW_DONE:abc:1:0\r\n');
      expect(tail.match(marker)?.group(1), '1');
    });

    test('drops content beyond capacity', () {
      final tail = MarkerTail(capacity: 16)..append('a' * 100);
      expect(tail.snippet().length, 16);
    });

    test('snippet is bounded', () {
      final tail = MarkerTail()..append('b' * 4096);
      expect(tail.snippet(64), 'b' * 64);
    });
  });

  group('path and quoting helpers', () {
    test('absolute paths are used as-is', () {
      expect(debugResolveTargetPath('/etc/hosts', '/home/me'), '/etc/hosts');
    });

    test('relative paths are joined to the directory', () {
      expect(debugResolveTargetPath('lib/main.dart', '/home/me/app'),
          '/home/me/app/lib/main.dart');
    });

    test('a trailing slash on the directory is not doubled', () {
      expect(debugResolveTargetPath('a.txt', '/home/me/'), '/home/me/a.txt');
    });

    test('a missing directory leaves the path relative', () {
      expect(debugResolveTargetPath('a.txt', null), 'a.txt');
      expect(debugResolveTargetPath('a.txt', ''), 'a.txt');
    });

    test('quoting survives embedded single quotes', () {
      expect(debugShellQuote("it's"), r"'it'\''s'");
      expect(debugShellQuote('plain'), "'plain'");
      expect(debugShellQuote(r'$HOME `id` "x"'), '\'\$HOME `id` "x"\'');
    });
  });
}
