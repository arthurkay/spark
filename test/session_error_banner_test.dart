import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/message.dart';
import 'package:spark/features/chat/chat_provider.dart';

MessageWithParts _msg({
  required String role,
  int? completed,
  Map<String, dynamic>? error,
  List<MessagePart> parts = const [],
}) {
  final time = <String, dynamic>{'created': 1};
  if (completed != null) time['completed'] = completed;
  return MessageWithParts(
    info: MessageInfo(
      id: 'msg_$role${completed ?? ''}${error == null ? '' : '_err'}',
      role: role,
      time: time,
      error: error,
    ),
    parts: parts,
  );
}

Map<String, dynamic> _apiError(String message, {int? statusCode}) {
  return {
    'name': 'APIError',
    'data': {'message': message, 'statusCode': ?statusCode},
  };
}

void main() {
  group('resolveBannerOnLoad', () {
    test('tail error wins over sticky and current banner', () {
      final messages = [
        _msg(role: 'user'),
        _msg(role: 'assistant', error: _apiError('boom', statusCode: 400)),
      ];
      final banner = resolveBannerOnLoad(
        messages: messages,
        sticky: false,
        currentError: 'old',
        currentErrorType: 'OldError',
        currentStatusCode: null,
      );
      expect(banner.clear, isFalse);
      expect(banner.error, 'boom');
      expect(banner.errorType, 'APIError');
      expect(banner.statusCode, 400);
    });

    test('sticky session.error survives a load with no tail error', () {
      // Model rejected the prompt before any assistant message was created —
      // this is the case that used to wipe the banner.
      final banner = resolveBannerOnLoad(
        messages: [_msg(role: 'user')],
        sticky: true,
        currentError: 'model does not support chat completion',
        currentErrorType: 'APIError',
        currentStatusCode: 400,
      );
      expect(banner.clear, isFalse);
      expect(banner.error, 'model does not support chat completion');
      expect(banner.errorType, 'APIError');
      expect(banner.statusCode, 400);
    });

    test('a successful tail clears a sticky error', () {
      final banner = resolveBannerOnLoad(
        messages: [
          _msg(role: 'user'),
          _msg(role: 'assistant', completed: 5),
        ],
        sticky: true,
        currentError: 'stale failure',
        currentErrorType: 'APIError',
        currentStatusCode: 400,
      );
      expect(banner.clear, isTrue);
      expect(banner.error, isNull);
    });

    test('no tail error and not sticky clears the banner', () {
      final banner = resolveBannerOnLoad(
        messages: [_msg(role: 'user')],
        sticky: false,
        currentError: null,
        currentErrorType: null,
        currentStatusCode: null,
      );
      expect(banner.clear, isTrue);
    });

    test('an aborted tail is not an error banner', () {
      final banner = resolveBannerOnLoad(
        messages: [
          _msg(
            role: 'assistant',
            error: {'name': 'MessageAbortedError', 'data': {}},
          ),
        ],
        sticky: false,
        currentError: null,
        currentErrorType: null,
        currentStatusCode: null,
      );
      expect(banner.clear, isTrue);
      expect(banner.error, isNull);
    });

    test('empty transcript with sticky keeps the error', () {
      final banner = resolveBannerOnLoad(
        messages: const [],
        sticky: true,
        currentError: 'server rejected the model',
        currentErrorType: 'UnknownError',
        currentStatusCode: null,
      );
      expect(banner.clear, isFalse);
      expect(banner.error, 'server rejected the model');
    });

    test('NoReplyStarted is cleared, not kept sticky', () {
      final banner = resolveBannerOnLoad(
        messages: [_msg(role: 'user')],
        sticky: true,
        currentError: 'The server accepted your message but no reply started.',
        currentErrorType: 'NoReplyStarted',
        currentStatusCode: null,
      );
      expect(banner.clear, isTrue);
      expect(banner.error, isNull);
      expect(banner.errorType, isNull);
    });
  });

  group('tailSucceeded', () {
    test('completed error-free assistant is success', () {
      expect(tailSucceeded([_msg(role: 'assistant', completed: 2)]), isTrue);
    });

    test('unfinished assistant is not', () {
      expect(tailSucceeded([_msg(role: 'assistant')]), isFalse);
    });

    test('user tail is not', () {
      expect(tailSucceeded([_msg(role: 'user')]), isFalse);
    });

    test('errored assistant is not', () {
      expect(
        tailSucceeded([_msg(role: 'assistant', error: _apiError('x'))]),
        isFalse,
      );
    });

    test('empty is not', () {
      expect(tailSucceeded(const []), isFalse);
    });
  });

  group('MessageInfo.errorStatusCode', () {
    test('reads statusCode from error data', () {
      final info = _msg(
        role: 'assistant',
        error: _apiError('nope', statusCode: 400),
      ).info;
      expect(info.errorStatusCode, 400);
    });

    test('null when absent', () {
      final info = _msg(role: 'assistant', error: _apiError('nope')).info;
      expect(info.errorStatusCode, isNull);
    });
  });

  group('messageHasVisibleContent', () {
    test('an error-only assistant message still renders', () {
      final m = _msg(role: 'assistant', error: _apiError('model unsupported'));
      expect(messageHasVisibleContent(m), isTrue);
    });

    test('an aborted error-only message does not render', () {
      final m = _msg(
        role: 'assistant',
        error: {'name': 'MessageAbortedError', 'data': {}},
      );
      expect(messageHasVisibleContent(m), isFalse);
    });

    test('a message with text still renders', () {
      final m = MessageWithParts(
        info: MessageInfo(id: 'm', role: 'user'),
        parts: [MessagePart(id: 'p', type: 'text', text: 'hi')],
      );
      expect(messageHasVisibleContent(m), isTrue);
    });

    test('a message with no parts and no error does not render', () {
      final m = MessageWithParts(
        info: MessageInfo(id: 'm', role: 'user'),
        parts: const [],
      );
      expect(messageHasVisibleContent(m), isFalse);
    });
  });
}
