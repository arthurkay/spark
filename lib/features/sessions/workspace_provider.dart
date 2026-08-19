import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/providers.dart';
import '../../core/models/project.dart';
import '../../core/models/vcs.dart';
import '../../core/storage/cache_service.dart';

const _projectsCacheKey = 'projects/list.json';

void _sortProjects(List<Project> projects) {
  projects.sort((a, b) {
    if (a.isGlobal != b.isGlobal) return a.isGlobal ? 1 : -1;
    return a.worktree.compareTo(b.worktree);
  });
}

/// Cache-first: the last known project list renders immediately (the sessions
/// screen sits behind this — a cold offline start used to stare at a loader
/// for the full connect timeout), then the network refreshes it.
final projectsProvider = StreamProvider<List<Project>>((ref) async* {
  ref.watch(projectsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) {
    yield [];
    return;
  }
  yield* cacheFirstThenFetch<Project>(
    readCache: () async {
      final cached = await CacheService.instance
          .read(_projectsCacheKey, maxAge: const Duration(days: 30));
      final items = cached?['items'];
      if (items is! List) return null;
      final projects = items
          .whereType<Map<String, dynamic>>()
          .map(Project.fromJson)
          .toList();
      _sortProjects(projects);
      return projects;
    },
    fetch: () async {
      final projects = await client.listProjects();
      _sortProjects(projects);
      await CacheService.instance.write(_projectsCacheKey, {
        'items': projects.map((p) => p.toJson()).toList(),
      });
      return projects;
    },
  );
});

final projectsRefreshProvider = StateProvider<int>((ref) => 0);

void refreshProjects(Ref ref) {
  ref.read(projectsRefreshProvider.notifier).state++;
}

final selectedWorkspaceProvider =
    StateNotifierProvider<_SelectedWorkspace, Project?>(_SelectedWorkspace.new);

class _SelectedWorkspace extends StateNotifier<Project?> {
  _SelectedWorkspace(this.ref) : super(null) {
    _load();
  }

  final Ref ref;

  static const _key = 'opencode_workspace_dir';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = prefs.getString(_key);
    if (dir == null) return;
    final projects = await ref.read(projectsProvider.future);
    state = projects.where((p) => p.worktree == dir).firstOrNull ??
        Project(id: '__custom__', worktree: dir);
  }

  Future<void> select(Project? project) async {
    state = project;
    final prefs = await SharedPreferences.getInstance();
    if (project != null) {
      await prefs.setString(_key, project.worktree);
    } else {
      await prefs.remove(_key);
    }
  }

  String? get directory => state?.worktree;
}

final vcsRefreshProvider = StateProvider<int>((ref) => 0);

/// Branch info per worktree. A single global lookup used to feed every
/// project tile, so all projects displayed whichever branch the server's
/// default directory was on.
final vcsProvider =
    FutureProvider.family<VcsInfo?, String?>((ref, directory) async {
  ref.watch(vcsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return null;
  try {
    return await client.getVcsInfo(directory: directory);
  } catch (_) {
    return null;
  }
});
