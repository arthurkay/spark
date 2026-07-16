import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/server_connection.dart';
import '../storage/connection_store.dart';
import 'opencode_client.dart';
import 'sse_client.dart';

final connectionStoreProvider = Provider<ConnectionStore>((ref) {
  return ConnectionStore();
});

class ConnectionState {
  const ConnectionState({this.connection, this.password});

  final ServerConnection? connection;
  final String? password;

  bool get isConfigured => connection != null;
}

class ConnectionController extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => const ConnectionState();

  ConnectionStore get _store => ref.read(connectionStoreProvider);

  Future<void> restore() async {
    final stored = await _store.load();
    if (stored != null) {
      state = ConnectionState(
        connection: stored.connection,
        password: stored.password,
      );
    }
  }

  Future<void> connect(ServerConnection connection, String? password) async {
    await _store.save(connection, password);
    state = ConnectionState(connection: connection, password: password);
  }

  Future<void> disconnect() async {
    await _store.clear();
    state = const ConnectionState();
  }
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, ConnectionState>(
      ConnectionController.new,
    );

final opencodeClientProvider = Provider<OpencodeClient?>((ref) {
  final state = ref.watch(connectionControllerProvider);
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
      case 'session.removed':
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
