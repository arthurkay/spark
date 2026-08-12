import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/chat_screen.dart';

void main() {
  group('transcriptIdForRow', () {
    // The transcript list is reverse: true, so list row 0 is painted at the
    // bottom of the screen and must therefore be the newest message.
    const ids = ['oldest', 'middle', 'newest'];

    test('row 0 is the newest message', () {
      expect(transcriptIdForRow(ids, 0), 'newest');
    });

    test('rows walk backwards through history', () {
      expect(transcriptIdForRow(ids, 1), 'middle');
      expect(transcriptIdForRow(ids, 2), 'oldest');
    });

    test('the row past the oldest is the header slot', () {
      expect(transcriptIdForRow(ids, 3), isNull);
      expect(transcriptIdForRow(ids, 99), isNull);
    });

    test('negative rows are not ids', () {
      expect(transcriptIdForRow(ids, -1), isNull);
    });

    test('an empty transcript has no rows', () {
      expect(transcriptIdForRow(const [], 0), isNull);
    });

    test('a single message is both newest and oldest', () {
      expect(transcriptIdForRow(const ['only'], 0), 'only');
      expect(transcriptIdForRow(const ['only'], 1), isNull);
    });

    test('every row maps to a distinct id, newest first', () {
      final walked = [
        for (var row = 0; row < ids.length; row++)
          transcriptIdForRow(ids, row)!,
      ];
      expect(walked, ['newest', 'middle', 'oldest']);
      expect(walked.toSet().length, ids.length);
    });

    test('loading older messages does not disturb the newest rows', () {
      // Older ids are prepended. In a reversed list they land at the far end,
      // so the low rows — the ones on screen — must not shift.
      const withOlder = ['ancient', 'older', ...ids];
      expect(transcriptIdForRow(withOlder, 0), 'newest');
      expect(transcriptIdForRow(withOlder, 1), 'middle');
      expect(transcriptIdForRow(withOlder, 2), 'oldest');
      expect(transcriptIdForRow(withOlder, 3), 'older');
      expect(transcriptIdForRow(withOlder, 4), 'ancient');
    });
  });
}
