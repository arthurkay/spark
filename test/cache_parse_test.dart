import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/chat_provider.dart';

void main() {
  group('parseMessagesFromCache', () {
    test('parses an empty items list', () {
      final result = parseMessagesFromCache({'items': []});
      expect(result, isEmpty);
    });

    test('parses missing items key as empty', () {
      final result = parseMessagesFromCache({});
      expect(result, isEmpty);
    });

    test('parses a single text message', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {
              'id': 'msg_1',
              'role': 'user',
              'time': {'created': 100},
            },
            'parts': [
              {'id': 'p1', 'type': 'text', 'text': 'Hello'},
            ],
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.info.id, 'msg_1');
      expect(result.first.info.role, 'user');
      expect(result.first.parts, hasLength(1));
      expect(result.first.parts.first.text, 'Hello');
    });

    test('parses messages with tool parts', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {
              'id': 'msg_2',
              'role': 'assistant',
              'time': {'created': 200, 'completed': 300},
            },
            'parts': [
              {
                'id': 'part_tool',
                'type': 'tool',
                'tool': 'bash',
                'state': {'status': 'completed', 'output': 'done'},
              },
            ],
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.parts.first.type, 'tool');
      expect(result.first.parts.first.toolName, 'bash');
      expect(result.first.parts.first.state, 'completed');
      expect(result.first.info.timeCompleted, 300);
    });

    test('parses multiple messages in order', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {'id': 'msg_a', 'role': 'user'},
            'parts': [],
          },
          {
            'info': {'id': 'msg_b', 'role': 'assistant'},
            'parts': [],
          },
          {
            'info': {'id': 'msg_c', 'role': 'user'},
            'parts': [],
          },
        ],
      });
      expect(result, hasLength(3));
      expect(result[0].info.id, 'msg_a');
      expect(result[1].info.id, 'msg_b');
      expect(result[2].info.id, 'msg_c');
    });

    test('skips non-map items in the list', () {
      final result = parseMessagesFromCache({
        'items': [
          'not a map',
          42,
          null,
          {
            'info': {'id': 'msg_valid', 'role': 'user'},
            'parts': [],
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.info.id, 'msg_valid');
    });

    test('handles messages with no parts', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {'id': 'msg_1', 'role': 'user'},
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.parts, isEmpty);
    });

    test('handles messages with error field', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {
              'id': 'msg_err',
              'role': 'assistant',
              'error': {
                'name': 'ContextOverflowError',
                'data': {'message': 'context too long'},
              },
            },
            'parts': [],
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.info.hasError, isTrue);
      expect(result.first.info.errorMessage, 'context too long');
    });

    test('handles messages with model and provider info', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {
              'id': 'msg_model',
              'role': 'assistant',
              'modelID': 'claude-3',
              'providerID': 'anthropic',
              'agent': 'build',
              'time': {'created': 100, 'completed': 200},
            },
            'parts': [],
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.info.modelID, 'claude-3');
      expect(result.first.info.providerID, 'anthropic');
      expect(result.first.info.agent, 'build');
    });

    test('handles items that lack the parts key', () {
      final result = parseMessagesFromCache({
        'items': [
          {
            'info': {'id': 'msg_no_parts', 'role': 'user'},
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.parts, isEmpty);
    });
  });
}
