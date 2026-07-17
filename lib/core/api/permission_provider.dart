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
        final permission = _fromProps(props);
        if (permission != null) _add(permission);
      case 'permission.updated':
        final permission = _fromProps(props);
        if (permission != null) _add(permission);
      case 'permission.replied':
        _resolve(props);
    }
  }

  PermissionRequest? _fromProps(Map<String, dynamic> props) {
    final data = props['data'] ?? props['permission'] ?? props['info'] ?? props;
    if (data is Map<String, dynamic>) {
      final request = PermissionRequest.fromJson(data);
      if (request.id.isNotEmpty) return request;
    }
    return null;
  }

  void _add(PermissionRequest permission) {
    final map = {...ref.read(pendingPermissionsProvider)};
    map[permission.id] = permission;
    ref.read(pendingPermissionsProvider.notifier).state = map;
    NotificationService.instance.showPermission(permission);
  }

  void _resolve(Map<String, dynamic> props) {
    final data = props['data'] is Map<String, dynamic>
        ? props['data'] as Map<String, dynamic>
        : props;
    final requestID =
        (data['requestID'] ?? data['id'] ?? data['permissionID'] ?? '')
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
