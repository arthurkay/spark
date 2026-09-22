import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'local_server_provider.dart';

class LocalServerSettingsSection extends ConsumerWidget {
  const LocalServerSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localServerProvider);
    final controller = ref.read(localServerProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Local server').small.semiBold.muted,
        const Gap(10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.squareTerminal,
                    size: 18,
                    color: _statusColor(theme, state),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SparkCode (this machine)').medium,
                        const Gap(2),
                        Text(
                          state.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: state.status == LocalServerStatus.failed
                                ? theme.colorScheme.destructive
                                : theme.colorScheme.mutedForeground,
                          ),
                        ),
                        if (state.version != null)
                          Text('opencode ${state.version}').xSmall.muted,
                      ],
                    ),
                  ),
                  ..._actions(context, ref, controller, state),
                ],
              ),
              if (state.status == LocalServerStatus.installing ||
                  state.status == LocalServerStatus.starting ||
                  state.status == LocalServerStatus.locating) ...[
                const Gap(12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        const Gap(8),
        OutlineButton(
          density: ButtonDensity.compact,
          onPressed: state.log.isEmpty ? null : () => _openLogs(context, state),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.scrollText, size: 14),
              Gap(4),
              Text('Logs'),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusColor(ThemeData theme, LocalServerState state) {
    switch (state.status) {
      case LocalServerStatus.healthy:
        return theme.colorScheme.primary;
      case LocalServerStatus.failed:
      case LocalServerStatus.missing:
        return theme.colorScheme.destructive;
      case LocalServerStatus.installing:
      case LocalServerStatus.starting:
      case LocalServerStatus.locating:
        return theme.colorScheme.chart2;
      default:
        return theme.colorScheme.mutedForeground;
    }
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    LocalServerController controller,
    LocalServerState state,
  ) {
    final busy =
        state.status == LocalServerStatus.installing ||
        state.status == LocalServerStatus.starting ||
        state.status == LocalServerStatus.locating ||
        state.status == LocalServerStatus.stopping;
    switch (state.status) {
      case LocalServerStatus.missing:
      case LocalServerStatus.idle when state.binaryPath == null:
        return [
          OutlineButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: busy ? null : () => controller.install(),
            child: const Text('Install').small,
          ),
        ];
      case LocalServerStatus.idle:
        return [
          OutlineButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: () => controller.upgrade(),
            child: const Text('Upgrade').small,
          ),
          const Gap(4),
          PrimaryButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: () => controller.start(),
            child: const Text('Start').small,
          ),
        ];
      case LocalServerStatus.healthy:
        return [
          PrimaryButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: () => controller.stop(),
            child: const Text('Stop').small,
          ),
        ];
      case LocalServerStatus.failed:
        return [
          OutlineButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: () => controller.start(),
            child: const Text('Retry').small,
          ),
          const Gap(4),
          if (state.binaryPath == null)
            PrimaryButton(
              size: ButtonSize.small,
              density: ButtonDensity.compact,
              onPressed: () => controller.install(),
              child: const Text('Install').small,
            )
          else
            PrimaryButton(
              size: ButtonSize.small,
              density: ButtonDensity.compact,
              onPressed: () => controller.stop(),
              child: const Text('Stop').small,
            ),
        ];
      case LocalServerStatus.starting:
      case LocalServerStatus.installing:
      case LocalServerStatus.locating:
      case LocalServerStatus.stopping:
        return [
          OutlineButton(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            onPressed: () => controller.stop(),
            child: const Text('Cancel').small,
          ),
        ];
    }
  }

  void _openLogs(BuildContext context, LocalServerState state) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.scrollText, size: 18),
                  const Gap(8),
                  const Text('Local server logs').h4,
                  const Spacer(),
                  IconButton.ghost(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => closeSheet(sheetContext),
                  ),
                ],
              ),
              const Gap(12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.muted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: state.log.isEmpty
                      ? const Text('No output yet.').muted.small
                      : SingleChildScrollView(
                          child: SelectableText(
                            state.log.join('\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
