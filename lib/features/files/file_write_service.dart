import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
/// user never sees and drives it in three steps:
///
/// 1. Send a single short command line — `sh -c '…'`, so the script is POSIX
///    regardless of which login shell the server picked — that turns off TTY
///    echo, prints a ready marker, and then runs `base64 -d > path`.
/// 2. Once the ready marker arrives, stream the base64-armored content as
///    **stdin of that already-running `base64`**, then a single `0x04` (EOF).
/// 3. Wait for a completion marker carrying the shell exit code and the
///    resulting file size, then tear the PTY down in the background.
///
/// Three properties of the payload path matter, and each of them was a real
/// bug before:
///
/// * The content must never be typed *at the shell prompt*. An interactive
///   line editor (zsh's ZLE) echoes and re-renders pasted input continuously,
///   so a 20 KB heredoc produced megabytes of output and quadratic work here.
///   Feeding stdin of a running command bypasses the line editor entirely.
/// * Base64 lines are wrapped at [_base64LineWidth]. A TTY in canonical mode
///   silently discards input past ~4096 bytes on a single line, which used to
///   truncate the payload (and lose the heredoc terminator) for any file over
///   ~3 KB.
/// * Base64-armoring keeps control bytes (Ctrl-C/D/Z) out of the payload, so
///   the TTY can't interpret file content as signals.
class PtyFileWriter {
  PtyFileWriter({required this.client});

  final OpencodeClient client;

  /// Marker prefix. The script assembles this at runtime from `$p` so that the
  /// shell's *echo of the command line* can never itself match a marker.
  static const _markerPrefix = 'SPARK_FW';
  static const _base64LineWidth = 76;
  static const _payloadChunkBytes = 2048;

  static const _connectTimeout = Duration(seconds: 15);
  static const _readyTimeout = Duration(seconds: 12);
  static const _teardownTimeout = Duration(seconds: 5);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _ptyId;
  String? _directory;
  Completer<void>? _readyCompleter;
  Completer<_WriteResult>? _doneCompleter;
  bool _cancelled = false;

  Future<void> write({
    required String path,
    String? directory,
    required String content,
  }) async {
    _directory = directory;
    final target = _resolveTargetPath(path, directory);
    final expectedBytes = utf8.encode(content).length;
    final payload = wrapBase64Lines(base64Encode(utf8.encode(content)),
        width: _base64LineWidth);

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

    final nonce = const Uuid().v4();
    final readyRe = RegExp('${_markerPrefix}_RDY:$nonce');
    final doneRe = RegExp('${_markerPrefix}_DONE:$nonce:(-?\\d+):(\\d+)');

    final ready = Completer<void>();
    final done = Completer<_WriteResult>();
    _readyCompleter = ready;
    _doneCompleter = done;
    // Both futures are awaited conditionally (a failure while waiting on
    // `ready` means `done` is never awaited), so keep a no-op listener on each
    // to stop an unawaited rejection becoming an unhandled async error.
    unawaited(ready.future.catchError((_) {}));
    unawaited(done.future.catchError((_) => const _WriteResult(-1, -1)));

    final tail = MarkerTail();
    void fail(String message) {
      if (!ready.isCompleted) ready.completeError(FileWriteException(message));
      if (!done.isCompleted) done.completeError(FileWriteException(message));
    }

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
          if (done.isCompleted) return;
          final String text;
          if (data is List<int>) {
            // The server's first binary frame is a `\x00{"cursor":n}` control
            // message, not terminal output.
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
          final match = tail.match(doneRe);
          if (match != null) {
            done.complete(_WriteResult(
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
            ));
          }
        },
        onError: (Object e) => fail('WebSocket error: $e'),
        onDone: () => fail('Connection closed before write confirmed'),
      );

      await channel.ready.timeout(
        _connectTimeout,
        onTimeout: () =>
            throw FileWriteException('Timed out connecting to the server'),
      );

      channel.sink.add(utf8.encode('${_buildCommand(target, nonce)}\n'));

      await ready.future.timeout(
        _readyTimeout,
        onTimeout: () => throw FileWriteException(
          'Timed out waiting for the shell to accept the write'
              '${_diagnostics(tail)}',
        ),
      );

