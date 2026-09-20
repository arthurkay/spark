import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/chat_provider.dart';
import 'package:spark/shared/chunked_async.dart';

void main() {
  group('chunkedMap', () {
    test('returns same result as synchronous map', () async {
      final items = List.generate(100, (i) => i * 2);
      final result = await chunkedMap(items, (n) => n + 1);
      expect(result, items.map((n) => n + 1).toList());
    });

    test('handles empty list', () async {
      final result = await chunkedMap<int, int>([], (n) => n);
      expect(result, isEmpty);
    });

    test('handles list smaller than chunk size', () async {
      final result = await chunkedMap([1, 2, 3], (n) => n * 10, chunkSize: 10);
      expect(result, [10, 20, 30]);
    });

    test('preserves order with multiple chunks', () async {
      final items = List.generate(50, (i) => i);
      final result = await chunkedMap(items, (n) => n, chunkSize: 10);
      expect(result, items);
    });
  });

  group('parseMessagesFromCache', () {
    test('parses an empty items list', () async {
      final result = await parseMessagesFromCache({'items': []});
      expect(result, isEmpty);
    });

    test('parses missing items key as empty', () async {
      final result = await parseMessagesFromCache({});
      expect(result, isEmpty);
    });

    test('parses a single text message', () async {
      final result = await parseMessagesFromCache({
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

    test('parses messages with tool parts', () async {
      final result = await parseMessagesFromCache({
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

    test('parses multiple messages in order', () async {
      final result = await parseMessagesFromCache({
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

    test('skips non-map items in the list', () async {
      final result = await parseMessagesFromCache({
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

    test('handles messages with no parts', () async {
      final result = await parseMessagesFromCache({
        'items': [
          {
            'info': {'id': 'msg_1', 'role': 'user'},
          },
        ],
      });
      expect(result, hasLength(1));
      expect(result.first.parts, isEmpty);
    });

    test('handles messages with error field', () async {
      final result = await parseMessagesFromCache({
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

    test('handles messages with model and provider info', () async {
      final result = await parseMessagesFromCache({
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

    test('handles items that lack the parts key', () async {
      final result = await parseMessagesFromCache({
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
