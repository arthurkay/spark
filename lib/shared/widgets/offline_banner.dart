import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';
import '../../core/api/connectivity_provider.dart';

/// A one-line strip under the status bar while no opencode server is
/// reachable.
///
/// Deliberately small and non-blocking: offline, the app keeps working from
/// its caches — browse sessions, replay narrations, read files already loaded.
/// Only talking to the AI needs the server, and the message queue already
/// holds sends until the connection returns.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectivityProvider);
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedSlide(
        offset: connected ? const Offset(0, -1) : Offset.zero,
        duration: Motion.base,
        curve: Motion.standard,
        child: Container(
          width: double.infinity,
          color: theme.colorScheme.muted,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.cloudOff,
                    size: 11,
                    color: theme.colorScheme.mutedForeground,
                  ),
                  const Gap(6),
                  Text('Not connected — showing saved data').xSmall.muted,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
