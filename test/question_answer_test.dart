import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/message_bubble.dart';

void main() {
  group('buildQuestionAnswer', () {
    test('a picked option is sent on its own', () {
      expect(
        buildQuestionAnswer(
          selectedLabels: ['OAuth'],
          customSelected: false,
          customText: '',
        ),
        ['OAuth'],
      );
    });

    test('a typed answer replaces the label for single-select', () {
      // Selecting "Other…" clears the selection, so only the text remains.
      expect(
        buildQuestionAnswer(
          selectedLabels: const [],
          customSelected: true,
          customText: 'Session cookies via Redis',
        ),
        ['Session cookies via Redis'],
      );
    });

    test('typed answer is trimmed', () {
      expect(
        buildQuestionAnswer(
          selectedLabels: const [],
          customSelected: true,
          customText: '  spaces around  ',
        ),
        ['spaces around'],
      );
    });

    test('multi-select sends labels and the typed answer together', () {
      expect(
        buildQuestionAnswer(
          selectedLabels: ['OAuth', 'JWT'],
          customSelected: true,
          customText: 'and mTLS',
        ),
        ['OAuth', 'JWT', 'and mTLS'],
      );
    });

    test('a blank typed answer is dropped, not sent as an empty string', () {
      expect(
        buildQuestionAnswer(
          selectedLabels: ['OAuth'],
          customSelected: true,
          customText: '   ',
        ),
        ['OAuth'],
      );
    });

    test('nothing chosen yields an empty answer, which blocks submit', () {
      expect(
        buildQuestionAnswer(
          selectedLabels: const [],
          customSelected: true,
          customText: '',
        ),
        isEmpty,
      );
      expect(
        buildQuestionAnswer(
          selectedLabels: const [],
          customSelected: false,
          customText: 'ignored while unselected',
        ),
        isEmpty,
      );
    });
  });
}
