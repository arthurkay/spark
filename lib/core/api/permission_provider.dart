import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
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
        _resolve(props);
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

  Future<void> _refresh() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final requests = await client.listPermissions();
      final map = <String, PermissionRequest>{};
      for (final r in requests) {
        map[r.id] = r;
      }
      ref.read(pendingPermissionsProvider.notifier).state = map;
      if (map.isEmpty) {
        NotificationService.instance.cancelPermission();
      }
    } on OpencodeApiException {
      // Ignore transient errors; poll will retry.
    }
  }
}

final permissionListenerProvider =
    NotifierProvider<PermissionListenerController, void>(
  PermissionListenerController.new,
);
