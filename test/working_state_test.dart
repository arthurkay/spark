import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/chat_provider.dart';

MessageWithParts _msg({
  required String role,
  int? completed,
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
    parts: const [],
  );
}

Map<String, dynamic> _err(String name, [String? message]) {
  final data = <String, dynamic>{};
  if (message != null) data['message'] = message;
  return {'name': name, 'data': data};
}

void main() {
  group('isTailGenerating', () {
    test('an unfinished assistant message is generating', () {
      expect(isTailGenerating([_msg(role: 'assistant')]), isTrue);
    });

    test('a completed assistant message is not', () {
      expect(
          isTailGenerating([_msg(role: 'assistant', completed: 2)]), isFalse);
    });

    test('an empty transcript is not', () {
      expect(isTailGenerating(const []), isFalse);
    });

    test('a user message at the tail is not', () {
      expect(isTailGenerating([_msg(role: 'user')]), isFalse);
    });

    test('a stale unfinished turn followed by another message is not', () {
      expect(
        isTailGenerating([_msg(role: 'assistant'), _msg(role: 'user')]),
        isFalse,
      );
    });

    group('a turn that died is finished even without time.completed', () {
      // The server leaves `time.completed` unset when a turn errors, so these
      // used to report "working" forever.
      for (final name in [
        'MessageOutputLengthError',
        'ContextOverflowError',
        'ProviderAuthError',
        'APIError',
        'ContentFilterError',
        'StructuredOutputError',
        'UnknownError',
        'MessageAbortedError',
      ]) {
        test(name, () {
          expect(
            isTailGenerating([_msg(role: 'assistant', error: _err(name))]),
            isFalse,
            reason: '$name should end the working state',
          );
        });
      }
    });
  });

  group('MessageInfo error reporting', () {
    test('exposes the server error tag', () {
      final info = _msg(
        role: 'assistant',
        error: _err('MessageOutputLengthError'),
      ).info;
      expect(info.errorName, 'MessageOutputLengthError');
      expect(info.hasError, isTrue);
      expect(info.wasAborted, isFalse);
    });

    test('an abort is terminal but not banner-worthy', () {
      final info = _msg(
        role: 'assistant',
        error: _err('MessageAbortedError', 'aborted'),
      ).info;
      expect(info.hasError, isTrue);
      expect(info.wasAborted, isTrue);
    });

    test('falls back to the error name when there is no message', () {
      final info = _msg(
        role: 'assistant',
        error: _err('ContextOverflowError'),
      ).info;
      expect(info.errorMessage, 'ContextOverflowError');
    });

    test('prefers the error data message when present', () {
      final info = _msg(
        role: 'assistant',
        error: _err('APIError', 'rate limited'),
      ).info;
      expect(info.errorMessage, 'rate limited');
    });

    test('a clean message reports no error', () {
      final info = _msg(role: 'assistant', completed: 2).info;
      expect(info.hasError, isFalse);
      expect(info.errorName, isNull);
      expect(info.errorMessage, isNull);
    });
  });
}
