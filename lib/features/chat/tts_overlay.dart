import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/motion.dart';
import '../../shared/widgets/markdown_view.dart';
import 'tts_equalizer.dart';
import 'tts_loading_overlay.dart';
import 'tts_provider.dart';

/// Expansion stops for the narration player, smallest to largest.
enum TtsPlayerSize { bar, half, tall }

/// The next stop when stepping [up] or down from [size]. Clamps at the ends.
TtsPlayerSize nextPlayerSize(TtsPlayerSize size, {required bool up}) {
  final index = size.index + (up ? 1 : -1);
  return TtsPlayerSize.values[index.clamp(0, TtsPlayerSize.values.length - 1)];
}

/// The narration player, mounted in the app shell rather than on a screen.
///
/// It used to live inside the chat screen's column, so navigating anywhere left
/// narration playing with no way to pause or stop it. Mounted above the router
/// it survives every navigation, and its expanded/collapsed state survives with
/// it.
class TtsOverlay extends ConsumerWidget {
  const TtsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ttsStateProvider.select((s) => s.status));
    final active = status == TtsStatus.playing || status == TtsStatus.paused;
    if (!active && status != TtsStatus.processing) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        // Owns its own visibility; shows only while the rewrite is in flight.
        const TtsLoadingOverlay(),
        if (active)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _TtsPlayer(),
              ),
            ),
          ),
      ],
    );
  }
}

class _TtsPlayer extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TtsPlayer> createState() => _TtsPlayerState();
}

class _TtsPlayerState extends ConsumerState<_TtsPlayer> {
  TtsPlayerSize _size = TtsPlayerSize.bar;

  /// 0 = Transcript (what is being spoken), 1 = Original (the real message,
  /// rendered). Survives navigation with the rest of the player state.
  int _tab = 0;

  /// Accumulated drag on the header, so a slow deliberate drag steps a stop
  /// even without fling velocity.
  double _dragDelta = 0;

  bool get _expanded => _size != TtsPlayerSize.bar;

  /// An expanded player means someone is reading along — keep the screen on.
  /// Collapsed playback is background listening; the normal timeout applies.
  void _setSize(TtsPlayerSize size) {
    if (size == _size) return;
    setState(() => _size = size);
    unawaited(WakelockPlus.toggle(enable: size != TtsPlayerSize.bar));
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Fling wins; a slow drag needs distance to commit. Negative dy is upward.
    final bool? up = velocity < -250
        ? true
        : velocity > 250
            ? false
            : _dragDelta < -40
                ? true
                : _dragDelta > 40
                    ? false
                    : null;
    _dragDelta = 0;
    if (up != null) _setSize(nextPlayerSize(_size, up: up));
  }

  @override
  void dispose() {
    // The player unmounts when narration stops; never leave the screen pinned.
    if (_expanded) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tts = ref.watch(ttsStateProvider);
    final theme = Theme.of(context);
    final isPaused = tts.status == TtsStatus.paused;
    final notifier = ref.read(ttsStateProvider.notifier);
    final progress = ref.read(ttsControllerProvider).progress;
    final fullText = tts.fullText ?? tts.text ?? '';
    final hasOriginal = tts.sourceText?.trim().isNotEmpty ?? false;
    // The tall stop reads like a sheet but keeps the app visible above it; the
    // half stop is glanceable. Height animates between them via AnimatedSize.
    final contentHeight = _size == TtsPlayerSize.tall
        ? MediaQuery.sizeOf(context).height * 0.58
        : 220.0;

    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.inOut,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              // Tap toggles closed/open; dragging the header steps through the
              // stops (bar, half, tall) like a sheet with detents.
              onTap: () =>
                  _setSize(_expanded ? TtsPlayerSize.bar : TtsPlayerSize.half),
              onVerticalDragStart: (_) => _dragDelta = 0,
              onVerticalDragUpdate: (d) => _dragDelta += d.delta.dy,
              onVerticalDragEnd: _onDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    TtsEqualizer(
                      isPlaying: !isPaused,
                      isPaused: isPaused,
                      height: 18,
                    ),
                    const Gap(10),
                    Expanded(
                      child: _expanded
                          ? const Text('Narrating').small.semiBold
                          // Collapsed: the words currently being spoken, so the
                          // bar itself is the live transcript.
                          : ValueListenableBuilder<TtsProgress?>(
                              valueListenable: progress,
                              builder: (context, value, _) {
                                return Text(
                                  _spokenWindow(fullText, value),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ).small;
                              },
                            ),
                    ),
                    const Gap(8),
                    IconButton.ghost(
                      size: ButtonSize.small,
                      density: ButtonDensity.compact,
                      onPressed: () =>
                          isPaused ? notifier.resume() : notifier.pause(),
                      icon: Icon(
                        isPaused ? LucideIcons.play : LucideIcons.pause,
                        size: 16,
                      ),
                    ),
                    IconButton.ghost(
                      size: ButtonSize.small,
                      density: ButtonDensity.compact,
                      onPressed: notifier.stop,
                      icon: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: Motion.base,
                      curve: Motion.standard,
                      child: const Icon(LucideIcons.chevronUp, size: 14)
                          .iconMutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && fullText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SeekBar(progress: progress, length: fullText.length),
                    const Gap(10),
                    if (hasOriginal) ...[
                      Row(
                        children: [
                          _PlayerTab(
                            label: 'Transcript',
                            selected: _tab == 0,
                            onTap: () => setState(() => _tab = 0),
                          ),
                          const Gap(6),
                          _PlayerTab(
                            label: 'Original',
                            selected: _tab == 1,
                            onTap: () => setState(() => _tab = 1),
                          ),
                        ],
                      ),
                      const Gap(10),
                    ],
                    if (_tab == 1 && hasOriginal)
                      _OriginalView(
                        sourceText: tts.sourceText!,
                        narrationLength: fullText.length,
                        progress: progress,
                        maxHeight: contentHeight,
                      )
                    else
                      _Transcript(
                        text: fullText,
                        progress: progress,
                        maxHeight: contentHeight,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A window of the narration around the word being spoken, for the collapsed
/// bar. Starts a little before so the line doesn't read as starting mid-word.
String _spokenWindow(String text, TtsProgress? progress) {
  if (text.isEmpty) return '';
  if (progress == null) return text;
  final start = math.max(0, math.min(progress.start, text.length) - 12);
  return text.substring(start).trimLeft();
}

/// A scroll view that follows narration progress proportionally.
///
/// Measuring the exact line of a character offset would mean laying the
/// paragraph out twice per word; position-as-a-fraction is approximate but
/// costs nothing and stays smooth. The same mechanism serves the Original tab,
/// where no exact mapping *can* exist — the narration paraphrases — but the
/// rewrite preserves document order, so the fraction tracks the reading
/// position well.
///
/// A drag by the user suspends following for a few seconds so reading back
/// doesn't fight the auto-scroll, then it re-attaches.
class _FollowedScrollView extends StatefulWidget {
  const _FollowedScrollView({
    required this.progress,
    required this.narrationLength,
    required this.maxHeight,
    required this.child,
  });

  final ValueNotifier<TtsProgress?> progress;
  final int narrationLength;
  final double maxHeight;
  final Widget child;

  @override
  State<_FollowedScrollView> createState() => _FollowedScrollViewState();
}

class _FollowedScrollViewState extends State<_FollowedScrollView> {
  final _scrollController = ScrollController();
  DateTime? _holdUntil;

  static const _holdAfterDrag = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    _scrollController.dispose();
    super.dispose();
  }

  void _onProgress() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow(widget.progress.value);
    });
  }

