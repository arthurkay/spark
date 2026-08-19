import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

bool _isWordBreak(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x0A || codeUnit == 0x09;

/// The next reveal cursor for progressively displayed streaming text.
///
/// The server sends the whole accumulated message on each update and the model
/// emits in bursts, so a sentence often arrives in one delta and used to appear
/// as a block. This advances a fraction of the outstanding text per tick — a
/// burst catches up over roughly [catchUpTicks] ticks instead of landing at
/// once — then snaps forward to the end of the word the cursor lands inside, so
/// a partial word is never painted. A token longer than [maxWordLookahead]
/// (a URL, a code span) falls back to a hard cut so one huge token cannot stall
/// the reveal.
int nextRevealIndex(
  String text,
  int revealed, {
  int catchUpTicks = 8,
  int maxWordLookahead = 24,
}) {
  final length = text.length;
  if (revealed >= length) return length;
  final int pending = length - revealed;
  final int step = math.max<int>(1, (pending / catchUpTicks).ceil());
  final int target = revealed + step;
  if (target >= length) return length;
  final int limit = math.min<int>(length, target + maxWordLookahead);
  for (var i = target; i < limit; i++) {
    // Include the break itself, so the next word starts clean.
    if (_isWordBreak(text.codeUnitAt(i))) return i + 1;
  }
  // No break within the lookahead: if the scan reached the end of the text the
  // final word ends there; otherwise this is one long token, so hard-cut.
  return limit == length ? length : target;
}

/// Reveals streaming text word by word instead of in server-sized chunks.
///
/// Only live streams animate: a message that is already complete when first
/// built (scrolled in from history) renders whole immediately.
class StreamingText extends StatefulWidget {
  const StreamingText({
    super.key,
    required this.text,
    required this.streaming,
    required this.builder,
  });

  final String text;
  final bool streaming;
  final Widget Function(BuildContext, String) builder;

  @override
  State<StreamingText> createState() => StreamingTextState();
}

class StreamingTextState extends State<StreamingText> {
  /// Roughly the delta-throttle cadence, so the reveal costs about what the
  /// old chunk rendering did — the win is granularity, not extra frames.
  static const _tick = Duration(milliseconds: 50);

  /// A stream we joined at the start has only a few characters on its first
  /// build. Anything longer was already written before this widget existed —
  /// opening a session mid-turn, or scrolling past a turn the server abandoned
  /// without stamping `time.completed` — and replaying it from empty would be
  /// theatre, so it renders whole and only new words animate.
  static const _coldStartLimit = 80;

  int _revealed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _revealed = widget.streaming && widget.text.length <= _coldStartLimit
        ? 0
        : widget.text.length;
    if (widget.streaming) _start();
  }

  @override
  void didUpdateWidget(StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A replaced (not appended) message can leave the cursor past the end.
    if (_revealed > widget.text.length) _revealed = widget.text.length;
    if (!widget.streaming) {
      // The turn finished: show everything rather than trickling the tail out
      // after the model has already stopped.
      _timer?.cancel();
      _timer = null;
      if (_revealed != widget.text.length) {
        _revealed = widget.text.length;
      }
    } else if (_timer == null) {
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      final next = nextRevealIndex(widget.text, _revealed);
      // Nothing new to show: skip the rebuild entirely so an idle stream costs
      // a timer callback and nothing else.
      if (next == _revealed) return;
      setState(() => _revealed = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _revealed >= widget.text.length
        ? widget.text
        : widget.text.substring(0, _revealed);
    return widget.builder(context, shown);
  }
}
