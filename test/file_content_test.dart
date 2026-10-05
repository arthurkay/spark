import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spark/core/models/file_node.dart';

void main() {
  group('FileContent.decodedBytes', () {
    test('decodes base64 content', () {
      final content = FileContent.fromJson({
        'content': base64Encode(utf8.encode('%PDF-1.4')),
        'encoding': 'base64',
      });
      expect(content.isBase64Encoded, isTrue);
      expect(content.decodedBytes, Uint8List.fromList(utf8.encode('%PDF-1.4')));
    });

    test('passes plain text through as utf8 bytes', () {
      const content = FileContent(content: 'hello');
      expect(content.decodedBytes, Uint8List.fromList(utf8.encode('hello')));
    });

    test('returns null for invalid base64', () {
      const content = FileContent(
        content: '!!!not-base64!!!',
        encoding: 'base64',
      );
      expect(content.decodedBytes, isNull);
    });
  });
}
