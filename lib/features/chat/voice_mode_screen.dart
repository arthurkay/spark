import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/message.dart';
import '../../shared/haptics.dart';
import '../models/models_provider.dart';
import 'chat_provider.dart';
import 'tts_equalizer.dart';
import 'tts_provider.dart';

/// What the conversation loop is doing. One phase at a time, in a cycle:
/// listening → sending/waiting → speaking → listening…
enum VoicePhase { starting, listening, waiting, speaking, error }

/// The completed assistant reply that should be narrated next, or null.
///
/// Narrate only a *finished*, clean assistant message at the tail that hasn't
/// been narrated yet — a stream still in flight, an errored turn, or the reply
/// we just finished speaking all return null. Top-level and pure for tests.
MessageWithParts? replyToNarrate(
  List<MessageWithParts> messages,
  String? lastNarratedId,
) {
  if (messages.isEmpty) return null;
  final last = messages.last;
  final info = last.info;
  if (info.role != 'assistant') return null;
  if (info.timeCompleted == null || info.hasError) return null;
  if (info.id == lastNarratedId) return null;
  final text = last.parts
      .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
      .map((p) => p.text!)
      .join('\n\n');
  if (text.trim().isEmpty) return null;
  return last;
}

/// What to say while the agent works. Step 0 acknowledges the request; later
/// steps reassure. [salt] varies the pick between turns so consecutive waits
/// don't sound scripted, and phrases in [used] are skipped while any unused
/// remain — a person doesn't say "still working on it" the same way twice in
/// one conversation.
String fillerPhrase(int step, int salt, {Set<String> used = const {}}) {
  const openers = [
    'Alright, let me work on that.',
    'Okay, on it.',
    'Let me think that through.',
    'Sure — give me a moment.',
    'Right, looking into it.',
    'Good question, let me dig in.',
  ];
  const continuers = [
    'Still working on it.',
    'Just a moment more.',
    'Still thinking this through.',
    'Working through it now.',
    'Nearly there — still going.',
    'Bear with me, this one takes a bit.',
    'Making progress on it.',
    'Hang on, almost sorted.',
    'Taking a little longer than usual.',
    'Still at it.',
  ];
  final pool = step == 0 ? openers : continuers;
  final start = step == 0 ? salt : salt + step;
  for (var i = 0; i < pool.length; i++) {
    final candidate = pool[(start + i) % pool.length];
    if (!used.contains(candidate)) return candidate;
  }
  // Everything has been said once; cycle rather than fall silent.
  return pool[start % pool.length];
}

/// A live description of what the in-flight turn is doing, derived from its
/// streaming parts — so the wait can say "reading rollback.go" instead of a
/// generic reassurance.
class VoiceActivity {
  const VoiceActivity({required this.spoken, required this.shown});

  /// Short phrase suitable for speech, or null when only display text exists.
  final String? spoken;

  /// Text for the transcript slot: the reasoning tail, the answer starting to
  /// stream, or the tool line.
  final String shown;
}

/// Describes the tail message of an in-flight turn, newest activity first:
/// the answer streaming beats reasoning, which beats tool calls. Returns null
/// when the tail is not a generating assistant message or shows nothing yet.
VoiceActivity? describeActivity(MessageWithParts? tail) {
  if (tail == null) return null;
  final info = tail.info;
  if (info.role != 'assistant' || info.timeCompleted != null) return null;

  String? toolLine;
  String? reasoningTail;
  String? rawReasoning;
  String? answerTail;
  for (final part in tail.parts) {
    switch (part.type) {
      case 'tool':
        final line = _toolPhrase(part);
        if (line != null) toolLine = line;
      case 'reasoning':
        final text = part.text?.trim();
        if (text != null && text.isNotEmpty) {
          rawReasoning = text;
          reasoningTail = _tail(text);
        }
      case 'text':
        final text = part.text?.trim();
        if (text != null && text.isNotEmpty) answerTail = _tail(text);
    }
  }

  if (answerTail != null) {
    return VoiceActivity(
      spoken: 'The answer is coming together now.',
      shown: answerTail,
    );
  }
  if (reasoningTail != null) {
    // Voice the model's actual thought when a complete sentence exists —
    // insight into the mental process beats reassurance. Otherwise stay
    // grounded in what is known.
    final thought = speakableThought(rawReasoning ?? '');
    return VoiceActivity(
      spoken: thought ??
          (toolLine == null ? 'Thinking it through now.' : "I'm $toolLine."),
      shown: reasoningTail,
    );
  }
  if (toolLine != null) {
    return VoiceActivity(spoken: "I'm $toolLine.", shown: '$toolLine…');
  }
  return null;
}

