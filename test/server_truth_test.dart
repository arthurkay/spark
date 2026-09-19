import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/chat_provider.dart';

MessagePart _tool(String status) => MessagePart.fromJson({
  'id': 'part_$status',
  'type': 'tool',
  'tool': 'bash',
  'state': {'status': status, 'output': ''},
});

MessagePart _text(String content) =>
    MessagePart.fromJson({'id': 'part_text', 'type': 'text', 'text': content});

MessageWithParts _msg({
  required String role,
  int? completed,
  List<MessagePart> parts = const [],
  Map<String, dynamic>? error,
}) {
  final time = <String, dynamic>{'created': 1};
  if (completed != null) time['completed'] = completed;
  return MessageWithParts(
    info: MessageInfo(
      id: 'msg_$role${completed ?? ''}',
      role: role,
      time: time,
      error: error,
    ),
    parts: parts,
  );
}

void main() {
  group('sameMessages', () {
    test('identical empty messages are the same', () {
      final a = _msg(role: 'assistant');
      final b = _msg(role: 'assistant');
      expect(sameMessages(a, b), isTrue);
    });

    test('different part count means different', () {
      final a = _msg(role: 'assistant', parts: [_text('hi')]);
      final b = _msg(role: 'assistant', parts: [_text('hi'), _text('there')]);
      expect(sameMessages(a, b), isFalse);
    });

    test('different text means different', () {
      final a = _msg(role: 'assistant', parts: [_text('hello')]);
      final b = _msg(role: 'assistant', parts: [_text('world')]);
      expect(sameMessages(a, b), isFalse);
    });

    test('different type means different', () {
      final a = _msg(
        role: 'assistant',
        parts: [const MessagePart(id: 'p1', type: 'text', text: 'x')],
      );
      final b = _msg(
        role: 'assistant',
        parts: [const MessagePart(id: 'p1', type: 'tool', text: 'x')],
      );
      expect(sameMessages(a, b), isFalse);
    });

    test('different state means different — server updated', () {
      final a = _msg(role: 'assistant', parts: [_tool('running')]);
      final b = _msg(role: 'assistant', parts: [_tool('completed')]);
      expect(sameMessages(a, b), isFalse);
    });

    test('same state and content means same', () {
      final a = _msg(role: 'assistant', parts: [_tool('completed')]);
      final b = _msg(role: 'assistant', parts: [_tool('completed')]);
      expect(sameMessages(a, b), isTrue);
    });

    test('multiple parts compared pairwise', () {
      final a = _msg(
        role: 'assistant',
        parts: [_tool('running'), _text('hello')],
      );
      final b = _msg(
        role: 'assistant',
        parts: [_tool('completed'), _text('hello')],
      );
      expect(sameMessages(a, b), isFalse);
    });

    test('same content across multiple parts', () {
      final a = _msg(
        role: 'assistant',
        parts: [_tool('completed'), _text('done')],
      );
      final b = _msg(
        role: 'assistant',
        parts: [_tool('completed'), _text('done')],
      );
      expect(sameMessages(a, b), isTrue);
    });
  });

  group('computeWorkingState', () {
    test('aborting always returns false regardless of server state', () {
      final messages = [_msg(role: 'assistant')];
      expect(
        computeWorkingState(
          aborting: true,
          optimisticBusy: true,
          messages: messages,
        ),
        isFalse,
      );
    });

    test('optimisticBusy returns true when not aborting', () {
      final messages = [_msg(role: 'assistant', completed: 1)];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: messages,
        ),
        isTrue,
      );
    });

    test('server tail incomplete → working when no local flags', () {
      final messages = [_msg(role: 'assistant')];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isTrue,
      );
    });

    test('server tail complete → not working', () {
      final messages = [_msg(role: 'assistant', completed: 1)];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isFalse,
      );
    });

    test('server tail errored → not working', () {
      final messages = [
        _msg(
          role: 'assistant',
          error: {'name': 'ContextOverflowError', 'data': {}},
        ),
      ];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isFalse,
      );
    });

    test('server tail user message → not working', () {
      final messages = [_msg(role: 'user')];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isFalse,
      );
    });

    test('empty transcript → not working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: const [],
        ),
        isFalse,
      );
    });

    test('stale incomplete turn followed by user → not working', () {
      final messages = [_msg(role: 'assistant'), _msg(role: 'user')];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isFalse,
      );
    });
  });

  group('isTailGenerating with tool states', () {
    test('assistant with running tool and no timeCompleted → generating', () {
      final messages = [
        _msg(role: 'assistant', parts: [_tool('running')]),
      ];
      expect(isTailGenerating(messages), isTrue);
    });

    test('assistant with completed tool and no timeCompleted → generating', () {
      final messages = [
        _msg(role: 'assistant', parts: [_tool('completed')]),
      ];
      expect(isTailGenerating(messages), isTrue);
    });

    test('assistant with stopped tool and timeCompleted → not generating', () {
      final messages = [
        _msg(role: 'assistant', completed: 2, parts: [_tool('stopped')]),
      ];
      expect(isTailGenerating(messages), isFalse);
    });

    test('server marks tool completed after local stop → generating again', () {
      final messages = [
        _msg(role: 'assistant', parts: [_tool('completed')]),
      ];
      expect(
        isTailGenerating(messages),
        isTrue,
        reason: 'server says still going',
      );
    });
  });

  group('frozenTail + server reconcile', () {
    test('local abort stamps tools as stopped', () {
      final frozen = frozenTail([
        _msg(role: 'assistant', parts: [_tool('running'), _tool('pending')]),
      ], 9999);
      expect(frozen.last.parts.every((p) => p.state == 'stopped'), isTrue);
    });

    test(
      'server reload replaces frozen state — sameMessages returns false',
      () {
        final beforeAbort = _msg(role: 'assistant', parts: [_tool('running')]);
        final frozen = frozenTail([beforeAbort], 9999);
        final serverVersion = _msg(
          role: 'assistant',
          completed: 2,
          parts: [_tool('completed')],
        );
        expect(
          sameMessages(frozen.last, serverVersion),
          isFalse,
          reason: 'server updated state, so merge will replace frozen version',
        );
      },
    );

    test('server reload with same content reuses identity', () {
      final a = _msg(
        role: 'assistant',
        completed: 2,
        parts: [_tool('completed')],
      );
      final b = _msg(
        role: 'assistant',
        completed: 2,
        parts: [_tool('completed')],
      );
      expect(
        sameMessages(a, b),
        isTrue,
        reason: 'server returned same state, reuse cached bubble',
      );
    });
  });

  group('server reconnection clears abort', () {
    test('computeWorkingState with aborting:false reflects server truth', () {
      final messages = [_msg(role: 'assistant')];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: messages,
        ),
        isTrue,
        reason: 'after reconnect clears aborting, server tail drives state',
      );
    });

    test('computeWorkingState with aborting:true ignores server truth', () {
      final messages = [_msg(role: 'assistant')];
      expect(
        computeWorkingState(
          aborting: true,
          optimisticBusy: false,
          messages: messages,
        ),
        isFalse,
        reason: 'aborting flag blocks server state from driving UI',
      );
    });
  });

  group('messageHasVisibleContent', () {
    test('text message is visible', () {
      expect(
        messageHasVisibleContent(_msg(role: 'assistant', parts: [_text('hi')])),
        isTrue,
      );
    });

    test('tool message is visible', () {
      expect(
        messageHasVisibleContent(
          _msg(role: 'assistant', parts: [_tool('running')]),
        ),
        isTrue,
      );
    });

    test('empty assistant with no parts is hidden', () {
      expect(messageHasVisibleContent(_msg(role: 'assistant')), isFalse);
    });

    test('assistant with only empty text is hidden', () {
      expect(
        messageHasVisibleContent(
          _msg(
            role: 'assistant',
            parts: [const MessagePart(id: 'p1', type: 'text', text: '  ')],
          ),
        ),
        isFalse,
      );
    });

    test('reasoning part is visible', () {
      expect(
        messageHasVisibleContent(
          _msg(
            role: 'assistant',
            parts: [const MessagePart(id: 'p1', type: 'reasoning')],
          ),
        ),
        isTrue,
      );
    });

    test('file part is visible', () {
      expect(
        messageHasVisibleContent(
          _msg(
            role: 'assistant',
            parts: [const MessagePart(id: 'p1', type: 'file')],
          ),
        ),
        isTrue,
      );
    });
  });

  group('VisibleMessageIds equality', () {
    test('same ids are equal', () {
      expect(
        VisibleMessageIds(const ['a', 'b']),
        equals(VisibleMessageIds(const ['a', 'b'])),
      );
    });

    test('different ids are not equal', () {
      expect(
        VisibleMessageIds(const ['a', 'b']),
        isNot(equals(VisibleMessageIds(const ['a', 'c']))),
      );
    });

    test('different length is not equal', () {
      expect(
        VisibleMessageIds(const ['a']),
        isNot(equals(VisibleMessageIds(const ['a', 'b']))),
      );
    });
  });
}
