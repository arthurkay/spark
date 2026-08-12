import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/message.dart';
import '../../core/storage/settings_store.dart';
import 'tts_cache.dart';

const _ttsSessionTitle = '[TTS Preprocessing]';
const _minTextForLlm = 20;

enum TtsStatus { idle, processing, playing, paused }

/// Word-level progress deliberately isn't part of this state — it changes dozens
/// of times a sentence, and putting it here would rebuild every listener on each
/// word. It lives on [TtsController.progress], a notifier only the transcript
/// view watches.
class TtsState {
  const TtsState({
    this.status = TtsStatus.idle,
    this.messageId,
    this.text,
    this.fullText,
    this.sourceText,
  });

  final TtsStatus status;
  final String? messageId;

  /// Truncated preview of what is being spoken, for the collapsed player.
  final String? text;

  /// The whole narration, for the expanded transcript. Changes once per
  /// utterance, so it belongs in the state rather than the progress notifier.
  final String? fullText;

  /// The original message markdown, for the expanded player's Original tab.
  /// The narration paraphrases — code blocks, tables and other visual content
  /// exist only here.
  final String? sourceText;

  TtsState copyWith({
    TtsStatus? status,
    String? messageId,
    String? text,
    String? fullText,
    String? sourceText,
    bool clearText = false,
  }) {
    return TtsState(
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
      text: clearText ? null : (text ?? this.text),
      fullText: clearText ? null : (fullText ?? this.fullText),
      sourceText: clearText ? null : (sourceText ?? this.sourceText),
    );
  }
}

/// Where narration has reached, as character offsets into [TtsState.fullText].
class TtsProgress {
  const TtsProgress({required this.start, required this.end});

  /// Offsets into the *full* narration, not the current utterance — resuming
  /// re-speaks a substring, so the controller rebases these.
  final int start;
  final int end;
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

  /// Where the current bounded utterance ends within [_fullText]; the
  /// completion handler continues from here until the end of the text.
  int _chunkEnd = 0;

  int get _resumeOffset => _speechBase + _wordStart;

  /// Word-level position, watched only by the transcript view.
  final ValueNotifier<TtsProgress?> progress = ValueNotifier(null);

  /// Set while deliberately replacing the current utterance (seeking): the
  /// engine reports the flushed utterance as cancelled, which must not be
  /// mistaken for the user stopping narration.
  bool _expectInterruption = false;

