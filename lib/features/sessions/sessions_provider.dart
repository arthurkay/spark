import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/session.dart';
import 'workspace_provider.dart';

final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  final directory = ref.watch(selectedWorkspaceProvider)?.worktree;
  final sessions = await client.listSessions(directory: directory);
  sessions.sort((a, b) {
    final at = a.time?.updated ?? a.time?.created ?? 0;
    final bt = b.time?.updated ?? b.time?.created ?? 0;
    return bt.compareTo(at);
  });
  return sessions;
});

final allSessionsProvider = FutureProvider<List<Session>>((ref) async {
  ref.watch(sessionsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
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
  return all;
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
