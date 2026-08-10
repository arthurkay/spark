# TTS (Text-to-Speech) Implementation Proposed Plan

## Overview
Add text-to-speech capability to Spark, mirroring the existing STT (speech-to-text) integration. Users can tap a speaker icon on assistant message bubbles to have the response read aloud.

---

## 1. Dependencies

**pubspec.yaml** — add after `speech_to_text`:
```yaml
flutter_tts: ^4.2.5
```

---

## 2. Platform Configuration

### Android (`android/app/src/main/AndroidManifest.xml`)

Add TTS service query inside the existing `<queries>` block (required for SDK 30+):
```xml
<queries>
  <intent>
    <action android:name="android.intent.action.TTS_SERVICE" />
  </intent>
</queries>
```

Add missing permissions (recommended by `speech_to_text` for Bluetooth headset support):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

### iOS (`ios/Runner/Info.plist`)

Add missing permission descriptions (required for STT, will crash without them):
```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>Spark uses speech recognition to convert your voice into text.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Spark needs microphone access for speech recognition.</string>
```

---

## 3. TTS Provider

**New file: `lib/features/chat/tts_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsController {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _speakingMessageId;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  Future<void> speak(String messageId, String text) async {
    await init();
    if (_speakingMessageId == messageId) {
      await stop();
      return;
    }
    await _tts.stop();
    _speakingMessageId = messageId;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _speakingMessageId = null;
  }

  bool isSpeaking(String messageId) => _speakingMessageId == messageId;

  void dispose() {
    _tts.stop();
  }
}

final ttsControllerProvider = Provider<TtsController>((ref) {
  final controller = TtsController();
  ref.onDispose(controller.dispose);
  return controller;
});

// Notifier to track which message is currently speaking
class TtsStateNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String messageId, String text) {
    final tts = ref.read(ttsControllerProvider);
    if (state == messageId) {
      tts.stop();
      state = null;
    } else {
      tts.speak(messageId, text);
      state = messageId;
    }
  }

  void stop() {
    ref.read(ttsControllerProvider).stop();
    state = null;
  }
}

final ttsStateProvider = NotifierProvider<TtsStateNotifier, String?>(
  TtsStateNotifier.new,
);
```

---

## 4. Speaker Button on Message Bubbles

**File: `lib/features/chat/chat_screen.dart`**

### Location: Assistant message action row (after the message content, ~line 800-850 area in `_buildMessageBubble` or similar)

Add speaker icon button next to existing actions (copy, etc.):

```dart
Consumer(
  builder: (context, ref, _) {
    final speakingId = ref.watch(ttsStateProvider);
    final isSpeaking = speakingId == message.id;
    return GestureDetector(
      onTap: () {
        final plainText = message.text ?? '';
        if (plainText.isNotEmpty) {
          ref.read(ttsStateProvider.notifier).toggle(message.id, plainText);
        }
      },
      child: Icon(
        isSpeaking ? LucideIcons.volumeX : LucideIcons.volume2,
        size: 16,
        color: colorScheme.mutedForeground,
      ),
    );
  },
)
```

### When message starts streaming, stop TTS:
In the SSE handler for `message.updated` or `message.part.updated`, call:
```dart
ref.read(ttsStateProvider.notifier).stop();
```

---

## 5. Cleanup

- `_Composer.dispose()` — already calls `_speech.cancel()` for STT, no TTS cleanup needed there
- `TtsController.dispose()` — called via `ref.onDispose` in the provider
- App lifecycle `didChangeAppLifecycleState` — stop TTS when app goes to background

---

## 6. Files to Create/Modify

| File | Action | Lines (est.) |
|------|--------|-------------|
| `pubspec.yaml` | Add `flutter_tts` | 1 |
| `android/app/src/main/AndroidManifest.xml` | Add queries + permissions | 8 |
| `ios/Runner/Info.plist` | Add permission descriptions | 4 |
| `lib/features/chat/tts_provider.dart` | **New** — TTS controller + providers | ~60 |
| `lib/features/chat/chat_screen.dart` | Add speaker button, import TTS provider | ~20 |

**Estimated total: ~93 lines**

---

## 7. Testing Checklist

- [ ] Speaker icon appears on assistant messages
- [ ] Tap speaker → text is read aloud
- [ ] Tap speaker again while speaking → stops
- [ ] Tap different message → previous stops, new one starts
- [ ] TTS stops when app goes to background
- [ ] TTS stops when new message starts streaming
- [ ] Works on Android emulator
- [ ] Works on iOS simulator
- [ ] No TTS errors on messages with markdown/code blocks (strip markdown before speaking)

---

## 8. Future Enhancements (v2)

- Speed slider in settings (0.0–1.0 via `setSpeechRate`)
- Voice picker (`getVoices` + `setVoice`)
- Auto-read mode toggle (speak new assistant messages automatically)
- Word-by-word highlighting using `setProgressHandler`
- Strip markdown/code before speaking for cleaner audio