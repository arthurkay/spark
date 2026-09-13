import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/chat_provider.dart';

MessageWithParts _msg({
  required String role,
  int? completed,
  List<MessagePart> parts = const [],
}) {
  final time = <String, dynamic>{'created': 1};
  if (completed != null) time['completed'] = completed;
  return MessageWithParts(
    info: MessageInfo(id: 'msg_$role', role: role, time: time),
    parts: parts,
  );
}

MessagePart _tool(String status) => MessagePart.fromJson({
      'id': 'part_$status',
      'type': 'tool',
      'tool': 'bash',
      'state': {'status': status, 'output': 'partial'},
    });

void main() {
  group('frozenTail', () {
    test('stamps the live assistant tail as completed', () {
      final frozen = frozenTail([
        _msg(role: 'user', completed: 1),
        _msg(role: 'assistant'),
      ], 9999);
      expect(frozen.last.info.timeCompleted, 9999);
      expect(isTailGenerating(frozen), isFalse);
    });

    test('leaves an already-completed tail alone', () {
      final frozen = frozenTail([_msg(role: 'assistant', completed: 42)], 9999);
      expect(frozen.last.info.timeCompleted, 42);
    });

    test('leaves a user tail alone — nothing is generating', () {
      final messages = [_msg(role: 'user')];
      expect(frozenTail(messages, 9999), same(messages));
    });

    test('empty transcript is returned unchanged', () {
      expect(frozenTail(const [], 9999), isEmpty);
    });

    test('unfinished tool parts stop; finished ones keep their status', () {
      final frozen = frozenTail([
        _msg(
          role: 'assistant',
          parts: [_tool('running'), _tool('pending'), _tool('completed')],
        ),
      ], 9999);
      expect(
        frozen.last.parts.map((p) => p.state),
        ['stopped', 'stopped', 'completed'],
      );
    });

    test('freezing a tool part preserves the output already collected', () {
      final frozen = frozenTail(
        [
          _msg(role: 'assistant', parts: [_tool('running')])
        ],
        9999,
      );
      final state = frozen.last.parts.single.raw['state'] as Map;
      expect(state['output'], 'partial');
    });

    test('earlier messages are untouched', () {
      final first = _msg(role: 'user', completed: 1);
      final frozen = frozenTail([first, _msg(role: 'assistant')], 9999);
      expect(frozen.first, same(first));
      expect(frozen.length, 2);
    });
  });
}
