import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/server_config.dart';
import '../models/server_connection.dart';
import '../storage/connection_store.dart';
import 'opencode_client.dart';
import 'sse_client.dart';

final connectionStoreProvider = Provider<ConnectionStore>((ref) {
  return ConnectionStore();
});

class ServerManagerState {
  const ServerManagerState({
    this.configs = const [],
    this.activeId,
    this.password,
  });

  final List<ServerConfig> configs;
  final String? activeId;
  final String? password;

  bool get isConfigured => activeConfig != null;

  ServerConfig? get activeConfig {
    if (activeId == null) return null;
    return configs.where((c) => c.id == activeId).firstOrNull;
  }

  ServerConnection? get connection => activeConfig?.connection;

  ServerManagerState copyWith({
    List<ServerConfig>? configs,
    String? activeId,
    String? password,
  }) {
    return ServerManagerState(
      configs: configs ?? this.configs,
      activeId: activeId ?? this.activeId,
      password: password ?? this.password,
    );
  }
}

class ServerManagerController extends Notifier<ServerManagerState> {
  @override
  ServerManagerState build() => const ServerManagerState();

  ConnectionStore get _store => ref.read(connectionStoreProvider);

  Future<void> restore() async {
    final configs = await _store.loadAll();
    final activeId = await _store.loadActiveId();
    String? password;
    if (activeId != null) {
      password = await _store.loadPassword(activeId);
    }
    state = ServerManagerState(
      configs: configs,
      activeId: activeId,
      password: password,
    );
  }

  Future<void> addServer(ServerConfig config, String? password) async {
    await _store.addServer(config, password);
    state = ServerManagerState(
      configs: await _store.loadAll(),
      activeId: config.id,
      password: password,
    );
  }

  Future<void> updateServer(ServerConfig config, String? password) async {
    await _store.updateServer(config, password);
    final isActive = state.activeId == config.id;
    state = ServerManagerState(
      configs: await _store.loadAll(),
      activeId: state.activeId,
      password: isActive ? password : state.password,
    );
  }

  Future<void> removeServer(String serverId) async {
    await _store.removeServer(serverId);
    final configs = await _store.loadAll();
    final activeId = await _store.loadActiveId();
    String? password;
    if (activeId != null) {
      password = await _store.loadPassword(activeId);
    }
    state = ServerManagerState(
      configs: configs,
      activeId: activeId,
      password: password,
    );
  }

  Future<void> setActive(String serverId, {String? password}) async {
    await _store.setActiveId(serverId);
    final pw = password ?? await _store.loadPassword(serverId);
    state = state.copyWith(activeId: serverId, password: pw);
  }

  Future<void> connect(ServerConfig config, String? password) async {
    await _store.addServer(config, password);
    state = ServerManagerState(
      configs: await _store.loadAll(),
      activeId: config.id,
      password: password,
    );
  }

  Future<void> disconnect() async {
    if (state.activeId == null) return;
    await _store.removeServer(state.activeId!);
    final configs = await _store.loadAll();
    final activeId = configs.isNotEmpty ? configs.first.id : null;
    String? password;
    if (activeId != null) {
      password = await _store.loadPassword(activeId);
    }
    state = ServerManagerState(
      configs: configs,
      activeId: activeId,
      password: password,
    );
  }
}

final serverManagerProvider =
    NotifierProvider<ServerManagerController, ServerManagerState>(
  ServerManagerController.new,
);

final opencodeClientProvider = Provider<OpencodeClient?>((ref) {
  final state = ref.watch(serverManagerProvider);
  final connection = state.connection;
  if (connection == null) return null;
  final client = OpencodeClient(
    connection: connection,
    password: state.password,
  );
  ref.onDispose(client.close);
  return client;
});

final eventStreamProvider = StreamProvider<OpencodeEvent>((ref) {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) {
    return const Stream.empty();
  }
  final sse = SseClient(client.dio);
  ref.onDispose(sse.dispose);
  return sse.connect();
});

final sessionBusyProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);

final appPausedProvider = StateProvider<bool>((ref) => false);

class SessionActivityController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      _onEvent(event);
    });
    return const <String>{};
  }

  void _onEvent(OpencodeEvent event) {
    switch (event.type) {
      case 'session.status':
        final props = event.properties;
        final status = props['status'];
        final sid = _sid(props);
        if (sid == null) return;
        if (status is Map && status['type'] == 'busy') {
          state = {...state, sid};
        } else if (status is Map && status['type'] == 'idle') {
          state = {...state}..remove(sid);
        }
      case 'session.idle':
        final sid = _sid(event.properties);
        if (sid != null) state = {...state}..remove(sid);
      case 'session.updated':
      case 'session.deleted':
      case 'server.reconnected':
        if (event.type == 'server.reconnected') {
          state = const <String>{};
        }
    }
  }

  String? _sid(Map<String, dynamic> props) {
    if (props['sessionID'] is String) return props['sessionID'] as String;
    final info = props['info'];
    if (info is Map && info['sessionID'] is String) {
      return info['sessionID'] as String;
    }
    return null;
  }

  void setBusy(String id, bool busy) {
    if (busy) {
      state = {...state, id};
    } else {
      state = {...state}..remove(id);
    }
  }
}

final sessionActivityProvider =
    NotifierProvider<SessionActivityController, Set<String>>(
  SessionActivityController.new,
);
