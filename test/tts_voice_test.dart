import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/tts_provider.dart';

void main() {
  group('parseVoices', () {
    test('parses well-formed platform maps', () {
      final voices = parseVoices([
        {'name': 'en-us-x-tpf-local', 'locale': 'en-US'},
        {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
      ]);
      expect(voices, hasLength(2));
      expect(voices.first.locale, 'en-GB');
      expect(voices.last.name, 'en-us-x-tpf-local');
    });

    test('skips entries missing a name or locale', () {
      final voices = parseVoices([
        {'name': 'good', 'locale': 'en-US'},
        {'name': '', 'locale': 'en-US'},
        {'locale': 'en-US'},
        {'name': 'no-locale'},
        {'name': 42, 'locale': 'en-US'},
      ]);
      expect(voices, hasLength(1));
      expect(voices.single.name, 'good');
    });

    test('collapses duplicates', () {
      final voices = parseVoices([
        {'name': 'same', 'locale': 'en-US'},
        {'name': 'same', 'locale': 'en-US'},
      ]);
      expect(voices, hasLength(1));
    });

    test('sorts by locale then name, deterministically', () {
      final voices = parseVoices([
        {'name': 'zz', 'locale': 'en-US'},
        {'name': 'aa', 'locale': 'en-US'},
        {'name': 'mm', 'locale': 'de-DE'},
      ]);
      expect(
        voices.map((v) => '${v.locale}/${v.name}').toList(),
        ['de-DE/mm', 'en-US/aa', 'en-US/zz'],
      );
    });

    test('garbage input yields an empty list, never a throw', () {
      expect(parseVoices(null), isEmpty);
      expect(parseVoices('nonsense'), isEmpty);
      expect(parseVoices(42), isEmpty);
      expect(parseVoices(['a', 1, null]), isEmpty);
    });

    test('platform maps are not typed — non-string keys still parse', () {
      // The channel hands back Map<Object?, Object?>.
      final voices = parseVoices([
        <Object?, Object?>{'name': 'v', 'locale': 'en-US'},
      ]);
      expect(voices, hasLength(1));
    });
  });

  group('TtsState.sourceText', () {
    test('copyWith preserves sourceText by default', () {
      const state = TtsState(
        status: TtsStatus.playing,
        sourceText: '## original markdown',
      );
      expect(state.copyWith(status: TtsStatus.paused).sourceText,
          '## original markdown');
    });

    test('clearText drops sourceText with the rest', () {
      const state = TtsState(
        status: TtsStatus.playing,
        text: 'preview',
        fullText: 'narration',
        sourceText: 'original',
      );
      final cleared = state.copyWith(clearText: true);
      expect(cleared.text, isNull);
      expect(cleared.fullText, isNull);
      expect(cleared.sourceText, isNull);
    });
  });
}
