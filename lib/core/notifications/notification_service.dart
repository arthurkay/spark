import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';

import '../../core/models/permission.dart';

const String _channelId = 'opencode_permission';
const String _channelName = 'Permission requests';
const int _permissionNotificationId = 1;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  void Function(String permissionID, String sessionID)? _onTap;

  Future<void> init({
    required void Function(String permissionID, String sessionID) onTap,
  }) async {
    _onTap = onTap;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
    } on Object catch (_) {
      _available = false;
    }
  }

  Future<void> requestPermission() async {
    if (!_available) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.resumed) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } on Object catch (_) {
      _available = false;
    }
  }

  bool _available = true;

  bool get available => _available;

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final permissionID = (data['permissionID'] ?? '').toString();
      final sessionID = (data['sessionID'] ?? '').toString();
      if (permissionID.isNotEmpty && sessionID.isNotEmpty) {
        _onTap?.call(permissionID, sessionID);
      }
    } catch (_) {}
  }

  Future<void> showPermission(PermissionRequest permission) async {
    if (!_available) return;
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Confirmation requests from the SparkCode server',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Confirmation required',
      icon: '@mipmap/ic_notification',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    final title =
        permission.title ?? permission.type ?? 'Confirmation required';
    final body = permission.metadata.isNotEmpty
        ? permission.metadata.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n')
        : 'Tap to review and respond.';
    await _plugin.show(
      _permissionNotificationId,
      title,
      body,
      details,
      payload: jsonEncode({
        'permissionID': permission.id,
        'sessionID': permission.sessionID,
      }),
    );
  }

  Future<void> cancelPermission() async {
    if (!_available) return;
    await _plugin.cancel(_permissionNotificationId);
  }
}
