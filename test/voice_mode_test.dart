import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/voice_mode_screen.dart';

MessageWithParts _msg({
  required String id,
  required String role,
  int? completed,
  Map<String, dynamic>? error,
  String text = 'hello there',
}) {
  final time = <String, dynamic>{'created': 1};
  if (completed != null) time['completed'] = completed;
  return MessageWithParts(
    info: MessageInfo(id: id, role: role, time: time, error: error),
    parts: [
      MessagePart.fromJson({'id': 'p_$id', 'type': 'text', 'text': text}),
    ],
  );
}

void main() {
  group('replyToNarrate', () {
    test('narrates a fresh completed assistant reply', () {
      final reply = replyToNarrate(
          [_msg(id: 'a', role: 'assistant', completed: 2)], null);
      expect(reply?.info.id, 'a');
    });

    test('ignores a reply still streaming', () {
      expect(replyToNarrate([_msg(id: 'a', role: 'assistant')], null), isNull);
    });

    test('ignores an errored turn', () {
      expect(
        replyToNarrate([
          _msg(
              id: 'a',
              role: 'assistant',
              error: {'name': 'APIError', 'data': {}})
        ], null),
        isNull,
      );
    });

    test('never narrates the same reply twice', () {
      final messages = [_msg(id: 'a', role: 'assistant', completed: 2)];
      expect(replyToNarrate(messages, 'a'), isNull);
    });

    test('ignores a user message at the tail', () {
      expect(replyToNarrate([_msg(id: 'u', role: 'user')], null), isNull);
    });

    test('ignores a reply with no text parts', () {
      expect(
        replyToNarrate(
            [_msg(id: 'a', role: 'assistant', completed: 2, text: '  ')], null),
        isNull,
      );
    });

    test('an empty transcript narrates nothing', () {
      expect(replyToNarrate(const [], null), isNull);
    });
  });
}
