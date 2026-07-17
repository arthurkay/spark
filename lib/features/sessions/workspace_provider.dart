import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/providers.dart';
import '../../core/models/project.dart';

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  ref.watch(projectsRefreshProvider);
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  final projects = await client.listProjects();
  projects.sort((a, b) {
    if (a.isGlobal != b.isGlobal) return a.isGlobal ? 1 : -1;
    return a.worktree.compareTo(b.worktree);
  });
  return projects;
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
