import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/api/providers.dart';
import '../../core/models/server_config.dart';
import '../../core/models/server_connection.dart';
import 'opencode_installer.dart';
import 'opencode_locator.dart';

export 'opencode_locator.dart' show isDesktopPlatform;

const localServerId = 'local';

enum LocalServerStatus {
  idle,
  locating,
  missing,
  installing,
  starting,
  healthy,
  stopping,
  failed,
}

@immutable
class LocalServerState {
  const LocalServerState({
    this.status = LocalServerStatus.idle,
    this.binaryPath,
    this.version,
    this.port,
    this.error,
    this.log = const [],
  });

  final LocalServerStatus status;
  final String? binaryPath;
  final String? version;
  final int? port;
  final String? error;
  final List<String> log;

  bool get isRunning =>
      status == LocalServerStatus.healthy ||
      status == LocalServerStatus.starting;

  String get statusLabel {
    switch (status) {
      case LocalServerStatus.idle:
        return binaryPath == null ? 'Not installed' : 'Stopped';
      case LocalServerStatus.locating:
        return 'Looking for opencode…';
      case LocalServerStatus.missing:
        return 'opencode not found';
      case LocalServerStatus.installing:
        return 'Installing opencode…';
      case LocalServerStatus.starting:
        return 'Starting local server…';
      case LocalServerStatus.healthy:
        return 'Running on 127.0.0.1:${port ?? ''}';
      case LocalServerStatus.stopping:
        return 'Stopping…';
      case LocalServerStatus.failed:
        return error ?? 'Failed';
    }
  }

  LocalServerState copyWith({
    LocalServerStatus? status,
    String? binaryPath,
    String? version,
    int? port,
    String? error,
    List<String>? log,
    bool clearBinary = false,
    bool clearVersion = false,
    bool clearPort = false,
    bool clearError = false,
  }) {
    return LocalServerState(
      status: status ?? this.status,
      binaryPath: clearBinary ? null : (binaryPath ?? this.binaryPath),
      version: clearVersion ? null : (version ?? this.version),
      port: clearPort ? null : (port ?? this.port),
      error: clearError ? null : (error ?? this.error),
      log: log ?? this.log,
    );
  }
}

class ServerLogBuffer {
  ServerLogBuffer({this.max = 500});

  final int max;
  final List<String> lines = [];

  void add(String line) {
    for (final part in line.split('\n')) {
      if (part.trim().isEmpty) continue;
      lines.add(part);
    }
    if (lines.length > max) {
      lines.removeRange(0, lines.length - max);
    }
  }

  List<String> snapshot() => List.unmodifiable(lines);
}

Future<int?> findFreePort({
  int start = 4096,
  int attempts = 40,
  InternetAddress? address,
}) async {
  final bindAddress = address ?? InternetAddress.loopbackIPv4;
  for (var port = start; port < start + attempts; port++) {
    try {
      final socket = await ServerSocket.bind(bindAddress, port);
      await socket.close();
      return port;
    } catch (_) {}
  }
  return null;
}

class LocalServerController extends Notifier<LocalServerState> {
  final ServerLogBuffer _buffer = ServerLogBuffer();
  Timer? _flushTimer;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _stopping = false;
  bool _disposed = false;
  int _restartAttempts = 0;
  static const int _maxRestarts = 3;

  @override
  LocalServerState build() {
    ref.onDispose(_handleDispose);
    if (isDesktopPlatform) {
      Future.microtask(() => unawaited(_init()));
    }
    return const LocalServerState();
  }

  Future<void> _init() async {
    await discover();
    if (state.binaryPath != null && state.status == LocalServerStatus.idle) {
      await start();
    }
  }

  Future<void> discover() async {
    if (!isDesktopPlatform) return;
    state = state.copyWith(
      status: LocalServerStatus.locating,
      clearError: true,
    );
    final path = await findOpencodeBinary();
    if (path == null) {
      state = state.copyWith(
        status: LocalServerStatus.missing,
        clearBinary: true,
        clearVersion: true,
      );
      return;
    }
    final version = await opencodeVersion(path);
    state = state.copyWith(
      status: LocalServerStatus.idle,
      binaryPath: path,
      version: version,
      clearError: true,
    );
  }

