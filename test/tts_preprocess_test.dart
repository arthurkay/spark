import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:spark/features/chat/pdf_service.dart';
import 'package:spark/features/chat/tts_provider.dart';

void main() {
  group('speech preprocessing keeps the words it unwraps', () {
    test('bold, inline code and links survive stripping', () {
      final spoken = debugPreprocessForSpeech(
          'The **critical** bug is in `parseAll` — see [the docs](http://x.dev).');
      expect(spoken, 'The critical bug is in parseAll — see the docs.');
    });

    test('no replacement leaks a literal backreference', () {
      const source = '**a** *b* __c__ _d_ ~~e~~ `f` [g](http://h.io)';
      final spoken = debugPreprocessForSpeech(source);
      expect(spoken, isNot(contains(r'\1')));
      for (final word in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
        expect(spoken, contains(word), reason: 'lost "$word"');
      }
    });

    test('emphasis markers themselves are removed', () {
      expect(debugPreprocessForSpeech('**bold**'), 'bold');
      expect(debugPreprocessForSpeech('*italic*'), 'italic');
      expect(debugPreprocessForSpeech('__under__'), 'under');
      expect(debugPreprocessForSpeech('~~struck~~'), 'struck');
    });

    test('content that should be dropped is still dropped', () {
      expect(
        debugPreprocessForSpeech('Before\n```dart\nvoid main() {}\n```\nAfter'),
        'Before\n\nAfter',
      );
      expect(debugPreprocessForSpeech('![alt](img.png)'), '');
      expect(debugPreprocessForSpeech('## Heading'), 'Heading');
      expect(debugPreprocessForSpeech('- item'), 'item');
      expect(debugPreprocessForSpeech('1. item'), 'item');
      expect(debugPreprocessForSpeech('> quoted'), 'quoted');
    });

    test('bare urls become the word "link"', () {
      expect(debugPreprocessForSpeech('See https://example.com/a/b now'),
          'See link now');
    });

    test('plain prose is untouched', () {
      const plain = 'Just a normal sentence, nothing to strip.';
      expect(debugPreprocessForSpeech(plain), plain);
    });
  });

  group('pdf table extraction', () {
    md.Element parseTable(String source) {
      final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
          .parse(source);
      return nodes.whereType<md.Element>().firstWhere((e) => e.tag == 'table');
    }

    test('reads header and body cells as separate columns', () {
      final table = parseTable(
        '| Name | Role |\n'
        '| --- | --- |\n'
        '| Ada | Author |\n'
        '| Linus | Maintainer |\n',
      );
      expect(tableRows(table), [
        ['Name', 'Role'],
        ['Ada', 'Author'],
        ['Linus', 'Maintainer'],
      ]);
    });

    test('a header-only table yields just the header row', () {
      final table = parseTable('| A | B |\n| --- | --- |\n');
      expect(tableRows(table), [
        ['A', 'B'],
      ]);
    });
  });
}