      for (final chunk in chunkPayload(payload, maxBytes: _payloadChunkBytes)) {
        if (_cancelled || done.isCompleted) break;
        channel.sink.add(utf8.encode(chunk));
        // Let `base64` drain: a TTY in canonical mode buffers only ~4 KB of
        // unread input, and throttles the writer beyond that.
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      if (_cancelled) throw FileWriteException('Cancelled');
      if (!done.isCompleted) channel.sink.add(const <int>[0x04]);

      final result = await done.future.timeout(
        _writeTimeoutFor(payload.length),
        onTimeout: () => throw FileWriteException(
          'Timed out waiting for write confirmation${_diagnostics(tail)}',
        ),
      );
      if (result.exitCode != 0) {
        throw FileWriteException(
          'Save failed (exit code ${result.exitCode})${_diagnostics(tail)}',
          exitCode: result.exitCode,
        );
      }
      if (result.size != expectedBytes) {
        throw FileWriteException(
          'Save incomplete: wrote ${result.size} of $expectedBytes bytes',
        );
      }
    } finally {
      // Cleanup — closing the socket and deleting the PTY — must never gate
      // the result: the file is already written by the time the marker lands.
      _scheduleTeardown();
    }
  }

  /// Aborts an in-flight write and tears down the PTY without waiting for the
  /// timeout. Safe to call even if [write] never started or already finished.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final ready = _readyCompleter;
    final done = _doneCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(FileWriteException('Cancelled'));
    }
    if (done != null && !done.isCompleted) {
      done.completeError(FileWriteException('Cancelled'));
    }
    _scheduleTeardown();
  }

  /// One short line, well under the TTY's canonical-mode line limit.
  ///
  /// `$p` exists so the marker text only ever appears in the *output* of
  /// `printf`, never in the shell's echo of this line — otherwise the echo
  /// would be mistaken for the ready marker and the payload would be sent
  /// before `base64` was reading.
  String _buildCommand(String target, String nonce) {
    final quotedTarget = _shellQuote(target);
    final script = 'p=$_markerPrefix; stty -echo 2>/dev/null; '
        "printf '\\n%s_RDY:$nonce\\n' \"\$p\"; "
        'base64 -d > $quotedTarget; rc=\$?; '
        "sz=\$(wc -c < $quotedTarget 2>/dev/null | tr -d ' \\n'); "
        "printf '\\n%s_DONE:$nonce:%s:%s\\n' \"\$p\" \"\$rc\" \"\${sz:-0}\"";
    return 'sh -c ${_shellQuote(script)}';
  }

  static Duration _writeTimeoutFor(int payloadBytes) => Duration(
        seconds: math.min(60, math.max(20, payloadBytes ~/ 8192)),
      );

  String _diagnostics(MarkerTail tail) {
    final snippet = tail.snippet().trim();
    return snippet.isEmpty ? '' : ': $snippet';
  }

  void _scheduleTeardown() {
    unawaited(
      _teardown().timeout(_teardownTimeout, onTimeout: () {}).catchError((_) {}),
    );
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

class _WriteResult {
  const _WriteResult(this.exitCode, this.size);

  final int exitCode;
  final int size;
}

/// A bounded, rolling view of the most recent PTY output.
///
/// Marker detection used to concatenate every frame into a `StringBuffer` and
/// re-scan the whole transcript on each frame — quadratic, and slow enough on
/// a noisy PTY to starve the timers and `setState` calls waiting on the write.
/// Only the tail can contain a marker, so only the tail is kept.
class MarkerTail {
  MarkerTail({this.capacity = 4096});

  /// Must comfortably exceed the longest marker so one can never be split
  /// across two appends.
  final int capacity;

  String _tail = '';

  void append(String chunk) {
    if (chunk.isEmpty) return;
    _tail = _tail.isEmpty ? chunk : '$_tail$chunk';
    if (_tail.length > capacity) {
      _tail = _tail.substring(_tail.length - capacity);
    }
  }

  Match? match(RegExp pattern) => pattern.firstMatch(_tail);

  /// The trailing [max] characters, for error messages.
  String snippet([int max = 512]) =>
      _tail.length <= max ? _tail : _tail.substring(_tail.length - max);
}

/// Splits [encoded] into newline-terminated lines of at most [width] chars.
///
/// Returns the empty string for empty input; every other result ends in a
/// newline, which matters because a TTY only honours the EOF character at the
/// start of a line.
String wrapBase64Lines(String encoded, {int width = 76}) {
  if (encoded.isEmpty) return '';
  final out = StringBuffer();
  for (var i = 0; i < encoded.length; i += width) {
    out.write(encoded.substring(i, math.min(i + width, encoded.length)));
    out.write('\n');
  }
  return out.toString();
}

/// Groups the wrapped [payload] into whole-line chunks of at most [maxBytes].
///
/// Chunks end on line boundaries so the TTY always has complete lines to hand
/// to the reader. A single line longer than [maxBytes] is emitted on its own.
List<String> chunkPayload(String payload, {int maxBytes = 2048}) {
  if (payload.isEmpty) return const [];
  final chunks = <String>[];
  final current = StringBuffer();
  for (final line in payload.split('\n')) {
    if (line.isEmpty) continue;
    if (current.length > 0 && current.length + line.length + 1 > maxBytes) {
      chunks.add(current.toString());
      current.clear();
    }
    current.write(line);
    current.write('\n');
  }
  if (current.length > 0) chunks.add(current.toString());
  return chunks;
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

/// Test hooks for the pure helpers above.
String debugResolveTargetPath(String path, String? directory) =>
    _resolveTargetPath(path, directory);

String debugShellQuote(String s) => _shellQuote(s);
