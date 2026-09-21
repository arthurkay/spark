import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/chat_provider.dart';
import 'package:spark/features/chat/chat_screen.dart';

MessagePart _text(String id, String content) =>
    MessagePart.fromJson({'id': id, 'type': 'text', 'text': content});

MessagePart _tool(String id, String status) => MessagePart.fromJson({
  'id': id,
  'type': 'tool',
  'tool': 'bash',
  'state': {'status': status, 'output': ''},
});

MessageWithParts _msg({
  required String role,
  required String id,
  int? completed,
  List<MessagePart> parts = const [],
  Map<String, dynamic>? error,
}) {
  final time = <String, dynamic>{'created': 1};
  if (completed != null) time['completed'] = completed;
  return MessageWithParts(
    info: MessageInfo(id: id, role: role, time: time, error: error),
    parts: parts,
  );
}

void main() {
  group('computeWorkingState — optimisticBusy invariant', () {
    test('optimisticBusy + completed tail → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [_msg(role: 'assistant', id: 'a1', completed: 5)],
        ),
        isTrue,
        reason: 'optimisticBusy overrides completed tail',
      );
    });

    test('optimisticBusy + user tail → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [_msg(role: 'user', id: 'u1')],
        ),
        isTrue,
        reason: 'optimisticBusy overrides user tail',
      );
    });

    test('optimisticBusy + empty messages → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [],
        ),
        isTrue,
        reason: 'optimisticBusy overrides empty transcript',
      );
    });

    test('optimisticBusy + errored tail → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [
            _msg(
              role: 'assistant',
              id: 'a1',
              error: {'name': 'APIError', 'data': {}},
            ),
          ],
        ),
        isTrue,
        reason: 'optimisticBusy overrides errored tail',
      );
    });

    test('optimisticBusy + tool tail running → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [
            _msg(role: 'assistant', id: 'a1', parts: [_tool('t1', 'running')]),
          ],
        ),
        isTrue,
      );
    });

    test('optimisticBusy + tool tail completed → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [
            _msg(
              role: 'assistant',
              id: 'a1',
              completed: 5,
              parts: [_tool('t1', 'completed')],
            ),
          ],
        ),
        isTrue,
        reason: 'optimisticBusy overrides fully completed tool turn',
      );
    });

    test('aborting always returns false regardless of optimisticBusy', () {
      expect(
        computeWorkingState(
          aborting: true,
          optimisticBusy: true,
          messages: [_msg(role: 'assistant', id: 'a1')],
        ),
        isFalse,
        reason: 'aborting takes precedence over optimisticBusy',
      );
    });

    test('not optimisticBusy + completed tail → not working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: [_msg(role: 'assistant', id: 'a1', completed: 5)],
        ),
        isFalse,
      );
    });

    test('not optimisticBusy + user tail → not working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: [_msg(role: 'user', id: 'u1')],
        ),
        isFalse,
      );
    });

    test('not optimisticBusy + unfinished tail → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: [_msg(role: 'assistant', id: 'a1')],
        ),
        isTrue,
      );
    });
  });

  group('computeWorkingState — streaming lifecycle', () {
    test('send sets optimisticBusy → working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [_msg(role: 'user', id: 'u1')],
        ),
        isTrue,
        reason:
            'right after send(), user message is tail but optimisticBusy keeps working',
      );
    });

    test('server responds with assistant → still working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [
            _msg(role: 'user', id: 'u1'),
            _msg(role: 'assistant', id: 'a1'),
          ],
        ),
        isTrue,
      );
    });

    test('streaming content grows → still working', () {
      final msgs = [
        _msg(role: 'assistant', id: 'a1', parts: [_text('t1', 'Hello world')]),
      ];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: msgs,
        ),
        isTrue,
      );
    });

    test('server completes → not working after optimisticBusy clears', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: [_msg(role: 'assistant', id: 'a1', completed: 100)],
        ),
        isFalse,
      );
    });
  });

  group('computeWorkingState — edge cases for scroll follow', () {
    test('load snapshot with user tail while optimisticBusy stays working', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: true,
          messages: [_msg(role: 'user', id: 'u1')],
        ),
        isTrue,
        reason:
            'if load() fires before assistant message arrives, optimisticBusy prevents working=false',
      );
    });

    test(
      'load snapshot with completed assistant while optimisticBusy stays working',
      () {
        expect(
          computeWorkingState(
            aborting: false,
            optimisticBusy: true,
            messages: [_msg(role: 'assistant', id: 'a1', completed: 5)],
          ),
          isTrue,
          reason:
              'stale load snapshot showing completed should not kill working while optimisticBusy',
        );
      },
    );

    test('alternating messages — only last matters for isTailGenerating', () {
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: [
            _msg(role: 'assistant', id: 'a1', completed: 1),
            _msg(role: 'user', id: 'u1'),
            _msg(role: 'assistant', id: 'a2'),
          ],
        ),
        isTrue,
        reason: 'unfinished assistant at tail means working',
      );
    });

    test('long message list — only tail determines working', () {
      final msgs = <MessageWithParts>[
        for (var i = 0; i < 50; i++)
          _msg(role: i.isEven ? 'user' : 'assistant', id: 'm$i', completed: 1),
        _msg(role: 'assistant', id: 'm_last'),
      ];
      expect(
        computeWorkingState(
          aborting: false,
          optimisticBusy: false,
          messages: msgs,
        ),
        isTrue,
      );
    });
  });

  group('chatChromeOf — record equality during streaming', () {
    test('same working state across different messages → equal records', () {
      final s1 = ChatState(
        working: true,
        messages: [
          _msg(role: 'assistant', id: 'a1', parts: [_text('t1', 'Hi')]),
        ],
      );
      final s2 = ChatState(
        working: true,
        messages: [
          _msg(
            role: 'assistant',
            id: 'a1',
            parts: [_text('t1', 'Hi there world')],
          ),
        ],
      );
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(
        r1,
        equals(r2),
        reason:
            'chatChromeOf ignores message content — only working/loading/etc matter',
      );
    });

    test('working true → false changes record', () {
      final s1 = ChatState(working: true, messages: []);
      final s2 = ChatState(working: false, messages: []);
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(r1, isNot(equals(r2)));
    });

    test('loading changes record', () {
      final s1 = ChatState(loading: true);
      final s2 = ChatState(loading: false);
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(r1, isNot(equals(r2)));
    });

    test('error changes record', () {
      final s1 = ChatState(error: null);
      final s2 = ChatState(error: 'fail');
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(r1, isNot(equals(r2)));
    });

    test('empty messages — hasMessages field tracks emptiness', () {
      final s1 = ChatState(messages: const []);
      final s2 = ChatState(
        messages: [_msg(role: 'user', id: 'u1')],
      );
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(
        r1,
        isNot(equals(r2)),
        reason: 'hasMessages changes when messages go from empty to non-empty',
      );
    });

    test('multiple fields change — record still different', () {
      final s1 = ChatState(working: true, loading: true, sending: true);
      final s2 = ChatState(working: false, loading: false, sending: false);
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(r1, isNot(equals(r2)));
    });

    test('retry fields change record', () {
      final s1 = ChatState();
      final s2 = ChatState(retryMessage: 'try again');
      final r1 = chatChromeOf(s1, initialLoadDone: true);
      final r2 = chatChromeOf(s2, initialLoadDone: true);
      expect(r1, isNot(equals(r2)));
    });
  });

  group('isNearBottom — streaming follow threshold', () {
    test('at exact bottom', () {
      expect(isNearBottom(1000, 1000), isTrue);
    });

    test('within 1px of bottom', () {
      expect(isNearBottom(999, 1000), isTrue);
    });

    test('at threshold boundary', () {
      expect(isNearBottom(881, 1000), isTrue);
    });

    test('just beyond threshold', () {
      expect(isNearBottom(880, 1000), isFalse);
    });

    test('120px from bottom (old threshold edge)', () {
      expect(isNearBottom(880, 1000), isFalse);
    });

    test('200px from bottom (common user position)', () {
      expect(isNearBottom(800, 1000), isFalse);
    });

    test('zero scroll extent (empty chat)', () {
      expect(isNearBottom(0, 0), isTrue);
    });

    test('1px scroll extent', () {
      expect(isNearBottom(0, 1), isTrue);
    });

    test('scrolled past bottom (negative gap)', () {
      expect(
        isNearBottom(1000, 900),
        isTrue,
        reason: 'pixels > maxScrollExtent should be near bottom',
      );
    });
  });

  group('ChatState.copyWith — working field preservation', () {
    test('copyWith messages preserves working', () {
      const s = ChatState(working: true);
      final s2 = s.copyWith(
        messages: [_msg(role: 'user', id: 'u1')],
      );
      expect(s2.working, isTrue);
    });

    test('copyWith working: true sets working', () {
      const s = ChatState(working: false);
      final s2 = s.copyWith(working: true);
      expect(s2.working, isTrue);
    });

    test('copyWith working: false clears working', () {
      const s = ChatState(working: true);
      final s2 = s.copyWith(working: false);
      expect(s2.working, isFalse);
    });

    test('copyWith loading preserves working', () {
      const s = ChatState(working: true);
      final s2 = s.copyWith(loading: false);
      expect(s2.working, isTrue);
    });

    test('copyWith error preserves working', () {
      const s = ChatState(working: true);
      final s2 = s.copyWith(error: 'timeout');
      expect(s2.working, isTrue);
    });

    test('copyWith clearError preserves working', () {
      const s = ChatState(working: true, error: 'old');
      final s2 = s.copyWith(clearError: true);
      expect(s2.working, isTrue);
      expect(s2.error, isNull);
    });
  });

  group('isTailGenerating — additional edge cases', () {
    test('multiple completed messages then unfinished → working', () {
      expect(
        isTailGenerating([
          _msg(role: 'assistant', id: 'a1', completed: 1),
          _msg(role: 'user', id: 'u1'),
          _msg(role: 'assistant', id: 'a2'),
        ]),
        isTrue,
      );
    });

    test('assistant with text parts unfinished → working', () {
      expect(
        isTailGenerating([
          _msg(role: 'assistant', id: 'a1', parts: [_text('p1', 'Hello')]),
        ]),
        isTrue,
      );
    });

    test('assistant with tool parts running → working', () {
      expect(
        isTailGenerating([
          _msg(role: 'assistant', id: 'a1', parts: [_tool('t1', 'running')]),
        ]),
        isTrue,
      );
    });

    test('assistant with completed tool but no timeCompleted → working', () {
      expect(
        isTailGenerating([
          _msg(role: 'assistant', id: 'a1', parts: [_tool('t1', 'completed')]),
        ]),
        isTrue,
      );
    });

    test('assistant with timeCompleted + running tool → not working', () {
      expect(
        isTailGenerating([
          _msg(
            role: 'assistant',
            id: 'a1',
            completed: 5,
            parts: [_tool('t1', 'running')],
          ),
        ]),
        isFalse,
      );
    });
  });
}
