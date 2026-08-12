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

MessageWithParts _streaming({List<Map<String, dynamic>> parts = const []}) {
  return MessageWithParts(
    info:
        const MessageInfo(id: 'msg_s', role: 'assistant', time: {'created': 1}),
    parts: [
      for (final (i, p) in parts.indexed)
        MessagePart.fromJson({'id': 'p_$i', ...p}),
    ],
  );
}

void main() {
  group('fillerPhrase', () {
    test('step 0 is an acknowledgment, later steps reassure', () {
      expect(fillerPhrase(0, 0), contains('let me work'));
      expect(fillerPhrase(1, 0).toLowerCase(), isNot(contains('alright')));
    });

    test('consecutive steps never repeat a phrase', () {
      for (var salt = 0; salt < 40; salt++) {
        for (var step = 0; step < 12; step++) {
          expect(
            fillerPhrase(step, salt),
            isNot(fillerPhrase(step + 1, salt)),
            reason: 'salt=\$salt step=\$step',
          );
        }
      }
    });

    test('salt varies the opener between turns', () {
      final openers = {for (var s = 0; s < 6; s++) fillerPhrase(0, s)};
      expect(openers.length, greaterThan(1));
    });
  });

  group('speakableThought', () {
    test('extracts the last complete sentence', () {
      expect(
        speakableThought(
            'The handler is wrong. I should add a null check first. Then we'),
        'I should add a null check first.',
      );
    });

    test('returns null for a sentence still streaming', () {
      expect(speakableThought('I need to check the'), isNull);
    });

    test('strips code spans and markdown before speaking', () {
      expect(
        speakableThought('So `foo()` needs **fixing** in the handler.'),
        'So foo() needs fixing in the handler.',
      );
    });

    test('rejects fragments too short or too long to speak well', () {
      expect(speakableThought('Ok.'), isNull);
      expect(speakableThought('${'word ' * 60}.'), isNull);
    });

    test('fenced code blocks never leak into speech', () {
      final thought = speakableThought(
          'The fix is simple. ```dart\nvoid main() {}\n``` Now I apply it.');
      expect(thought, 'Now I apply it.');
    });
  });

  group('describeActivity', () {
    test('a tool call becomes a spoken phrase with the file name', () {
      final activity = describeActivity(_streaming(parts: [
        {
          'type': 'tool',
          'tool': 'read',
          'state': {
            'input': {'filePath': '/home/a/project/rollback.go'}
          },
        },
      ]));
      expect(activity?.spoken, "I'm reading rollback.go.");
      expect(activity?.shown, 'reading rollback.go…');
    });

    test('streamed reasoning shows its tail, spoken stays grounded', () {
      final activity = describeActivity(_streaming(parts: [
        {'type': 'reasoning', 'text': 'I need to check the handler first.'},
      ]));
      expect(activity?.shown, 'I need to check the handler first.');
      expect(activity?.spoken, 'I need to check the handler first.');
    });

    test('a streaming answer beats reasoning and tools', () {
      final activity = describeActivity(_streaming(parts: [
        {
          'type': 'tool',
          'tool': 'bash',
          'state': {'input': {}},
        },
        {'type': 'reasoning', 'text': 'thinking...'},
        {'type': 'text', 'text': 'The fix is to'},
      ]));
      expect(activity?.shown, 'The fix is to');
      expect(activity?.spoken, 'The answer is coming together now.');
    });

    test('the newest of several tool calls wins', () {
      final activity = describeActivity(_streaming(parts: [
        {
          'type': 'tool',
          'tool': 'read',
          'state': {
            'input': {'filePath': 'a.go'}
          },
        },
        {
          'type': 'tool',
          'tool': 'edit',
          'state': {
            'input': {'filePath': 'b.go'}
          },
        },
      ]));
      expect(activity?.spoken, "I'm editing b.go.");
    });

    test('a completed or non-assistant tail describes nothing', () {
      expect(describeActivity(null), isNull);
      expect(
        describeActivity(_msg(id: 'a', role: 'assistant', completed: 2)),
        isNull,
      );
      expect(describeActivity(_msg(id: 'u', role: 'user')), isNull);
    });

    test('an empty streaming turn describes nothing yet', () {
      expect(describeActivity(_streaming()), isNull);
    });

    test('long reasoning is tailed from a word boundary', () {
      final text = 'word ' * 100;
      final activity = describeActivity(_streaming(parts: [
        {'type': 'reasoning', 'text': text},
      ]));
      expect(activity!.shown.length, lessThanOrEqualTo(141));
      expect(activity.shown, startsWith('…'));
    });
  });

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