  bool get _held => _holdUntil != null && DateTime.now().isBefore(_holdUntil!);

  void _follow(TtsProgress? progress) {
    if (progress == null || widget.narrationLength == 0 || _held) return;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final fraction = (progress.start / widget.narrationLength).clamp(0.0, 1.0);
    final target = fraction * max;
    // Ignore sub-pixel corrections: re-targeting an animation every word for a
    // few pixels reads as jitter.
    if ((target - _scrollController.offset).abs() < 8) return;
    _scrollController.animateTo(
      target,
      duration: Motion.base,
      curve: Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (notification) {
          // Only a real drag holds the follow; the follow's own animateTo also
          // emits ScrollStart, but with no dragDetails.
          if (notification.dragDetails != null) {
            _holdUntil = DateTime.now().add(_holdAfterDrag);
          }
          return false;
        },
        child: SingleChildScrollView(
          controller: _scrollController,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The full narration with the spoken word highlighted.
class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.text,
    required this.progress,
    required this.maxHeight,
  });

  final String text;
  final ValueNotifier<TtsProgress?> progress;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _FollowedScrollView(
      progress: progress,
      narrationLength: text.length,
      maxHeight: maxHeight,
      child: ValueListenableBuilder<TtsProgress?>(
        valueListenable: progress,
        builder: (context, value, _) {
          final length = text.length;
          final start = (value?.start ?? 0).clamp(0, length);
          final end = (value?.end ?? 0).clamp(start, length);
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: text.substring(0, start),
                  style: TextStyle(color: theme.colorScheme.mutedForeground),
                ),
                TextSpan(
                  text: text.substring(start, end),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: text.substring(end),
                  style: TextStyle(
                    color: theme.colorScheme.foreground.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 14, height: 1.5),
          );
        },
      ),
    );
  }
}

/// The original message, rendered as it appears in the chat.
///
/// The narration deliberately paraphrases; code blocks, tables and images
/// exist only here. Scrolls along with the narration via the same
/// proportional follow as the transcript.
class _OriginalView extends StatelessWidget {
  const _OriginalView({
    required this.sourceText,
    required this.narrationLength,
    required this.progress,
    required this.maxHeight,
  });

  final String sourceText;
  final int narrationLength;
  final ValueNotifier<TtsProgress?> progress;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return _FollowedScrollView(
      progress: progress,
      narrationLength: narrationLength,
      maxHeight: maxHeight,
      child: MarkdownView(
        data: sourceText,
        textStyle: const TextStyle(fontSize: 14, height: 1.5),
      ),
    );
  }
}

/// Scrubs through the narration.
///
/// The thumb rides [progress] while idle; during a drag the local value wins so
/// the engine's per-word events don't fight the finger. Seeking re-speaks from
/// the chosen offset — the same mechanism resume and chunk-chaining use.
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.progress, required this.length});

  final ValueNotifier<TtsProgress?> progress;
  final int length;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TtsProgress?>(
      valueListenable: widget.progress,
      builder: (context, value, _) {
        final fraction = _dragValue ??
            (widget.length == 0
                ? 0.0
                : ((value?.start ?? 0) / widget.length).clamp(0.0, 1.0));
        return Slider(
          value: SliderValue.single(fraction),
          onChanged: (v) => setState(() => _dragValue = v.value),
          onChangeEnd: (v) {
            ref.read(ttsStateProvider.notifier).seek(v.value);
            setState(() => _dragValue = null);
          },
        );
      },
    );
  }
}

class _PlayerTab extends StatelessWidget {
  const _PlayerTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color:
              selected ? theme.colorScheme.foreground : theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? theme.colorScheme.background
                : theme.colorScheme.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
