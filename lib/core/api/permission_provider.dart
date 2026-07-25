import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../features/sessions/workspace_provider.dart';
import '../api/opencode_client.dart';
import '../api/providers.dart';
import '../api/sse_client.dart';
import '../models/permission.dart';
import '../notifications/notification_service.dart';

final pendingPermissionsProvider =
    StateProvider<Map<String, PermissionRequest>>(
  (ref) => const <String, PermissionRequest>{},
);

final autoApprovePermissionsProvider = StateProvider<bool>((ref) => false);

class PermissionListenerController extends Notifier<void> {
  @override
  void build() {
    _refresh();
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      _onEvent(event);
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    ref.onDispose(() => _timer?.cancel());
  }

  Timer? _timer;

  void _onEvent(OpencodeEvent event) {
    final props = event.properties;
    switch (event.type) {
      case 'permission.asked':
      case 'permission.v2.asked':
        final permission = PermissionRequest.fromProps(props);
        if (permission.id.isNotEmpty) _add(permission);
      case 'permission.replied':
      case 'permission.v2.replied':
      case 'permission.rejected':
      case 'permission.v2.rejected':
        _resolve(props);
        _refresh();
      case 'server.reconnected':
        _refresh();
    }
  }

  Future<void> _refresh() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final seen = <String, PermissionRequest>{};
      for (final p in await client.listPermissions()) {
        if (p.id.isNotEmpty) seen[p.id] = p;
      }
      final projects = await ref.read(projectsProvider.future);
      for (final project in projects) {
        if (project.isGlobal) continue;
        try {
          for (final p in await client.listPermissions(
            directory: project.worktree,
          )) {
            if (p.id.isNotEmpty) {
              seen.putIfAbsent(
                p.id,
                () => p.copyWith(directory: project.worktree),
              );
            }
          }
        } on OpencodeApiException {
          // Ignore per-project errors; keep other results.
        }
      }
      final autoApprove = ref.read(autoApprovePermissionsProvider);
      if (autoApprove) {
        for (final p in seen.values) {
          _respondAuto(p);
        }
        return;
      }
      final existing = ref.read(pendingPermissionsProvider);
      final hasNew = seen.keys.any((id) => !existing.containsKey(id));
      ref.read(pendingPermissionsProvider.notifier).state = seen;
      if (hasNew) {
        final newest = seen.values.last;
        NotificationService.instance.showPermission(newest);
      } else if (seen.isEmpty) {
        NotificationService.instance.cancelPermission();
      }
    } on OpencodeApiException {
      // Ignore transient errors; poll will retry.
    }
  }

  void _add(PermissionRequest permission) {
    final autoApprove = ref.read(autoApprovePermissionsProvider);
    if (autoApprove) {
      _respondAuto(permission);
      return;
    }
    final map = {...ref.read(pendingPermissionsProvider)};
    map[permission.id] = permission;
    ref.read(pendingPermissionsProvider.notifier).state = map;
    NotificationService.instance.showPermission(permission);
  }

  void _respondAuto(PermissionRequest permission) {
    final client = ref.read(opencodeClientProvider);
    client
        ?.respondPermission(
          sessionId: permission.sessionID,
          permissionId: permission.id,
          reply: 'once',
          directory: permission.directory,
        )
        .catchError((_) {});
    final map = {...ref.read(pendingPermissionsProvider)};
    if (map.remove(permission.id) != null) {
      ref.read(pendingPermissionsProvider.notifier).state = map;
    }
  }

  void _resolve(Map<String, dynamic> props) {
    final requestID =
        (props['requestID'] ?? props['permissionID'] ?? props['id'] ?? '')
            .toString();
    if (requestID.isEmpty) return;
    final map = {...ref.read(pendingPermissionsProvider)};
    map.remove(requestID);
    ref.read(pendingPermissionsProvider.notifier).state = map;
    if (map.isEmpty) NotificationService.instance.cancelPermission();
  }
}

final permissionListenerProvider =
    NotifierProvider<PermissionListenerController, void>(
  PermissionListenerController.new,
);
