import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'endpoints.dart';

class OpencodeEvent {
  const OpencodeEvent({required this.type, required this.properties});

  final String type;
  final Map<String, dynamic> properties;

  factory OpencodeEvent.fromJson(Map<String, dynamic> json) {
    return OpencodeEvent(
      type: (json['type'] ?? '').toString(),
      properties: json['properties'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class SseClient {
  SseClient(this._dio, {this.reconnectDelay = const Duration(seconds: 2)});

  final Dio _dio;
  final Duration reconnectDelay;

  StreamController<OpencodeEvent>? _controller;
  StreamSubscription<List<int>>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  Stream<OpencodeEvent> connect() {
    _controller = StreamController<OpencodeEvent>.broadcast(
      onCancel: dispose,
      onListen: _listen,
    );
    return _controller!.stream;
  }

  void _listen() {
    if (_disposed) return;
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      final response = await _dio.get<ResponseBody>(
        Endpoints.event,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      final buffer = StringBuffer();
      _subscription = response.data!.stream.listen(
        (chunk) {
          buffer.write(utf8.decode(chunk, allowMalformed: true));
          _drain(buffer);
        },
        onError: (Object e) {
          _controller?.addError(e);
          _scheduleReconnect();
        },
        onDone: () {
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      _reconnectAttempts = 0;
      _controller?.add(
        const OpencodeEvent(type: 'server.reconnected', properties: {}),
      );
    } catch (e) {
      _controller?.addError(e);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    final attempt = _reconnectAttempts++;
    final delay = reconnectDelay * (1 << attempt.clamp(0, 4));
    _reconnectTimer = Timer(delay, _listen);
  }

  void _drain(StringBuffer buffer) {
    var content = buffer.toString();
    var index = content.indexOf('\n\n');
    while (index != -1) {
      final rawEvent = content.substring(0, index);
      content = content.substring(index + 2);
      _emit(rawEvent);
      index = content.indexOf('\n\n');
    }
    buffer
      ..clear()
      ..write(content);
  }

  void _emit(String rawEvent) {
    final dataLines = <String>[];
    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return;
    final payload = dataLines.join('\n');
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      _controller?.add(OpencodeEvent.fromJson(json));
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _controller?.close();
  }
}
