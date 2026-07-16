import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/providers.dart';
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
  final sessions = await client.listSessions();
  sessions.sort((a, b) {
    final at = a.time?.updated ?? a.time?.created ?? 0;
    final bt = b.time?.updated ?? b.time?.created ?? 0;
    return bt.compareTo(at);
  });
  return sessions;
});

final sessionsRefreshProvider = StateProvider<int>((ref) => 0);

void refreshSessions(Ref ref) {
  ref.read(sessionsRefreshProvider.notifier).state++;
}
