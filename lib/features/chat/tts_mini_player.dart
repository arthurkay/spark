import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';
import 'tts_equalizer.dart';
import 'tts_provider.dart';

class TtsMiniPlayer extends ConsumerWidget {
  const TtsMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(ttsStateProvider);
    final isActive =
        tts.status == TtsStatus.playing || tts.status == TtsStatus.paused;
    if (!isActive) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isPaused = tts.status == TtsStatus.paused;

    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.standard,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            TtsEqualizer(
              isPlaying: tts.status == TtsStatus.playing,
              isPaused: isPaused,
              height: 20,
            ),
            const Gap(10),
            Expanded(
              child: Text(
                tts.text ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.foreground,
                ),
              ),
            ),
            const Gap(8),
            IconButton.ghost(
              onPressed: () {
                final notifier = ref.read(ttsStateProvider.notifier);
                if (isPaused) {
                  notifier.resume();
                } else {
                  notifier.pause();
                }
              },
              icon: Icon(
                isPaused ? LucideIcons.play : LucideIcons.pause,
                size: 18,
              ),
            ),
            IconButton.ghost(
              onPressed: () {
                ref.read(ttsStateProvider.notifier).stop();
              },
              icon: Icon(
                LucideIcons.x,
                size: 18,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
