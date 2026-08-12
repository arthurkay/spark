import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/tts_provider.dart';

/// Walks [nextChunkEnd] from 0 and returns every chunk.
List<String> walkChunks(String text, {int max = 3500}) {
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    final end = nextChunkEnd(text, start, max: max);
    expect(end, greaterThan(start), reason: 'chunking must make progress');
    chunks.add(text.substring(start, end));
    start = end;
  }
  return chunks;
}

void main() {
  group('nextChunkEnd', () {
    test('short text is one chunk', () {
      expect(nextChunkEnd('hello world', 0), 11);
    });

    test('text exactly at the limit is one chunk', () {
      final text = 'a' * 3500;
      expect(nextChunkEnd(text, 0), 3500);
    });

    test('cuts at a sentence end when one exists past the floor', () {
      final head = '${'a' * 50}. ';
      final text = '$head${'b' * 4000}';
      final end = nextChunkEnd(text, 0, max: 100);
      expect(text.substring(0, end), head);
    });

    test('prefers the latest sentence end in the window', () {
      final text = '${'a' * 30}. ${'b' * 30}. ${'c' * 4000}';
      final end = nextChunkEnd(text, 0, max: 100);
      // Both boundaries are past the floor; the later one wins.
      expect(text.substring(0, end), '${'a' * 30}. ${'b' * 30}. ');
    });

    test('falls back to a word boundary without sentence ends', () {
      final words = List.generate(100, (i) => 'word$i').join(' ');
      final end = nextChunkEnd(words, 0, max: 200);
      expect(end, lessThanOrEqualTo(200));
      expect(words[end - 1], ' ', reason: 'should cut after a space');
    });

    test('hard-cuts unbroken text at the limit', () {
      final text = 'x' * 10000;
      expect(nextChunkEnd(text, 0, max: 3500), 3500);
    });

    test('ignores a boundary too close to the start', () {
      // A sentence end in the first quarter would degenerate into tiny chunks.
      final text = 'Hi. ${'y' * 5000}';
      final end = nextChunkEnd(text, 0, max: 1000);
      expect(end, 1000, reason: 'should hard-cut, not stop at "Hi. "');
    });

    test('every chunk stays under the limit', () {
      final text = List.generate(400, (i) => 'Sentence number $i.').join(' ');
      for (final chunk in walkChunks(text, max: 500)) {
        expect(chunk.length, lessThanOrEqualTo(500));
      }
    });

    test('chunks reassemble to exactly the original text', () {
      final text = List.generate(300, (i) => 'Sentence number $i!').join(' ');
      expect(walkChunks(text, max: 400).join(), text);
    });

    test('a realistic long narration chunks at sentence seams', () {
      final text = List.generate(
        60,
        (i) => 'This is spoken sentence $i, with a bit of length to it.',
      ).join(' ');
      final chunks = walkChunks(text, max: 800);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks.sublist(0, chunks.length - 1)) {
        expect(chunk.trimRight(), endsWith('.'),
            reason: 'seams should land on sentence ends');
      }
      expect(chunks.join(), text);
    });
  });
}
