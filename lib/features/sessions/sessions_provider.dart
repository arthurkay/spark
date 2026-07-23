import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/session.dart';
import '../../core/storage/cache_service.dart';
import 'workspace_provider.dart';

final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  final directory = ref.watch(selectedWorkspaceProvider)?.worktree;
  final cacheKey =
      'sessions/${directory != null ? Uri.encodeComponent(directory) : 'all'}.json';
  try {
    final sessions = await client.listSessions(directory: directory);
    sessions.sort((a, b) {
      final at = a.time?.updated ?? a.time?.created ?? 0;
      final bt = b.time?.updated ?? b.time?.created ?? 0;
      return bt.compareTo(at);
    });
    await CacheService.instance.write(cacheKey, {
      'items': sessions.map((s) => s.toJson()).toList(),
    });
    return sessions;
  } on OpencodeApiException catch (_) {
    final cached = await CacheService.instance.read(cacheKey);
    if (cached != null) {
      final items = cached['items'] as List<dynamic>? ?? [];
      final sessions = items
          .whereType<Map<String, dynamic>>()
          .map(Session.fromJson)
          .toList();
      sessions.sort((a, b) {
        final at = a.time?.updated ?? a.time?.created ?? 0;
        final bt = b.time?.updated ?? b.time?.created ?? 0;
        return bt.compareTo(at);
      });
      return sessions;
    }
    return [];
  }
});

final allSessionsProvider = FutureProvider<List<Session>>((ref) async {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  const cacheKey = 'sessions/all.json';
  try {
    final projects = await ref.watch(projectsProvider.future);
    final seen = <String>{};
    final all = <Session>[];
    for (final s in await client.listSessions()) {
      if (seen.add(s.id)) all.add(s);
    }
    for (final p in projects) {
      if (p.isGlobal) continue;
      for (final s in await client.listSessions(directory: p.worktree)) {
        if (seen.add(s.id)) all.add(s);
      }
    }
    all.sort((a, b) {
      final at = a.time?.updated ?? a.time?.created ?? 0;
      final bt = b.time?.updated ?? b.time?.created ?? 0;
      return bt.compareTo(at);
    });
    await CacheService.instance.write(cacheKey, {
      'items': all.map((s) => s.toJson()).toList(),
    });
    return all;
  } on OpencodeApiException catch (_) {
    final cached = await CacheService.instance.read(cacheKey);
    if (cached != null) {
      final items = cached['items'] as List<dynamic>? ?? [];
      final sessions = items
          .whereType<Map<String, dynamic>>()
          .map(Session.fromJson)
          .toList();
      sessions.sort((a, b) {
        final at = a.time?.updated ?? a.time?.created ?? 0;
        final bt = b.time?.updated ?? b.time?.created ?? 0;
        return bt.compareTo(at);
      });
      return sessions;
    }
    return [];
  }
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
