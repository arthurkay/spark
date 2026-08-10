import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';

class TtsEqualizer extends StatefulWidget {
  const TtsEqualizer({
    super.key,
    required this.isPlaying,
    this.isPaused = false,
    this.barCount = 3,
    this.height = 16,
    this.color,
  });

  final bool isPlaying;
  final bool isPaused;
  final int barCount;
  final double height;
  final Color? color;

  @override
  State<TtsEqualizer> createState() => _TtsEqualizerState();
}

class _TtsEqualizerState extends State<TtsEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.ambient);
    if (widget.isPlaying && !widget.isPaused) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(TtsEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !widget.isPaused) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final minH = widget.height * 0.25;
    final maxH = widget.height;
    return SizedBox(
      width: widget.barCount * 5.0,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.barCount, (i) {
              final phase = (_controller.value - i * 0.15) % 1.0;
              final t = phase < 0.5 ? phase * 2 : 2 - phase * 2;
              final h = minH + (maxH - minH) * t;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
