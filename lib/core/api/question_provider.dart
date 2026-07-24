import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/question.dart';
import '../notifications/notification_service.dart';
import 'opencode_client.dart';
import 'providers.dart';
import 'sse_client.dart';

final pendingQuestionsProvider = StateProvider<Map<String, QuestionRequest>>(
  (ref) => const <String, QuestionRequest>{},
);

class QuestionListenerController extends Notifier<void> {
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
    switch (event.type) {
      case 'server.reconnected':
        _refresh();
        break;
      case 'question.asked':
        _onQuestionAsked(event.properties);
        break;
      case 'question.replied':
      case 'question.rejected':
        _onQuestionResolved(event.properties);
        break;
    }
  }

  void _onQuestionAsked(Map<String, dynamic> props) {
    try {
      final request = QuestionRequest.fromJson(props);
      if (request.id.isEmpty) return;
      _add(request);
    } catch (_) {}
  }

  void _onQuestionResolved(Map<String, dynamic> props) {
    final requestId =
        props['requestID'] as String? ?? props['id'] as String? ?? '';
    if (requestId.isEmpty) return;
    final map = {...ref.read(pendingQuestionsProvider)};
    map.removeWhere((key, value) => value.id == requestId);
    ref.read(pendingQuestionsProvider.notifier).state = map;
    if (map.isEmpty) NotificationService.instance.cancelQuestion();
  }

  void _add(QuestionRequest request) {
    final map = {...ref.read(pendingQuestionsProvider)};
    map[request.key] = request;
    if (request.messageID != null && request.messageID!.isNotEmpty) {
      map[request.messageID!] = request;
    }
    if (request.callID != null && request.callID!.isNotEmpty) {
      map[request.callID!] = request;
    }
    map[request.id] = request;
    ref.read(pendingQuestionsProvider.notifier).state = map;
    NotificationService.instance.showQuestion(request);
  }

  Future<void> _refresh() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final requests = await client.listQuestions();
      final map = <String, QuestionRequest>{};
      for (final r in requests) {
        map[r.key] = r;
        if (r.messageID != null && r.messageID!.isNotEmpty) {
          map[r.messageID!] = r;
        }
        if (r.callID != null && r.callID!.isNotEmpty) {
          map[r.callID!] = r;
        }
        map[r.id] = r;
      }
      ref.read(pendingQuestionsProvider.notifier).state = map;
      if (map.isEmpty) NotificationService.instance.cancelQuestion();
    } on OpencodeApiException {
      // Ignore transient errors; poll will retry.
    }
  }
}

final questionListenerProvider =
    NotifierProvider<QuestionListenerController, void>(
  QuestionListenerController.new,
);