/// "reading main.go", "running a command" — from the tool part's name and
/// input, defensively parsed.
String? _toolPhrase(MessagePart part) {
  final rawState = part.raw['state'];
  final input = rawState is Map<String, dynamic> ? rawState['input'] : null;
  String? path;
  if (input is Map) {
    final p = input['filePath'] ?? input['path'] ?? input['pattern'];
    if (p is String && p.isNotEmpty) path = p.split('/').last;
  }
  return switch (part.toolName) {
    'read' => path == null ? 'reading a file' : 'reading $path',
    'edit' || 'write' => path == null ? 'making an edit' : 'editing $path',
    'bash' => 'running a command',
    'grep' || 'glob' => 'searching the code',
    'webfetch' || 'websearch' => 'looking something up',
    'task' => 'delegating a subtask',
    'todowrite' => 'planning the steps',
    null => null,
    _ => 'using ${part.toolName}',
  };
}

/// The most recent *complete* sentence of streamed reasoning, cleaned for
/// speech — so the wait voices the model's actual thought ("The handler needs
/// a null check first.") rather than a canned phrase. Null when no full
/// sentence exists yet, or the candidate is too short or too long to speak
/// well; callers fall back to the generic filler.
String? speakableThought(String reasoning) {
  // Strip what reads fine but speaks badly: code spans, markdown emphasis.
  final cleaned = reasoning
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll('`', '')
      .replaceAll(RegExp(r'[*_#]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final matches = RegExp(r'[^.!?]+[.!?]').allMatches(cleaned).toList();
  if (matches.isEmpty) return null;
  final sentence = matches.last.group(0)!.trim();
  if (sentence.length < 12 || sentence.length > 160) return null;
  return sentence;
}

/// The last ~140 chars, starting cleanly after a word boundary.
String _tail(String text) {
  if (text.length <= 140) return text;
  final cut = text.substring(text.length - 140);
  final space = cut.indexOf(' ');
  return '…${space > 0 && space < 40 ? cut.substring(space + 1) : cut}';
}

class VoiceModeScreen extends ConsumerStatefulWidget {
  const VoiceModeScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends ConsumerState<VoiceModeScreen>
    with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  VoicePhase _phase = VoicePhase.starting;
  String _partial = '';
  String? _lastNarratedId;
  bool _closing = false;

  /// Long turns are dead air without them: a spoken acknowledgment shortly
  /// after sending, then periodic reassurance until the reply arrives.
  Timer? _fillerTimer;
  int _fillerStep = 0;
  int _fillerSalt = 0;
  String _fillerText = '';
  String? _lastFillerSpoken;
  VoiceActivity? _activity;

  /// Everything spoken as filler this conversation, so nothing repeats until
  /// the pool is exhausted.
  final Set<String> _usedFillers = {};
  late final AnimationController _thinkingPulse;

  @override
  void initState() {
    super.initState();
    // Voice mode narrates through its own surface; the global player bar
    // underneath it would just duplicate the controls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(voiceModeActiveProvider.notifier).state = true;
    });
    // A conversation is hands-free by definition; the screen stays on.
    WakelockPlus.enable();
    _thinkingPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    _fillerTimer?.cancel();
    _thinkingPulse.dispose();
    _speech.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  /// First filler ~5s in (a fast reply shouldn't get one at all), then with a
  /// growing backoff — a person interjects less, not more, the longer they
  /// work. Each fires only if the turn is still in flight.
  void _scheduleFiller() {
    _fillerTimer?.cancel();
    final delay = _fillerStep == 0
        ? const Duration(seconds: 5)
        : Duration(
            seconds:
                math.min(12 + _fillerStep * 6, 35) + math.Random().nextInt(6));
    _fillerTimer = Timer(delay, () {
      if (!mounted || _closing || _phase != VoicePhase.waiting) return;
      // Prefer what the turn is actually doing; fall back to reassurance. A
      // long-running tool would repeat itself verbatim, which sounds robotic —
      // alternate with the generic phrases instead.
      final live = _activity?.spoken;
      final phrase = (live != null && live != _lastFillerSpoken)
          ? live
          : fillerPhrase(_fillerStep, _fillerSalt, used: _usedFillers);
      _lastFillerSpoken = phrase;
      _usedFillers.add(phrase);
      setState(() => _fillerText = phrase);
      ref.read(ttsControllerProvider).speakFiller(phrase);
      _fillerStep++;
      _scheduleFiller();
    });
  }

  void _stopFillers() {
    _fillerTimer?.cancel();
    _fillerTimer = null;
    _fillerText = '';
    _lastFillerSpoken = null;
    _activity = null;
  }

  Future<void> _start() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (_) {
        if (mounted && _phase == VoicePhase.listening) {
          setState(() => _phase = VoicePhase.error);
        }
      },
    );
    if (!mounted) return;
    if (!available) {
      setState(() => _phase = VoicePhase.error);
      return;
    }
    // Interrupt any Read Aloud narration; this screen owns audio now.
    await ref.read(ttsStateProvider.notifier).stopForVoiceMode();
    await _listen();
  }

  void _onSpeechStatus(String status) {
    // 'done' arrives after the final result; the result handler drives the
    // send, so nothing to do here unless nothing was recognized.
    if (!mounted || _closing) return;
    if (status == 'notListening' &&
        _phase == VoicePhase.listening &&
        _partial.trim().isEmpty) {
      // Mic closed with silence — reopen rather than dead-end.
      _listen();
    }
  }

  Future<void> _listen() async {
    if (!mounted || _closing) return;
    _stopFillers();
    setState(() {
      _phase = VoicePhase.listening;
      _partial = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted || _closing) return;
        setState(() => _partial = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _send(result.recognizedWords.trim());
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> _send(String text) async {
    Haptics.tap();
    setState(() => _phase = VoicePhase.waiting);
    _fillerStep = 0;
    _fillerSalt = math.Random().nextInt(1 << 16);
    _scheduleFiller();
    await _speech.stop();
    final model = ref.read(selectedModelProvider(widget.sessionId));
    final agent = ref.read(selectedAgentProvider) ??
        ref.read(defaultAgentProvider) ??
        'build';
    await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(text, model: model, agent: agent);
  }

  void _narrate(MessageWithParts message) {
    _stopFillers();
    _lastNarratedId = message.info.id;
    setState(() => _phase = VoicePhase.speaking);
    // The same pipeline as Read Aloud: preprocess, LLM speech rewrite (cached
    // per message), chunked utterances, the selected voice.
    ref.read(ttsStateProvider.notifier).narrate(message);
  }

  /// Speaking finished → listen again. Tapping the mic while speaking
  /// interrupts and listens immediately.
  void _onTtsChange(TtsState? prev, TtsState next) {
    if (!mounted || _closing) return;
    if (_phase == VoicePhase.speaking &&
        prev?.status != TtsStatus.idle &&
        next.status == TtsStatus.idle) {
      _listen();
    }
  }

  void _onChatChange(ChatController controller) {
    if (!mounted || _closing || _phase != VoicePhase.waiting) return;
    final messages = controller.state.messages;
    final reply = replyToNarrate(messages, _lastNarratedId);
    if (reply != null) {
      _narrate(reply);
      return;
    }
    // Surface what the turn is doing while it streams. setState only when the
    // description changes — deltas arrive many times a second.
    final activity = describeActivity(messages.isEmpty ? null : messages.last);
    if (activity?.shown != _activity?.shown) {
      setState(() => _activity = activity);
    } else {
      _activity = activity;
    }
  }

  void _onMicPressed() {
    Haptics.tap();
    switch (_phase) {
      case VoicePhase.speaking:
        // Interrupt the narration and talk.
        ref.read(ttsStateProvider.notifier).stop();
        _listen();
      case VoicePhase.listening:
        _speech.stop(); // Forces the final result now.
      case VoicePhase.error:
        _start();
      case VoicePhase.waiting:
        // Force-stop the agent's turn and hand the floor back.
        ref.read(chatControllerProvider(widget.sessionId).notifier).abort();
        _listen();
      case VoicePhase.starting:
        break;
    }
  }

  void _exit() {
    _closing = true;
    _stopFillers();
    _speech.cancel();
    ref.read(ttsStateProvider.notifier).stop();
    ref.read(voiceModeActiveProvider.notifier).state = false;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ttsStateProvider, _onTtsChange);
    ref.listen(chatControllerProvider(widget.sessionId),
        (prev, next) => _onChatChange(next));
    final tts = ref.watch(ttsStateProvider);
    final theme = Theme.of(context);

    // The narration pipeline's processing step shows as part of "waiting":
    // from the user's seat the agent is still working until speech starts.
    final effectivePhase =
        _phase == VoicePhase.speaking && tts.status == TtsStatus.processing
            ? VoicePhase.waiting
            : _phase;

    // Loop the pulse only while it is on screen.
    if (effectivePhase == VoicePhase.waiting) {
      if (!_thinkingPulse.isAnimating) _thinkingPulse.repeat(reverse: true);
    } else if (_thinkingPulse.isAnimating) {
      _thinkingPulse.stop();
    }

    final (label, hint) = switch (effectivePhase) {
      VoicePhase.starting => ('Starting…', ''),
      VoicePhase.listening => ('Listening', 'Tap the mic when you finish'),
      VoicePhase.waiting => ('Thinking…', 'Tap the mic to stop the agent'),
      VoicePhase.speaking => ('Speaking', 'Tap the mic to interrupt'),
      VoicePhase.error => ('Microphone unavailable', 'Tap the mic to retry'),
    };

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.chevronDown),
              onPressed: _exit,
            ),
          ],
          title: const Text('Voice conversation'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: effectivePhase == VoicePhase.speaking
                  ? TtsEqualizer(
                      isPlaying: true,
                      barCount: 5,
                      height: 56,
                      color: theme.colorScheme.primary,
                    )
                  : effectivePhase == VoicePhase.waiting
                      // Breathing, not static: long turns read as hung
                      // otherwise.
                      ? AnimatedBuilder(
                          animation: _thinkingPulse,
                          builder: (context, child) {
                            final t = Curves.easeInOut
                                .transform(_thinkingPulse.value);
                            return Transform.scale(
                              scale: 0.88 + 0.18 * t,
                              child: Opacity(
                                opacity: 0.45 + 0.55 * t,
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            LucideIcons.brain,
                            size: 56,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          effectivePhase == VoicePhase.listening
                              ? LucideIcons.mic
                              : effectivePhase == VoicePhase.error
                                  ? LucideIcons.micOff
                                  : LucideIcons.brain,
                          size: 56,
                          color: effectivePhase == VoicePhase.listening
                              ? theme.colorScheme.primary
                              : theme.colorScheme.mutedForeground,
                        ),
            ),
            const Gap(20),
            Center(child: Text(label).h4),
            if (hint.isNotEmpty) ...[
              const Gap(4),
              Center(child: Text(hint).xSmall.muted),
            ],
            const Gap(24),
            // What is being heard or said, so the conversation stays legible.
            SizedBox(
              height: 160,
              child: Center(
                child: SingleChildScrollView(
                  reverse: true,
                  child: effectivePhase == VoicePhase.speaking
                      ? _NarrationTicker(
                          controller: ref.read(ttsControllerProvider),
                          fullText: tts.fullText ?? '',
                        )
                      : effectivePhase == VoicePhase.waiting
                          ? Text(
                              _activity?.shown ??
                                  (_fillerText.isEmpty ? ' ' : _fillerText),
                              textAlign: TextAlign.center,
                            ).muted.italic
                          : Text(
                              _partial.isEmpty ? ' ' : _partial,
                              textAlign: TextAlign.center,
                            ).large,
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: GestureDetector(
                onTap: _onMicPressed,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: effectivePhase == VoicePhase.listening
                        ? theme.colorScheme.primary
                        : theme.colorScheme.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    effectivePhase == VoicePhase.speaking
                        ? LucideIcons.mic
                        : effectivePhase == VoicePhase.listening
                            ? LucideIcons.check
                            : LucideIcons.mic,
                    size: 30,
                    color: effectivePhase == VoicePhase.listening
                        ? theme.colorScheme.background
                        : theme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const Gap(12),
            Center(
              child: GhostButton(
                onPressed: _exit,
                child: const Text('End conversation').small.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The words being spoken, ticking past — the voice-mode counterpart of the
/// player bar's live window.
class _NarrationTicker extends StatelessWidget {
  const _NarrationTicker({required this.controller, required this.fullText});

  final TtsController controller;
  final String fullText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TtsProgress?>(
      valueListenable: controller.progress,
      builder: (context, value, _) {
        final length = fullText.length;
        final start = (value?.start ?? 0).clamp(0, length);
        final end = (value?.end ?? 0).clamp(start, length);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: fullText.substring(0, start),
                style: TextStyle(color: theme.colorScheme.mutedForeground),
              ),
              TextSpan(
                text: fullText.substring(start, end),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: fullText.substring(end),
                style: TextStyle(
                  color: theme.colorScheme.foreground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.6),
        );
      },
    );
  }
}
