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
    final props = event.properties;
    switch (event.type) {
      case 'question.asked':
      case 'question.v2.asked':
        final request = QuestionRequest.fromJson(props);
        if (request.id.isNotEmpty) _add(request);
      case 'question.replied':
      case 'question.v2.replied':
        _resolve(props);
      case 'question.rejected':
      case 'question.v2.rejected':
        _resolve(props);
      case 'server.reconnected':
        _refresh();
    }
  }

  void _add(QuestionRequest request) {
    final map = {...ref.read(pendingQuestionsProvider)};
    map[request.key] = request;
    ref.read(pendingQuestionsProvider.notifier).state = map;
    NotificationService.instance.showQuestion(request);
  }

  void _resolve(Map<String, dynamic> props) {
    final requestID = (props['requestID'] ?? props['id'] ?? '').toString();
    if (requestID.isEmpty) return;
    final map = {...ref.read(pendingQuestionsProvider)};
    map.remove(requestID);
    ref.read(pendingQuestionsProvider.notifier).state = map;
    if (map.isEmpty) NotificationService.instance.cancelQuestion();
  }

  Future<void> _refresh() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final requests = await client.listQuestions();
      final map = <String, QuestionRequest>{};
      for (final r in requests) {
        map[r.key] = r;
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
