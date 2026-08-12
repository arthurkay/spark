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

class VoiceModeScreen extends ConsumerStatefulWidget {
  const VoiceModeScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<VoiceModeScreen> createState() => _VoiceModeScreenState();
}

class _VoiceModeScreenState extends ConsumerState<VoiceModeScreen> {
  final SpeechToText _speech = SpeechToText();
  VoicePhase _phase = VoicePhase.starting;
  String _partial = '';
  String? _lastNarratedId;
  bool _closing = false;

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
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    _speech.cancel();
    WakelockPlus.disable();
    super.dispose();
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
    final reply = replyToNarrate(controller.state.messages, _lastNarratedId);
    if (reply != null) _narrate(reply);
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
      case VoicePhase.starting:
      case VoicePhase.waiting:
        break;
    }
  }

  void _exit() {
    _closing = true;
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

    final (label, hint) = switch (effectivePhase) {
      VoicePhase.starting => ('Starting…', ''),
      VoicePhase.listening => ('Listening', 'Tap the mic when you finish'),
      VoicePhase.waiting => ('Thinking…', ''),
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