  Future<void> start() async {
    if (_stopping || _disposed) return;
    final current = state.status;
    if (current == LocalServerStatus.starting ||
        current == LocalServerStatus.healthy ||
        current == LocalServerStatus.installing) {
      return;
    }
    var binary = state.binaryPath;
    if (binary == null) {
      await discover();
      binary = state.binaryPath;
      if (binary == null) return;
    }
    final port = await findFreePort();
    if (port == null) {
      _fail('No free port available for the local server.');
      return;
    }
    _appendLog('Starting: opencode serve --port $port --hostname 127.0.0.1');
    Process process;
    try {
      process = await Process.start(
        binary,
        ['serve', '--port', '$port', '--hostname', '127.0.0.1'],
        runInShell: Platform.isWindows,
        workingDirectory: _homeDir(),
      );
    } catch (e) {
      _fail('Failed to launch opencode: $e');
      return;
    }
    _process = process;
    _stopping = false;
    state = state.copyWith(
      status: LocalServerStatus.starting,
      port: port,
      clearError: true,
    );
    _wireOutput(process);
    final exitCode = Completer<int>();
    process.exitCode.then((code) {
      if (!exitCode.isCompleted) exitCode.complete(code);
    });
    final healthy = await _awaitHealthy(process, port, exitCode.future);
    if (_stopping || _disposed) return;
    if (healthy) {
      _restartAttempts = 0;
      await _register(port);
      state = state.copyWith(
        status: LocalServerStatus.healthy,
        clearError: true,
      );
      exitCode.future.then((code) => _onUnexpectedExit(code));
      return;
    }
    final code = exitCode.isCompleted ? await exitCode.future : null;
    _teardownProcess();
    if (code != null) {
      _appendLog('opencode serve exited with code $code');
      _failOrRestart('Local server exited with code $code.');
    } else {
      _appendLog('Local server did not become healthy in time');
      _fail(
        'Local server did not respond on 127.0.0.1:$port within 60 seconds.',
      );
    }
  }

