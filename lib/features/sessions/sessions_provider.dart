import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/session.dart';
import '../../core/storage/cache_service.dart';
import 'workspace_provider.dart';

/// The TTS preprocessing session is an implementation detail of "read aloud"
/// and must never appear in the session list — including when a cache written
/// before it was hidden is served after a request fails.
bool _isHiddenSession(Session s) =>
    s.title?.startsWith('[TTS Preprocessing]') == true;

void _sortSessions(List<Session> sessions) {
  sessions.sort((a, b) {
    final at = a.time?.updated ?? a.time?.created ?? 0;
    final bt = b.time?.updated ?? b.time?.created ?? 0;
    return bt.compareTo(at);
  });
}

/// Parses, filters and sorts a cached session payload; null when unusable.
List<Session>? _decodeCachedSessions(Map<String, dynamic>? cached) {
  final items = cached?['items'];
  if (items is! List) return null;
  final sessions = items
      .whereType<Map<String, dynamic>>()
      .map(Session.fromJson)
      .where((s) => !_isHiddenSession(s))
      .toList();
  _sortSessions(sessions);
  return sessions;
}

/// Cache-first, then network — see [cacheFirstThenFetch].
final sessionsProvider = StreamProvider<List<Session>>((ref) async* {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) {
    yield [];
    return;
  }
  final directory = ref.watch(selectedWorkspaceProvider)?.worktree;
  final cacheKey =
      'sessions/${directory != null ? Uri.encodeComponent(directory) : 'all'}.json';
  yield* cacheFirstThenFetch<Session>(
    readCache: () async => _decodeCachedSessions(await CacheService.instance
        .read(cacheKey, maxAge: const Duration(days: 30))),
    fetch: () async {
      final sessions = await client.listSessions(directory: directory);
      sessions.removeWhere(_isHiddenSession);
      _sortSessions(sessions);
      await CacheService.instance.write(cacheKey, {
        'items': sessions.map((s) => s.toJson()).toList(),
      });
      return sessions;
    },
  );
});

final allSessionsProvider = StreamProvider<List<Session>>((ref) async* {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) {
    yield [];
    return;
  }
  const cacheKey = 'sessions/all.json';
  yield* cacheFirstThenFetch<Session>(
    readCache: () async => _decodeCachedSessions(await CacheService.instance
        .read(cacheKey, maxAge: const Duration(days: 30))),
    fetch: () async {
      final projects = await ref.watch(projectsProvider.future);
      final directories =
          projects.where((p) => !p.isGlobal).map((p) => p.worktree).toList();
      final results = await Future.wait([
        client.listSessions(),
        for (final dir in directories) client.listSessions(directory: dir),
      ]);
      final seen = <String>{};
      final all = <Session>[];
      for (final sessions in results) {
        for (final s in sessions) {
          if (_isHiddenSession(s)) continue;
          if (seen.add(s.id)) all.add(s);
        }
      }
      _sortSessions(all);
      await CacheService.instance.write(cacheKey, {
        'items': all.map((s) => s.toJson()).toList(),
      });
      return all;
    },
  );
});

final sessionsRefreshProvider = StateProvider<int>((ref) => 0);

void refreshSessions(Ref ref) {
  ref.read(sessionsRefreshProvider.notifier).state++;
}

class SessionLifecycleListener extends Notifier<void> {
  @override
  void build() {
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      switch (event.type) {
        case 'session.created':
        case 'session.deleted':
          refreshSessions(ref);
          refreshProjects(ref);
      }
    });
  }
}

final sessionLifecycleProvider =
    NotifierProvider<SessionLifecycleListener, void>(
  SessionLifecycleListener.new,
);
