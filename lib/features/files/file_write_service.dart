import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/pty_ws.dart';

/// Thrown when a [PtyFileWriter.write] fails for any reason other than a
/// plain [OpencodeApiException] from the REST calls it makes (creating or
/// removing the headless PTY).
class FileWriteException implements Exception {
  FileWriteException(this.message, {this.exitCode});

  final String message;
  final int? exitCode;

  @override
  String toString() => 'FileWriteException: $message';
}

/// Persists file content to the server by proxying a shell write through a
/// headless PTY.
///
/// The `opencode serve` API has no endpoint to write file content directly
/// (only `GET /file` and `GET /file/content`). This writer spawns a PTY the
/// user never sees, sends a base64-armored `base64 -d > path` heredoc, waits
/// for a completion marker carrying the shell exit code, then tears the PTY
/// down. Base64-armoring avoids two real bugs with sending raw file bytes
/// through a PTY: canonical-mode TTY line-length truncation (~4096 bytes) and
/// control bytes (Ctrl-C/D/Z) being interpreted as signals instead of data.
class PtyFileWriter {
  PtyFileWriter({required this.client});

  final OpencodeClient client;

  static const _timeout = Duration(seconds: 15);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _ptyId;
  String? _directory;
  Completer<int>? _completer;
  bool _cancelled = false;

  Future<void> write({
    required String path,
    String? directory,
    required String content,
  }) async {
    _directory = directory;
    final target = _resolveTargetPath(path, directory);

    final session = await client.createPty(
      title: 'file-write',
      directory: directory,
      cwd: directory,
    );
    if (_cancelled) {
      await _bestEffortRemove(session.id, directory);
      return;
    }
    _ptyId = session.id;

    final completer = Completer<int>();
    _completer = completer;
    final buffer = StringBuffer();

    final delimiter = 'SPARK_EOF_${const Uuid().v4()}';
    final marker = 'SPARK_WRITE_DONE_${const Uuid().v4()}';
    final markerRe = RegExp('$marker:(-?\\d+)');

    final encoded = base64Encode(utf8.encode(content));
    final command = "base64 -d << '$delimiter' > ${_shellQuote(target)}\n"
        '$encoded\n'
        '$delimiter\n'
        "printf '\\n$marker:%d\\n' \$?\n";

    final uri = buildPtyWebSocketUri(
      client: client,
      ptyId: session.id,
      directory: directory,
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        (data) {
          if (completer.isCompleted) return;
          if (data is List<int>) {
            if (data.isNotEmpty && data[0] == 0x00) return;
            buffer.write(utf8.decode(data, allowMalformed: true));
          } else if (data is String) {
            buffer.write(data);
          }
          final match = markerRe.firstMatch(buffer.toString());
          if (match != null && !completer.isCompleted) {
            completer.complete(int.parse(match.group(1)!));
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) {
            completer.completeError(FileWriteException('WebSocket error: $e'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.completeError(
              FileWriteException('Connection closed before write confirmed'),
            );
          }
        },
      );

      channel.sink.add(utf8.encode(command));

      final exitCode = await completer.future.timeout(
        _timeout,
        onTimeout: () => throw FileWriteException(
            'Timed out waiting for write confirmation'),
      );
      if (exitCode != 0) {
        throw FileWriteException('Save failed (exit code $exitCode)',
            exitCode: exitCode);
      }
    } finally {
      await _teardown();
    }
  }

  /// Aborts an in-flight write and tears down the PTY without waiting for the
  /// timeout. Safe to call even if [write] never started or already finished.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(FileWriteException('Cancelled'));
    }
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    final id = _ptyId;
    if (id != null) {
      _ptyId = null;
      await _bestEffortRemove(id, _directory);
    }
  }

  Future<void> _bestEffortRemove(String id, String? directory) async {
    try {
      await client.removePty(id, directory: directory);
    } catch (_) {}
  }
}

String _resolveTargetPath(String path, String? directory) {
  if (path.startsWith('/')) return path;
  if (directory == null || directory.isEmpty) return path;
  final base = directory.endsWith('/')
      ? directory.substring(0, directory.length - 1)
      : directory;
  return '$base/$path';
}

String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";
