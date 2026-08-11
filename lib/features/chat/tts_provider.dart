import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/message.dart';

const _ttsSessionTitle = '[TTS Preprocessing]';
const _minTextForLlm = 20;

enum TtsStatus { idle, processing, playing, paused }

/// Word-level progress deliberately isn't part of this state — see the progress
/// handler in [TtsController.init]. It lives in the controller instead, so
/// playback doesn't rebuild every listener once per spoken word.
class TtsState {
  const TtsState({
    this.status = TtsStatus.idle,
    this.messageId,
    this.text,
  });

  final TtsStatus status;
  final String? messageId;

  /// Truncated preview of what is being spoken, for the mini player.
  final String? text;

  TtsState copyWith({
    TtsStatus? status,
    String? messageId,
    String? text,
    bool clearText = false,
  }) {
    return TtsState(
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
      text: clearText ? null : (text ?? this.text),
    );
  }
}

class TtsController {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _sessionId;
  void Function(TtsState)? _onStateChange;
  TtsState _current = const TtsState();

  /// Bumped by [stop] so an utterance whose LLM rewrite is still in flight
  /// knows it was cancelled and must not start speaking when the call returns.
  int _generation = 0;

  /// The full text of the current utterance. [TtsState.text] only carries a
  /// truncated preview for the mini player, so [resume] can't use it.
  String? _fullText;

  /// Where the currently-speaking substring starts within [_fullText], and how
  /// far into that substring playback has reached. flutter_tts has no resume
  /// primitive, so resuming means re-speaking from their sum.
  int _speechBase = 0;
  int _wordStart = 0;

  int get _resumeOffset => _speechBase + _wordStart;

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
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    });
    _tts.setPauseHandler(() {
      _updateState(_current.copyWith(status: TtsStatus.paused));
    });
    _tts.setCancelHandler(() {
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    });
    // Progress is recorded, not published: nothing renders the spoken word, and
    // pushing a new state per word rebuilt the mini player and overlay dozens
    // of times a sentence. [resume] is the only consumer.
    _tts.setProgressHandler((text, start, end, word) {
      _wordStart = start;
    });
    _initialized = true;
  }

  void _clearUtterance() {
    _fullText = null;
    _speechBase = 0;
    _wordStart = 0;
  }

  static String _preview(String text) =>
      text.length > 120 ? '${text.substring(0, 120)}...' : text;

  void _updateState(TtsState state) {
    _current = state;
    _onStateChange?.call(state);
  }

  Future<void> speak(String text,
      {OpencodeClient? client, String? messageId}) async {
    await init();
    final generation = ++_generation;

    var processed = _preprocessForSpeech(text);
    final needsLlm = client != null && processed.length >= _minTextForLlm;

    if (needsLlm) {
      _updateState(TtsState(
        status: TtsStatus.processing,
        messageId: messageId,
        text: _preview(text),
      ));
      processed = await _llmRewrite(client, processed) ?? processed;
      // The rewrite takes seconds, and the overlay invites the user to cancel
      // during it. Without this check the cancelled utterance would start
      // speaking the moment the request came back.
      if (generation != _generation) return;
    }

    _fullText = processed;
    _speechBase = 0;
    _wordStart = 0;
    _updateState(TtsState(
      status: TtsStatus.playing,
      messageId: messageId,
      text: _preview(processed),
    ));
    await _tts.speak(processed);
  }

  Future<void> pause() async {
    await _tts.pause();
  }

  /// Re-speaks from where playback stopped: flutter_tts exposes `speak`,
  /// `pause` and `stop` only — there is no resume, and speaking an empty string
  /// just fires the completion handler and ends the utterance.
  Future<void> resume() async {
    await init();
    final text = _fullText;
    if (text == null) return;
    final offset = _resumeOffset.clamp(0, text.length);
    final remaining = text.substring(offset);
    if (remaining.trim().isEmpty) {
      await stop();
      return;
    }
    _speechBase = offset;
    _wordStart = 0;
    _updateState(_current.copyWith(status: TtsStatus.playing));
    await _tts.speak(remaining);
  }

  Future<void> stop() async {
    _generation++;
    _clearUtterance();
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
        text:
            'Rewrite the following text for natural text-to-speech narration. '
            'Your goal is to produce text that sounds like a warm, articulate '
            'human speaking naturally.\n\n'
            'Rules:\n'
            '- Write in flowing prose, never bullet points or lists\n'
            '- Use commas for brief pauses, em-dashes for dramatic pauses, '
            'ellipses for trailing off\n'
            '- Add natural emphasis: slightly rephrase key points so they '
            'land with weight\n'
            '- Vary sentence length — mix short punchy sentences with longer '
            'flowing ones\n'
            '- Use contractions (don\'t, it\'s, we\'ll) and conversational '
            'connectors (so, now, here\'s the thing, what\'s interesting is)\n'
            '- For code or technical content, describe it conceptually, never '
            'read syntax (say "a function that sorts a list" not "open brace, '
            'def sort, open paren")\n'
            '- Convert markdown formatting to spoken equivalents:\n'
            '  - "heading:" → say it like a title, add a pause after\n'
            '  - "bold text" → rephrase to emphasize naturally\n'
            '  - "code block" → summarize what the code does\n'
            '  - "link" → say "linked at..." or omit\n'
            '- If the text is a list, convert to flowing narrative ("First we '
            'do X, then Y, and finally Z")\n'
            '- End with a natural cadence — don\'t trail off mid-thought\n\n'
            'Output ONLY the rewritten text. No quotes, no labels, no explanation.\n\n'
            '$text',
      );
      final rewritten = response.parts
          .where(
              (p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
          .map((p) => p.text!)
          .join('\n\n');
      unawaited(client.compactSession(sessionId));
      return rewritten.isNotEmpty ? rewritten : null;
    } catch (_) {
      return null;
    }
  }

  /// Strips markdown down to something worth speaking.
  ///
  /// Patterns that *unwrap* their content must use [String.replaceAllMapped]:
  /// Dart's [String.replaceAll] takes a literal replacement and has no
  /// backreference support, so `r'\1'` used to substitute the two characters
  /// `\1` for the emphasized word rather than keeping it — silently deleting
  /// every bold, italic, inline-code and link text before it was ever spoken.
  static String _preprocessForSpeech(String text) {
    String unwrap(Match m) => m[1] ?? '';
    var s = text;
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    s = s.replaceAllMapped(RegExp(r'`([^`]*)`'), unwrap);
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), unwrap);
    s = s.replaceAll(RegExp(r'https?://\S+'), 'link');
    s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    s = s.replaceAllMapped(RegExp(r'\*\*([^*]*)\*\*'), unwrap);
    s = s.replaceAllMapped(RegExp(r'\*([^*]*)\*'), unwrap);
    s = s.replaceAllMapped(RegExp(r'__([^_]*)__'), unwrap);
    s = s.replaceAllMapped(RegExp(r'_([^_]*)_'), unwrap);
    s = s.replaceAllMapped(RegExp(r'~~([^~]*)~~'), unwrap);
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

/// Test hook for the markdown stripping above.
String debugPreprocessForSpeech(String text) =>
    TtsController._preprocessForSpeech(text);
