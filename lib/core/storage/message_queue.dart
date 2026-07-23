import '../api/opencode_client.dart';
import '../models/provider.dart';
import 'cache_service.dart';

const _queueKey = 'send_queue.json';

class QueuedMessage {
  QueuedMessage({
    required this.sessionId,
    required this.text,
    required this.timestamp,
    this.model,
    this.agent,
    this.attachmentData,
  });

  final String sessionId;
  final String text;
  final int timestamp;
  final ModelSelection? model;
  final String? agent;
  final List<Map<String, dynamic>>? attachmentData;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'text': text,
        'timestamp': timestamp,
        if (model != null) 'model': model!.toJson(),
        if (agent != null) 'agent': agent,
        if (attachmentData != null) 'attachments': attachmentData,
      };

  factory QueuedMessage.fromJson(Map<String, dynamic> json) {
    final modelJson = json['model'] as Map<String, dynamic>?;
    return QueuedMessage(
      sessionId: json['sessionId'] as String,
      text: json['text'] as String,
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      model: modelJson != null
          ? ModelSelection(
              providerID: modelJson['providerID'] as String,
              modelID: modelJson['modelID'] as String,
            )
          : null,
      agent: json['agent'] as String?,
      attachmentData: (json['attachments'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

class MessageQueue {
  final CacheService _cache = CacheService.instance;
  List<QueuedMessage>? _queue;

  Future<List<QueuedMessage>> _load() async {
    if (_queue != null) return _queue!;
    final data = await _cache.read(_queueKey);
    if (data == null) {
      _queue = [];
      return _queue!;
    }
    final list = data['items'] as List<dynamic>? ?? [];
    _queue = list
        .whereType<Map<String, dynamic>>()
        .map(QueuedMessage.fromJson)
        .toList();
    return _queue!;
  }

  Future<void> _save() async {
    final q = _queue ?? [];
    await _cache.write(_queueKey, {
      'items': q.map((m) => m.toJson()).toList(),
    });
  }

  Future<int> get length async => (await _load()).length;

  Future<void> enqueue(QueuedMessage message) async {
    final q = await _load();
    q.add(message);
    await _save();
  }

  Future<QueuedMessage?> dequeue() async {
    final q = await _load();
    if (q.isEmpty) return null;
    final msg = q.removeAt(0);
    await _save();
    return msg;
  }

  Future<List<QueuedMessage>> peekAll() async => _load();

  Future<void> removeByIndex(int index) async {
    final q = await _load();
    if (index >= 0 && index < q.length) {
      q.removeAt(index);
      await _save();
    }
  }

  Future<void> clear() async {
    _queue = [];
    await _cache.delete(_queueKey);
  }

  Future<void> drain(OpencodeClient client) async {
    final q = await _load();
    if (q.isEmpty) return;
    final remaining = <QueuedMessage>[];
    for (final msg in q) {
      try {
        await client.sendPromptAsync(
          sessionId: msg.sessionId,
          text: msg.text,
          model: msg.model,
          agent: msg.agent,
        );
      } catch (_) {
        remaining.add(msg);
      }
    }
    _queue = remaining;
    await _save();
  }
}
