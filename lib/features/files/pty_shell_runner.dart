import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/pty_ws.dart';

class PtyResult {
  const PtyResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

class PtyShellRunner {
  PtyShellRunner({required this.client});

  final OpencodeClient client;

  static const _markerPrefix = 'SPARK_SH';
  static const _connectTimeout = Duration(seconds: 15);
  static const _readyTimeout = Duration(seconds: 12);
  static const _doneTimeout = Duration(seconds: 30);
  static const _teardownTimeout = Duration(seconds: 5);

  Future<PtyResult> run(String command, {String? directory}) async {
    final session = await client.createPty(
      title: 'shell-runner',
      directory: directory,
      cwd: directory,
    );

    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    var ptyId = session.id;

    final nonce = const Uuid().v4();
    final readyRe = RegExp('${_markerPrefix}_RDY:$nonce');
    final doneRe = RegExp('${_markerPrefix}_DONE:$nonce:(-?\\d+)');

    final ready = Completer<void>();
    final done = Completer<PtyResult>();
    unawaited(ready.future.catchError((_) {}));
    unawaited(done.future.catchError((_) => const PtyResult(-1, '')));

    final tail = _MarkerTail();
    final outputBuffer = StringBuffer();
    void fail(String message) {
      if (!ready.isCompleted) ready.completeError(Exception(message));
      if (!done.isCompleted) done.completeError(Exception(message));
    }

    final uri = buildPtyWebSocketUri(
      client: client,
      ptyId: session.id,
      directory: directory,
    );

    try {
      channel = WebSocketChannel.connect(uri);
      subscription = channel.stream.listen(
        (data) {
          if (done.isCompleted) return;
          final String text;
          if (data is List<int>) {
            if (data.isNotEmpty && data[0] == 0x00) return;
            text = utf8.decode(data, allowMalformed: true);
          } else if (data is String) {
            text = data;
          } else {
            return;
          }
          tail.append(text);
          if (!ready.isCompleted && tail.match(readyRe) != null) {
            ready.complete();
          }
          if (ready.isCompleted) {
            outputBuffer.write(text);
          }
          final match = tail.match(doneRe);
          if (match != null) {
            done.complete(PtyResult(
              int.parse(match.group(1)!),
              outputBuffer.toString(),
            ));
          }
        },
        onError: (Object e) => fail('WebSocket error: $e'),
        onDone: () => fail('Connection closed before command completed'),
      );

      await channel.ready.timeout(
        _connectTimeout,
        onTimeout: () => throw Exception('Timed out connecting to the server'),
      );

      // [command] is interpolated raw: it is a command *line* for the inner
      // `sh -c` to parse, not a single argument. Quoting it made the shell look
      // for a program literally named `touch "notes.txt"` and fail with 127,
      // which is why every file operation silently did nothing. The one round
      // of quoting applied to the whole script below is what protects it from
      // the outer login shell.
      final script = 'p=$_markerPrefix; stty -echo 2>/dev/null; '
          "printf '\\n%s_RDY:$nonce\\n' \"\$p\"; "
          '$command; rc=\$?; '
          "printf '\\n%s_DONE:$nonce:%s\\n' \"\$p\" \"\$rc\"";
      channel.sink.add(utf8.encode('sh -c ${_shellQuote(script)}\n'));

      await ready.future.timeout(
        _readyTimeout,
        onTimeout: () => throw Exception('Timed out waiting for shell ready'),
      );

      final result = await done.future.timeout(
        _doneTimeout,
        onTimeout: () =>
            throw Exception('Timed out waiting for command to complete'),
      );

      return result;
    } finally {
      unawaited(_teardown(channel, subscription, ptyId, directory)
          .timeout(_teardownTimeout, onTimeout: () {})
          .catchError((_) {}));
    }
  }

  Future<void> _teardown(
    WebSocketChannel? channel,
    StreamSubscription<dynamic>? subscription,
    String ptyId,
    String? directory,
  ) async {
    await subscription?.cancel();
    await channel?.sink.close();
    try {
      await client.removePty(ptyId, directory: directory);
    } catch (_) {}
  }

  static String _shellQuote(String s) => shellQuote(s);
}

/// Wraps [s] in single quotes so the shell treats it as one literal word.
///
/// Use this for every path or filename interpolated into a command. Double
/// quotes are not enough: `"$name"` still expands `$`, backticks and `\`, so a
/// file called `notes$HOME.txt` would break — and a crafted name could run a
/// command.
String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

class _MarkerTail {
  _MarkerTail();
  final int capacity = 4096;
  String _tail = '';

  void append(String chunk) {
    if (chunk.isEmpty) return;
    _tail = _tail.isEmpty ? chunk : '$_tail$chunk';
    if (_tail.length > capacity) {
      _tail = _tail.substring(_tail.length - capacity);
    }
  }

  Match? match(RegExp pattern) => pattern.firstMatch(_tail);
}
