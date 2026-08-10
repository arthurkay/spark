import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/message.dart';

const _ttsSessionTitle = '[TTS Preprocessing]';
const _minTextForLlm = 20;

enum TtsStatus { idle, playing, paused }

class TtsProgress {
  const TtsProgress(
      {required this.start, required this.end, required this.word});
  final int start;
  final int end;
  final String word;
}

class TtsState {
  const TtsState({
    this.status = TtsStatus.idle,
    this.messageId,
    this.text,
    this.progress,
  });

  final TtsStatus status;
  final String? messageId;
  final String? text;
  final TtsProgress? progress;

  TtsState copyWith({
    TtsStatus? status,
    String? messageId,
    String? text,
    bool clearText = false,
    TtsProgress? progress,
    bool clearProgress = false,
  }) {
    return TtsState(
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
      text: clearText ? null : (text ?? this.text),
      progress: clearProgress ? null : (progress ?? this.progress),
    );
  }
}

class TtsController {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _sessionId;
  void Function(TtsState)? _onStateChange;
  TtsState _current = const TtsState();

  void setOnStateChange(void Function(TtsState) cb) => _onStateChange = cb;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() {
      _updateState(_current.copyWith(status: TtsStatus.playing));
    });
    _tts.setCompletionHandler(() {
      _updateState(
        const TtsState(status: TtsStatus.idle),
      );
    });
    _tts.setPauseHandler(() {
      _updateState(_current.copyWith(status: TtsStatus.paused));
    });
    _tts.setCancelHandler(() {
      _updateState(
        const TtsState(status: TtsStatus.idle),
      );
    });
    _tts.setProgressHandler((text, start, end, word) {
      _updateState(
        _current.copyWith(
          progress: TtsProgress(start: start, end: end, word: word),
        ),
      );
    });
    _initialized = true;
  }

  void _updateState(TtsState state) {
    _current = state;
    _onStateChange?.call(state);
  }

  Future<void> speak(String text,
      {OpencodeClient? client, String? messageId}) async {
    await init();
    var processed = _preprocessForSpeech(text);
    if (client != null && processed.length >= _minTextForLlm) {
      processed = await _llmRewrite(client, processed) ?? processed;
    }
    _updateState(
      TtsState(
        status: TtsStatus.playing,
        messageId: messageId,
        text: processed.length > 120
            ? '${processed.substring(0, 120)}...'
            : processed,
      ),
    );
    await _tts.speak(processed);
  }

  Future<void> pause() async {
    await _tts.pause();
  }

  Future<void> resume() async {
    await init();
    _updateState(_current.copyWith(status: TtsStatus.playing));
    await _tts.speak('');
  }

  Future<void> stop() async {
    await _tts.stop();
    _updateState(const TtsState(status: TtsStatus.idle));
  }

  void dispose() {
    _tts.stop();
  }

  Future<String?> _getOrCreateSessionId(OpencodeClient client) async {
    if (_sessionId != null) return _sessionId;
    try {
      final sessions = await client.listSessions();
      for (final s in sessions) {
        if (s.title == _ttsSessionTitle) {
          _sessionId = s.id;
          return _sessionId;
        }
      }
    } catch (_) {}
    try {
      final session = await client.createSession(title: _ttsSessionTitle);
      _sessionId = session.id;
      return _sessionId;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _llmRewrite(OpencodeClient client, String text) async {
    final sessionId = await _getOrCreateSessionId(client);
    if (sessionId == null) return null;
    try {
      final response = await client.sendMessage(
        sessionId: sessionId,
        text: 'Rewrite the following text for natural text-to-speech. '
            'Remove all markdown, code artifacts, and technical formatting. '
            'Add natural pauses with commas where appropriate. '
            'Convert jargon to conversational language. '
            'Output ONLY the rewritten text, nothing else.\n\n$text',
      );
      final rewritten = response.parts
          .where(
              (p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
          .map((p) => p.text!)
          .join('\n\n');
      return rewritten.isNotEmpty ? rewritten : null;
    } catch (_) {
      return null;
    }
  }

  static String _preprocessForSpeech(String text) {
    var s = text;
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    s = s.replaceAll(RegExp(r'`([^`]*)`'), r'\1');
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'\1');
    s = s.replaceAll(RegExp(r'https?://\S+'), 'link');
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\*\*([^*]*)\*\*'), r'\1');
    s = s.replaceAll(RegExp(r'\*([^*]*)\*'), r'\1');
    s = s.replaceAll(RegExp(r'__([^_]*)__'), r'\1');
    s = s.replaceAll(RegExp(r'_([^_]*)_'), r'\1');
    s = s.replaceAll(RegExp(r'~~([^~]*)~~'), r'\1');
    s = s.replaceAll(RegExp(r'^>\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\|[^|]+\|', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^[-: ]+\|[-: ]+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    return s.trim();
  }
}

final ttsControllerProvider = Provider<TtsController>((ref) {
  final controller = TtsController();
  ref.onDispose(controller.dispose);
  return controller;
});

class TtsStateNotifier extends Notifier<TtsState> {
  @override
  TtsState build() {
    final controller = ref.read(ttsControllerProvider);
    controller.setOnStateChange((s) {
      state = s;
    });
    return const TtsState();
  }

  void toggle(MessageWithParts message) {
    final text = message.parts
        .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
        .map((p) => p.text!)
        .join('\n\n');
    if (text.isEmpty) return;

    final tts = ref.read(ttsControllerProvider);
    final client = ref.read(opencodeClientProvider);
    if (state.status != TtsStatus.idle && state.messageId == message.info.id) {
      tts.stop();
    } else {
      tts.speak(text, client: client, messageId: message.info.id);
    }
  }

  void pause() {
    ref.read(ttsControllerProvider).pause();
  }

  void resume() {
    ref.read(ttsControllerProvider).resume();
  }

  void stop() {
    ref.read(ttsControllerProvider).stop();
  }
}

final ttsStateProvider = NotifierProvider<TtsStateNotifier, TtsState>(
  TtsStateNotifier.new,
);