  Future<bool> _awaitHealthy(
    Process process,
    int port,
    Future<int> exitFuture,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      if (_stopping || _disposed) return false;
      if (_process != process) return false;
      if (await _health(port)) return true;
      final exited = await _exitWithin(
        exitFuture,
        const Duration(milliseconds: 400),
      );
      if (exited) return false;
      if (DateTime.now().isAfter(deadline)) return false;
    }
  }

  Future<bool> _exitWithin(Future<int> future, Duration d) async {
    try {
      await future.timeout(d);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> _health(int port) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:$port',
          connectTimeout: const Duration(milliseconds: 800),
          receiveTimeout: const Duration(milliseconds: 800),
        ),
      );
      final res = await dio.get(Endpoints.health);
      if (res.statusCode != 200) return false;
      final data = res.data;
      if (data is Map) {
        return data['healthy'] != false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _register(int port) async {
    final config = ServerConfig(
      id: localServerId,
      name: 'Local SparkCode',
      connection: ServerConnection(host: '127.0.0.1', port: port),
    );
    final activeId = ref.read(serverManagerProvider).activeId;
    final activate = activeId == null || activeId == localServerId;
    await ref
        .read(serverManagerProvider.notifier)
        .upsertServer(config, null, activate: activate);
  }

  void _onUnexpectedExit(int code) {
    if (_stopping || _disposed) return;
    if (state.status != LocalServerStatus.healthy) return;
    _appendLog('opencode serve exited unexpectedly (code $code)');
    _failOrRestart('Local server exited unexpectedly (code $code).');
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    if (state.status == LocalServerStatus.healthy ||
        state.status == LocalServerStatus.starting) {
      state = state.copyWith(status: LocalServerStatus.stopping);
    }
    _appendLog('Stopping local server…');
    final process = _process;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    _teardownProcess();
    await _deactivateLocal();
    _stopping = false;
    if (!_disposed) {
      state = state.copyWith(
        status: LocalServerStatus.idle,
        clearPort: true,
        clearError: true,
      );
      _appendLog('Local server stopped');
    }
  }

  Future<void> _deactivateLocal() async {
    final manager = ref.read(serverManagerProvider.notifier);
    final current = ref.read(serverManagerProvider);
    if (current.activeId != localServerId) return;
    final others = current.configs.where((c) => c.id != localServerId);
    if (others.isEmpty) {
      await manager.removeServer(localServerId);
    } else {
      await manager.setActive(others.first.id);
    }
  }

  Future<void> shutdown() async {
    _stopping = true;
    final process = _process;
    process?.kill();
    _teardownProcess();
  }

  Future<void> install() async {
    if (!isDesktopPlatform) return;
    if (state.status == LocalServerStatus.installing) return;
    final npmAvailable = await isOnPath('npm');
    final command = installCommandFor(
      defaultTargetPlatform,
      npmAvailable: npmAvailable,
    );
    if (command == null) {
      _fail(
        'npm was not found. Install Node.js, then run: npm install -g opencode-ai',
      );
      return;
    }
    state = state.copyWith(
      status: LocalServerStatus.installing,
      clearError: true,
    );
    _appendLog('Installing: ${command.executable} ${command.args.join(' ')}');
    try {
      final process = await Process.start(
        command.executable,
        command.args,
        runInShell: Platform.isWindows,
      );
      await _wireInstallOutput(process);
      final code = await process.exitCode;
      if (code != 0) {
        _fail('Installer exited with code $code.');
        return;
      }
      _appendLog('Install finished');
      await discover();
      if (state.binaryPath != null) {
        await start();
      } else {
        _fail('opencode still not found after install. Restart Spark.');
      }
    } catch (e) {
      _fail('Install failed: $e');
    }
  }

  Future<void> upgrade() async {
    final binary = state.binaryPath;
    if (binary == null) return;
    _appendLog('Upgrading opencode…');
    try {
      final process = await Process.start(
        binary,
        ['upgrade'],
        runInShell: Platform.isWindows,
        workingDirectory: _homeDir(),
      );
      await _wireInstallOutput(process);
      final code = await process.exitCode;
      if (code != 0) {
        _appendLog('Upgrade exited with code $code');
        return;
      }
      _appendLog('Upgrade finished');
      await discover();
    } catch (e) {
      _appendLog('Upgrade failed: $e');
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  void _failOrRestart(String message) {
    _appendLog(message);
    if (_restartAttempts >= _maxRestarts) {
      _fail(message);
      return;
    }
    _restartAttempts++;
    final delay = Duration(seconds: _restartAttempts);
    _appendLog(
      'Restarting in ${delay.inSeconds}s '
      '(attempt $_restartAttempts of $_maxRestarts)…',
    );
    state = state.copyWith(status: LocalServerStatus.idle, clearError: true);
    Timer(delay, () {
      if (_disposed || _stopping) return;
      unawaited(start());
    });
  }

  void _fail(String message) {
    _appendLog(message);
    state = state.copyWith(status: LocalServerStatus.failed, error: message);
  }

  void _wireOutput(Process process) {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
  }

  Future<void> _wireInstallOutput(Process process) async {
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
    final err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
    await process.exitCode;
    await out.cancel();
    await err.cancel();
  }

  void _teardownProcess() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _process = null;
  }

  void _appendLog(String line) {
    if (line.trim().isEmpty) return;
    _buffer.add(line);
    developer.log(line, name: 'local_server');
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 200), _flushLog);
  }

  void _flushLog() {
    if (_disposed) return;
    state = state.copyWith(log: _buffer.snapshot());
  }

  void _handleDispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    final process = _process;
    _process = null;
    process?.kill();
  }

  String _homeDir() {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return Directory.current.path;
    return home;
  }
}

final localServerProvider =
    NotifierProvider<LocalServerController, LocalServerState>(
      LocalServerController.new,
    );
