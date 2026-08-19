import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/pty_ws.dart';
import '../../core/models/terminal.dart';
import '../../shared/utf8_chunker.dart';

class PtyConnectionState {
  const PtyConnectionState({
    this.session,
    this.connecting = false,
    this.connected = false,
    this.error,
  });

  final PtySession? session;
  final bool connecting;
  final bool connected;
  final String? error;

  PtyConnectionState copyWith({
    PtySession? session,
    bool? connecting,
    bool? connected,
    String? error,
  }) {
    return PtyConnectionState(
      session: session ?? this.session,
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      error: error,
    );
  }
}

class PtyController extends ChangeNotifier {
  PtyController({
    required this.client,
    required this.directory,
    required this.terminal,
  });

  final OpencodeClient client;
  final String? directory;
  final xterm.Terminal terminal;

  PtyConnectionState _state = const PtyConnectionState();
  PtyConnectionState get state => _state;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _flushTimer;
  Timer? _resizeDebounce;
  final List<int> _pendingBytes = [];
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _exited = false;

  static const _maxReconnectAttempts = 6;

  Future<void> init() async {
    if (_disposed) return;
    _setState(connecting: true);
    try {
      final session =
          await client.createPty(title: 'Terminal', directory: directory);
      _setState(session: session, connecting: false);
      _connectWebSocket(session.id);
    } catch (e) {
      _setState(connecting: false, error: 'Failed to create terminal: $e');
    }
  }

  void _setState({
    PtySession? session,
    bool? connecting,
    bool? connected,
    String? error,
  }) {
    _state = _state.copyWith(
      session: session,
      connecting: connecting,
      connected: connected,
      error: error,
    );
    notifyListeners();
  }

  void _connectWebSocket(String ptyId) {
    if (_disposed) return;
    _cleanup();

    final url = buildPtyWebSocketUri(
      client: client,
      ptyId: ptyId,
      directory: directory,
    );

    try {
      _channel = WebSocketChannel.connect(url);
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        (data) {
          if (_disposed) return;
          if (data is List<int>) {
            if (data.isNotEmpty && data[0] == 0x00) {
              return;
            }
            _bufferOutput(data);
          } else if (data is String) {
            _flushPendingBytes();
            terminal.write(data);
          }
        },
        onDone: () {
          if (!_disposed && !_exited) {
            _setState(connected: false);
            _scheduleReconnect(ptyId);
          }
        },
        onError: (Object e) {
          if (!_disposed && !_exited) {
            _setState(connected: false, error: 'Connection error: $e');
            _scheduleReconnect(ptyId);
          }
        },
      );

      _setState(connecting: false, connected: true, error: null);

      terminal.onOutput = (data) {
        if (!_disposed && _channel != null) {
          _channel!.sink.add(data);
        }
      };

      terminal.onResize = (w, h, pw, ph) {
        if (_disposed) return;
        // Debounced: the terminal sheet's height is derived from viewInsets, so
        // opening the keyboard fires a resize per animation frame — each of
        // which used to issue its own HTTP request.
        _resizeDebounce?.cancel();
        _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
          if (!_disposed) _resizePty(w, h);
        });
      };
    } catch (e) {
      _setState(connected: false, error: 'WebSocket error: $e');
      _scheduleReconnect(ptyId);
    }
  }

  /// Coalesces PTY output into one write per frame.
  ///
  /// Each WebSocket frame used to become its own `terminal.write`, and each
  /// write notifies the view — a command producing a lot of output could force
  /// hundreds of parses and repaints per second. Buffering to a ~16ms tick
  /// bounds that to one per frame.
  void _bufferOutput(List<int> data) {
    _pendingBytes.addAll(data);
    _flushTimer ??= Timer(const Duration(milliseconds: 16), _flushPendingBytes);
  }

  void _flushPendingBytes() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingBytes.isEmpty || _disposed) return;

    // Decode with the previous frame's trailing bytes prepended: a multi-byte
    // UTF-8 sequence split across frames would otherwise decode to replacement
    // characters. Any incomplete trailing sequence is held back for next time.
    final bytes = Uint8List.fromList(_pendingBytes);
    _pendingBytes.clear();
    final split = splitTrailingIncompleteUtf8(bytes);
    if (split.complete.isNotEmpty) {
      terminal.write(utf8.decode(split.complete, allowMalformed: true));
    }
    _pendingBytes.addAll(split.incomplete);
  }

  Future<void> _resizePty(int cols, int rows) async {
    final session = _state.session;
    if (session == null || _disposed) return;
    try {
      await client.resizePty(
        session.id,
        cols: cols,
        rows: rows,
        directory: directory,
      );
    } catch (_) {}
  }

  void _scheduleReconnect(String ptyId) {
    if (_disposed || _exited) return;
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setState(connected: false, error: 'Connection lost');
      return;
    }
    final delay = Duration(
      milliseconds: 500 * (1 << _reconnectAttempts.clamp(0, 4)),
    );
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () => _connectWebSocket(ptyId));
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    terminal.onOutput = null;
    terminal.onResize = null;
  }

  Future<void> kill() async {
    if (_exited) return;
    _exited = true;
    final session = _state.session;
    if (session != null) {
      try {
        await client.removePty(session.id, directory: directory);
      } catch (_) {}
    }
    _cleanup();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _resizeDebounce?.cancel();
    kill();
    super.dispose();
  }
}

/// Deliberately NOT autoDispose: the controller (terminal buffer, PTY,
/// websocket) outlives the sheet, so closing the sheet just hides it and
/// reopening reattaches to the same shell with its scrollback intact. Ending
/// the session is an explicit action in the sheet, which kills the PTY and
/// invalidates this provider so the next open starts fresh.
final terminalProvider =
    ChangeNotifierProvider.family<PtyController?, String?>((ref, directory) {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return null;

  final terminal = xterm.Terminal();

  final controller = PtyController(
    client: client,
    directory: directory,
    terminal: terminal,
  );

  ref.onDispose(controller.dispose);

  controller.init();

  return controller;
});
