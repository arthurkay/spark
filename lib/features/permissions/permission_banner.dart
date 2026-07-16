import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/permission_provider.dart';
import '../../core/api/providers.dart';
import '../../core/models/permission.dart';
import '../../core/notifications/notification_service.dart';

class PermissionBanner extends ConsumerWidget {
  const PermissionBanner({super.key, this.onOpenSession});

  final void Function(String sessionID)? onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingPermissionsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final requests = pending.values.toList();
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

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard({
    required this.permission,
    required this.onOpenSession,
  });

  final PermissionRequest permission;
  final void Function(String sessionID)? onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(opencodeClientProvider);
    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.shieldQuestion, size: 18),
                const Gap(8),
                Expanded(
                  child: Text(
                    permission.title ?? permission.type ?? 'Confirmation',
                  ).semiBold,
                ),
              ],
            ),
            if (permission.metadata.isNotEmpty) ...[
              const Gap(8),
              SelectableText(
                permission.metadata.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('\n'),
              ).mono.small.muted,
            ],
            const Gap(12),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    onPressed: () =>
                        _respond(ref, client, permission, 'reject'),
                    child: const Text('Reject'),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: PrimaryButton(
                    onPressed: () => _respond(ref, client, permission, 'once'),
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
            const Gap(6),
            GhostButton(
              density: ButtonDensity.compact,
              alignment: Alignment.centerRight,
              onPressed: () => onOpenSession?.call(permission.sessionID),
              child: const Text('Open session').small,
            ),
          ],
        ),
      ),
    );
  }

  void _respond(
    WidgetRef ref,
    dynamic client,
    PermissionRequest permission,
    String response,
  ) {
    final map = {...ref.read(pendingPermissionsProvider)};
    if (map.remove(permission.id) != null) {
      ref.read(pendingPermissionsProvider.notifier).state = map.isEmpty
          ? const {}
          : map;
      if (map.isEmpty) NotificationService.instance.cancelPermission();
    }
    if (client != null && client is OpencodeClient) {
      client
          .respondPermission(
            sessionId: permission.sessionID,
            permissionId: permission.id,
            response: response,
            remember: response == 'always',
          )
          .catchError((_) {});
    }
  }
}
