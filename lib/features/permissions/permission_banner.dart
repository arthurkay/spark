import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/permission_provider.dart';
import '../../core/api/providers.dart';
import '../../app/motion.dart';
import '../../shared/haptics.dart';
import '../../core/models/permission.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/widgets/code_highlight_view.dart';
import 'permission_sheet.dart';
import 'permission_utils.dart';

class PermissionBanner extends ConsumerWidget {
  const PermissionBanner({super.key, this.onOpenSession});

  final void Function(String sessionID)? onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingPermissionsProvider);
    final requests = pending.values.toList();
    // AnimatedSize with an always-present child: appearing/disappearing
    // instantly used to shove the whole chat list up and down.
    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.inOut,
      alignment: Alignment.topCenter,
      child: requests.isEmpty
          ? const SizedBox(width: double.infinity)
          : _bannerBody(context, requests),
    );
  }

  Widget _bannerBody(BuildContext context, List<PermissionRequest> requests) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.border,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final permission in requests)
            _PermissionCard(
              permission: permission,
              onOpenSession: onOpenSession,
            ),
        ],
      ),
    );
  }
}

class _PermissionCard extends ConsumerStatefulWidget {
  const _PermissionCard({
    required this.permission,
    required this.onOpenSession,
  });

  final PermissionRequest permission;
  final void Function(String sessionID)? onOpenSession;

  @override
  ConsumerState<_PermissionCard> createState() => _PermissionCardState();
}

class _PermissionCardState extends ConsumerState<_PermissionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    final collapsed = ref.read(collapseFilePermissionsProvider);
    final isFile = filePermissionTypes.contains(widget.permission.type);
    _expanded = isFile ? !collapsed : true;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(opencodeClientProvider);
    final permission = widget.permission;
    final hasMetadata = permission.metadata.isNotEmpty;

    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: hasMetadata
                  ? () => setState(() => _expanded = !_expanded)
                  : () => _showSheet(context, ref, permission),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(permissionIcon(permission.type), size: 18),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          permission.title ?? permission.type ?? 'Confirmation',
                        ).semiBold,
                      ),
                      if (hasMetadata)
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: Motion.base,
                          curve: Motion.standard,
                          child: const Icon(LucideIcons.chevronRight, size: 14)
                              .iconMutedForeground,
                        )
                      else
                        const Icon(LucideIcons.chevronRight, size: 14)
                            .iconMutedForeground,
                    ],
                  ),
                  if (hasMetadata && _expanded) ...[
                    const Gap(8),
                    ...permission.metadata.entries.map((e) {
                      final isCommand = isCommandEntry(e.key, e.value);
                      if (isCommand) {
                        final cmd = e.value.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: CodeHighlightView(
                            code: cmd,
                            language: 'bash',
                            constraints: const BoxConstraints(maxHeight: 160),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(
                          '${e.key}: ${e.value}',
                        ).mono.small.muted,
                      );
                    }),
                  ],
                ],
              ),
            ),
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    onPressed: () =>
                        _respondWithFeedback(ref, client, permission, 'reject'),
                    child: const Text('Reject'),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: PrimaryButton(
                    onPressed: () =>
                        _respondWithFeedback(ref, client, permission, 'once'),
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
            const Gap(6),
            GhostButton(
              density: ButtonDensity.compact,
              alignment: Alignment.centerRight,
              onPressed: () => widget.onOpenSession?.call(permission.sessionID),
              child: const Text('Open session').small,
            ),
          ],
        ),
      ),
    );
  }

  void _showSheet(
    BuildContext context,
    WidgetRef ref,
    PermissionRequest permission,
  ) {
    final client = ref.read(opencodeClientProvider);
    showPermissionSheet(
      context: context,
      permission: permission,
      onRespond: (response) {
        final map = {...ref.read(pendingPermissionsProvider)};
        if (map.remove(permission.id) != null) {
          ref.read(pendingPermissionsProvider.notifier).state =
              map.isEmpty ? const {} : map;
          if (map.isEmpty) NotificationService.instance.cancelPermission();
        }
        client
            ?.respondPermission(
              sessionId: permission.sessionID,
              permissionId: permission.id,
              reply: response,
              directory: permission.directory,
            )
            .catchError((_) {});
      },
    );
  }

  void _respondWithFeedback(
    WidgetRef ref,
    OpencodeClient? client,
    PermissionRequest permission,
    String response,
  ) {
    // Approving or denying is a commitment — it should be felt.
    Haptics.commit();
    _respond(ref, client, permission, response);
  }

  void _respond(
    WidgetRef ref,
    dynamic client,
    PermissionRequest permission,
    String response,
  ) {
    final map = {...ref.read(pendingPermissionsProvider)};
    if (map.remove(permission.id) != null) {
      ref.read(pendingPermissionsProvider.notifier).state =
          map.isEmpty ? const {} : map;
      if (map.isEmpty) NotificationService.instance.cancelPermission();
    }
    if (client != null && client is OpencodeClient) {
      client
          .respondPermission(
            sessionId: permission.sessionID,
            permissionId: permission.id,
            reply: response,
            directory: permission.directory,
          )
          .catchError((_) {});
    }
  }
}
