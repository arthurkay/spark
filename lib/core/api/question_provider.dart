import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/question.dart';
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
      switch (event.type) {
        case 'question.asked':
        case 'question.v2.asked':
        case 'question.replied':
        case 'question.v2.replied':
        case 'question.rejected':
        case 'question.v2.rejected':
        case 'server.reconnected':
          _refresh();
      }
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
    ref.onDispose(() => _timer?.cancel());
  }

  Timer? _timer;

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
    } on OpencodeApiException {
      // Ignore transient errors; poll will retry.
    }
  }
}

final questionListenerProvider =
    NotifierProvider<QuestionListenerController, void>(
  QuestionListenerController.new,
);
