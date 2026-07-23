import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      _onEvent(event);
    });
  }

  void _onEvent(OpencodeEvent event) {
    final props = event.properties;
    switch (event.type) {
      case 'permission.asked':
      case 'permission.v2.asked':
        final permission = PermissionRequest.fromProps(props);
        if (permission.id.isNotEmpty) _add(permission);
        break;
      case 'permission.replied':
      case 'permission.v2.replied':
        _resolve(props);
        break;
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
        )
        .catchError((_) {});
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