  void setOnStateChange(void Function(TtsState) cb) => _onStateChange = cb;

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setStartHandler(() {
      // A new utterance is audibly underway; any cancel after this is real.
      _expectInterruption = false;
      _updateState(_current.copyWith(status: TtsStatus.playing));
    });
    _tts.setCompletionHandler(() {
      // Completion of a *chunk*, not necessarily of the narration: long text is
      // spoken in bounded utterances (see [nextChunkEnd]), so keep going until
      // the chunk that ends at the end of the text.
      final text = _fullText;
      if (text != null && _chunkEnd < text.length) {
        unawaited(_speakFrom(_chunkEnd));
        return;
      }
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    });
    _tts.setPauseHandler(() {
      _updateState(_current.copyWith(status: TtsStatus.paused));
    });
    _tts.setCancelHandler(() {
      if (_expectInterruption) {
        _expectInterruption = false;
        return;
      }
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    });
    // Without this, an engine failure leaves the player claiming playback of
    // audio that will never arrive.
    _tts.setErrorHandler((message) {
      debugPrint('TTS error: $message');
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    });
    // Published on its own notifier rather than through [TtsState]: this fires
    // per word, and only the transcript view watches it, so playback never
    // rebuilds the rest of the app.
    _tts.setProgressHandler((text, start, end, word) {
      _wordStart = start;
      progress.value = TtsProgress(
        start: _speechBase + start,
        end: _speechBase + end,
      );
    });
    _initialized = true;
  }

  void _clearUtterance() {
    _fullText = null;
    _speechBase = 0;
    _wordStart = 0;
    _chunkEnd = 0;
    progress.value = null;
  }

  /// The device's voices, parsed defensively — the platform hands back
  /// loosely-typed maps.
  Future<List<TtsVoice>> availableVoices() async {
    await init();
    return parseVoices(await _tts.getVoices);
  }

  /// Persists and applies [voice]; null returns to the engine default.
  Future<void> setVoiceSelection(TtsVoice? voice) async {
    await init();
    final store = SettingsStore();
    if (voice == null) {
      await store.clearTtsVoice();
      await _tts.clearVoice();
    } else {
      await store.saveTtsVoice(voice.name, voice.locale);
      await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    }
  }

  /// Speaks a short standalone phrase — voice mode's thinking fillers.
  ///
  /// Deliberately outside the narration pipeline: no LLM rewrite (that is the
  /// very thing being waited on), no cache, no [TtsState] bookkeeping beyond
  /// what the engine handlers do on their own. Uses the selected voice so the
  /// filler sounds like the narrator.
  Future<void> speakFiller(String text) async {
    await init();
    await _applyPersistedVoice();
    // May flush a previous filler still tailing off.
    _expectInterruption = true;
    await _tts.speak(text);
  }

  /// Speaks a short sample in [voice] without touching the persisted choice —
  /// [speak] re-applies the persisted voice, so a preview can't leak into
  /// narration. No client and no messageId: no LLM call, no cache write.
  Future<void> previewVoice(TtsVoice voice) async {
    await stop();
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    await _tts.speak('This is how narration will sound.');
  }

  Future<void> _applyPersistedVoice() async {
    final voice = await SettingsStore().loadTtsVoice();
    if (voice == null) {
      await _tts.clearVoice();
    } else {
      await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    }
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
    // Once per narration, not per chunk: previews from the settings sheet
    // change the engine's voice, so re-applying the persisted choice here keeps
    // engine state deterministic.
    await _applyPersistedVoice();

    var processed = _preprocessForSpeech(text);

    // A narration already generated for this message is reused verbatim: the
    // rewrite is a full model round-trip behind a blocking overlay, and the
    // result only depends on the message text.
    final cached = messageId == null
        ? null
        : await NarrationCache.instance.read(messageId, processed);
    if (cached != null) {
      if (generation != _generation) return;
      await _play(cached, messageId: messageId, sourceText: text);
      return;
    }

    final needsLlm = client != null && processed.length >= _minTextForLlm;
    if (needsLlm) {
      _updateState(TtsState(
        status: TtsStatus.processing,
        messageId: messageId,
        text: _preview(text),
        sourceText: text,
      ));
      final rewritten = await _llmRewrite(client, processed);
      // The rewrite takes seconds, and the overlay invites the user to cancel
      // during it. Without this check the cancelled utterance would start
      // speaking the moment the request came back.
      if (generation != _generation) return;
      if (rewritten != null) {
        processed = rewritten;
        if (messageId != null) {
          // Keyed on the pre-rewrite text, which is what the next lookup has.
          await NarrationCache.instance
              .write(messageId, _preprocessForSpeech(text), rewritten);
        }
      }
    }

    if (generation != _generation) return;
    await _play(processed, messageId: messageId, sourceText: text);
  }

  Future<void> _play(String narration,
      {String? messageId, String? sourceText}) async {
    _fullText = narration;
    progress.value = null;
    // Starting narration may flush something already speaking — a thinking
    // filler, or a previous narration. The engine reports the flushed
    // utterance as cancelled; without this it would wipe the state just set.
    _expectInterruption = true;
    _updateState(TtsState(
      status: TtsStatus.playing,
      messageId: messageId,
      text: _preview(narration),
      fullText: narration,
      sourceText: sourceText,
    ));
    await _speakFrom(0);
  }

  /// Speaks the bounded chunk of [_fullText] starting at [offset].
  ///
  /// Android's TextToSpeech rejects utterances longer than
  /// getMaxSpeechInputLength() (4000 chars) — and flutter_tts's failure path
  /// never completes the platform call, so a long narration used to hang
  /// silently with the player claiming playback. Bounded chunks, chained by the
  /// completion handler, keep every utterance under the limit.
  Future<void> _speakFrom(int offset) async {
    final text = _fullText;
    if (text == null) return;
    final start = offset.clamp(0, text.length);
    if (start >= text.length || text.substring(start).trim().isEmpty) {
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
      return;
    }
    _speechBase = start;
    _wordStart = 0;
    _chunkEnd = nextChunkEnd(text, start);
    final result = await _tts.speak(text.substring(start, _chunkEnd));
    // The Android side answers 1 for accepted, 0 for refused-outright.
    if (result == 0) {
      _clearUtterance();
      _updateState(const TtsState(status: TtsStatus.idle));
    }
  }

  Future<void> pause() async {
    await _tts.pause();
  }

  /// Re-speaks from where playback stopped: flutter_tts exposes `speak`,
  /// `pause` and `stop` only — there is no resume, and speaking an empty string
  /// just fires the completion handler and ends the utterance.
  Future<void> resume() async {
    await init();
    if (_fullText == null) return;
    _updateState(_current.copyWith(status: TtsStatus.playing));
    await _speakFrom(_resumeOffset);
  }

  /// Jumps narration to [offset] within the current text. Works while playing
  /// or paused — the new utterance starts immediately either way.
  Future<void> seekTo(int offset) async {
    final text = _fullText;
    if (text == null) return;
    _expectInterruption = true;
    // Reflect the jump instantly; the engine's first progress event follows.
    final clamped = offset.clamp(0, text.length);
    progress.value = TtsProgress(start: clamped, end: clamped);
    await _speakFrom(clamped);
  }

  Future<void> stop() async {
    _generation++;
    _clearUtterance();
    await _tts.stop();
    _updateState(const TtsState(status: TtsStatus.idle));
  }

  void dispose() {
    _tts.stop();
    progress.dispose();
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

  /// Narrates [message] unconditionally — voice mode's counterpart of
  /// [toggle], which flips between play and stop for the same message.
  void narrate(MessageWithParts message) {
    final text = message.parts
        .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
        .map((p) => p.text!)
        .join('\n\n');
    if (text.isEmpty) return;
    ref.read(ttsControllerProvider).speak(
          text,
          client: ref.read(opencodeClientProvider),
          messageId: message.info.id,
        );
  }

  /// Stops playback and waits for the engine, so voice mode starts clean.
  Future<void> stopForVoiceMode() => ref.read(ttsControllerProvider).stop();

  /// Seeks to a fraction of the narration, from the player's seek bar.
  void seek(double fraction) {
    final length = state.fullText?.length ?? 0;
    if (length == 0) return;
    ref
        .read(ttsControllerProvider)
        .seekTo((fraction.clamp(0.0, 1.0) * length).round());
  }
}

