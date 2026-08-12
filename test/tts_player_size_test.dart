import 'package:flutter_test/flutter_test.dart';
import 'package:spark/features/chat/tts_overlay.dart';

void main() {
  group('nextPlayerSize', () {
    test('steps up through the stops', () {
      expect(nextPlayerSize(TtsPlayerSize.bar, up: true), TtsPlayerSize.half);
      expect(nextPlayerSize(TtsPlayerSize.half, up: true), TtsPlayerSize.tall);
    });

    test('steps down through the stops', () {
      expect(nextPlayerSize(TtsPlayerSize.tall, up: false), TtsPlayerSize.half);
      expect(nextPlayerSize(TtsPlayerSize.half, up: false), TtsPlayerSize.bar);
    });

    test('clamps at both ends', () {
      expect(nextPlayerSize(TtsPlayerSize.tall, up: true), TtsPlayerSize.tall);
      expect(nextPlayerSize(TtsPlayerSize.bar, up: false), TtsPlayerSize.bar);
    });
  });
}
