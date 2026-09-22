import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../features/chat/chat_provider.dart';
import '../notifications/notification_service.dart';
import 'providers.dart';
import 'sse_client.dart';

class SessionErrorInfo {
  const SessionErrorInfo({
    required this.sessionId,
    required this.message,
    this.errorType,
    this.statusCode,
    required this.at,
  });

  final String sessionId;
  final String message;
  final String? errorType;
  final int? statusCode;
  final DateTime at;

  String get title => errorType ?? 'Session error';

  String get body {
    final status = statusCode != null ? ' (HTTP $statusCode)' : '';
    return '$message$status';
  }
}

/// Latest `session.error` per session, for any session — including ones whose
/// chat screen is not mounted.
final sessionErrorsProvider = StateProvider<Map<String, SessionErrorInfo>>(
  (ref) => const {},
);

/// Records every `session.error` off the SSE stream and notifies the user
/// when the failing session is not the chat they are looking at (or the app is
/// backgrounded). The open chat renders its own inline banner, so it is
/// skipped here to avoid double-reporting.
class SessionErrorReporterController extends Notifier<void> {
  @override
  void build() {
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event != null) _onEvent(event);
    });
  }

  String? _lastSignature;
  DateTime? _lastAt;
  static const Duration _dedupeWindow = Duration(seconds: 4);

  void _onEvent(OpencodeEvent event) {
    if (event.type != 'session.error') return;
    final props = event.properties;
    developer.log('session.error: ${jsonEncode(props)}', name: 'SSE');

    final sessionId = (props['sessionID'] ?? props['session_id'] ?? '')
        .toString();
    final errorObj = props['error'];
    String message = 'The session hit an error.';
    String? errorType;
    int? statusCode;
    if (errorObj is Map<String, dynamic>) {
      errorType = errorObj['name'] as String?;
      final data = errorObj['data'];
      if (data is Map<String, dynamic>) {
        final m = data['message'];
        if (m is String && m.isNotEmpty) message = m;
        statusCode = data['statusCode'] as int?;
      }
      if (message == 'The session hit an error.' && errorType != null) {
        message = errorType;
      }
    }

    final signature = '$sessionId|$errorType|$message';
    final now = DateTime.now();
    if (signature == _lastSignature &&
        _lastAt != null &&
        now.difference(_lastAt!) < _dedupeWindow) {
      return;
    }
    _lastSignature = signature;
    _lastAt = now;

    final info = SessionErrorInfo(
      sessionId: sessionId,
      message: message,
      errorType: errorType,
      statusCode: statusCode,
      at: now,
    );
    ref.read(sessionErrorsProvider.notifier).state = {
      ...ref.read(sessionErrorsProvider),
      sessionId: info,
    };

    final active = ref.read(activeChatSessionProvider);
    final paused = ref.read(appPausedProvider);
    if (sessionId != active || paused) {
      unawaited(
        NotificationService.instance.showSessionError(
          sessionId,
          errorType ?? 'Session error',
          message,
        ),
      );
    }
  }
}

final sessionErrorReporterProvider =
    NotifierProvider<SessionErrorReporterController, void>(
      SessionErrorReporterController.new,
    );