final ttsStateProvider = NotifierProvider<TtsStateNotifier, TtsState>(
  TtsStateNotifier.new,
);

/// True while the voice-conversation screen owns audio; the global player
/// overlay hides itself so the two surfaces don't duplicate controls.
final voiceModeActiveProvider = StateProvider<bool>((ref) => false);

/// One selectable engine voice.
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Parses the loosely-typed voice list the platform returns.
///
/// Entries missing a name or locale are skipped, duplicates collapse, and the
/// result sorts by locale then name so the picker is stable across launches.
/// Garbage input yields an empty list rather than a throw.
List<TtsVoice> parseVoices(dynamic raw) {
  if (raw is! List) return const [];
  final seen = <TtsVoice>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    final locale = entry['locale'];
    if (name is! String || name.isEmpty) continue;
    if (locale is! String || locale.isEmpty) continue;
    seen.add(TtsVoice(name: name, locale: locale));
  }
  final voices = seen.toList()
    ..sort((a, b) {
      final byLocale = a.locale.compareTo(b.locale);
      return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
    });
  return voices;
}

/// End index of the utterance chunk starting at [start].
///
/// Kept comfortably under Android's 4000-char utterance limit, and cut at a
/// sentence end where one exists in the window so the seam between utterances
/// lands where a pause belongs; falls back to a word boundary, then a hard cut.
/// Walking this from 0 covers the text exactly — no gaps, no overlaps.
int nextChunkEnd(String text, int start, {int max = 3500}) {
  if (text.length - start <= max) return text.length;
  final window = text.substring(start, start + max);
  // Only accept a boundary past a quarter of the window: a boundary near the
  // very start would degenerate into hundreds of tiny utterances.
  final floor = max ~/ 4;
  for (final boundary in const ['. ', '.\n', '! ', '? ', '\n']) {
    final i = window.lastIndexOf(boundary);
    if (i > floor) return start + i + boundary.length;
  }
  final space = window.lastIndexOf(' ');
  if (space > floor) return start + space + 1;
  return start + max;
}

/// Test hook for the markdown stripping above.
String debugPreprocessForSpeech(String text) =>
    TtsController._preprocessForSpeech(text);
