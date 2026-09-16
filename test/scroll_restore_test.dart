import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/chat_screen.dart';

void main() {
  group('isNearBottom', () {
    test('returns true when at the very bottom', () {
      expect(isNearBottom(1000, 1000), isTrue);
    });

    test('returns true when within threshold of bottom', () {
      expect(isNearBottom(881, 1000), isTrue);
    });

    test('returns false when more than threshold away from bottom', () {
      expect(isNearBottom(880, 1000), isFalse);
    });

    test('returns false when scrolled near the top', () {
      expect(isNearBottom(0, 1000), isFalse);
    });

    test('returns true for zero maxScrollExtent (empty list)', () {
      expect(isNearBottom(0, 0), isTrue);
    });
  });

  group('decideScrollRestore', () {
    test('waitForLayout when maxScrollExtent is zero', () {
      expect(
        decideScrollRestore(savedPosition: 42.0, maxScrollExtent: 0),
        ScrollRestoreDecision.waitForLayout,
      );
    });

    test('waitForLayout when maxScrollExtent is negative', () {
      expect(
        decideScrollRestore(savedPosition: null, maxScrollExtent: -1),
        ScrollRestoreDecision.waitForLayout,
      );
    });

    test('jumpToPosition when saved position is positive', () {
      expect(
        decideScrollRestore(savedPosition: 500.0, maxScrollExtent: 1000),
        ScrollRestoreDecision.jumpToPosition,
      );
    });

    test('scrollToBottom when saved position is zero', () {
      expect(
        decideScrollRestore(savedPosition: 0, maxScrollExtent: 1000),
        ScrollRestoreDecision.scrollToBottom,
      );
    });

    test('scrollToBottom when saved position is negative (was at bottom)', () {
      expect(
        decideScrollRestore(savedPosition: -1, maxScrollExtent: 1000),
        ScrollRestoreDecision.scrollToBottom,
      );
    });

    test('scrollToBottom when saved position is null', () {
      expect(
        decideScrollRestore(savedPosition: null, maxScrollExtent: 1000),
        ScrollRestoreDecision.scrollToBottom,
      );
    });
  });

  group('scrollKey', () {
    test('prefixed with chat_ and session id', () {
      expect(scrollKey('abc123'), 'chat_abc123');
    });

    test('handles empty session id', () {
      expect(scrollKey(''), 'chat_');
    });
  });
}
