import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';
import 'tts_equalizer.dart';
import 'tts_provider.dart';

class TtsLoadingOverlay extends ConsumerStatefulWidget {
  const TtsLoadingOverlay({super.key});

  @override
  ConsumerState<TtsLoadingOverlay> createState() => _TtsLoadingOverlayState();
}

class _TtsLoadingOverlayState extends ConsumerState<TtsLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Motion.base,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Motion.standard,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tts = ref.watch(ttsStateProvider);
    final isProcessing = tts.status == TtsStatus.processing;

    if (isProcessing) {
      if (!_fadeController.isAnimating && _fadeController.value == 0) {
        _fadeController.forward();
      }
    } else {
      if (_fadeController.isAnimating || _fadeController.value > 0) {
        _fadeController.reverse();
      }
    }

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, _) {
        if (_fadeAnimation.value == 0) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: !isProcessing,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: GestureDetector(
              onTap: () {
                ref.read(ttsStateProvider.notifier).stop();
              },
              child: Container(
                color:
                    Colors.black.withValues(alpha: 0.6 * _fadeAnimation.value),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TtsEqualizer(
                        isPlaying: true,
                        barCount: 5,
                        height: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const Gap(20),
                      Text(
                        'Preparing to read aloud...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Gap(8),
                      Text(
                        'Tap anywhere to cancel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
