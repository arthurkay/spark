import '../../core/models/project.dart';
import '../../core/models/session.dart';

class WorkspaceGroup {
  const WorkspaceGroup({required this.project, required this.sessions});

  final Project project;
  final List<Session> sessions;
}

List<WorkspaceGroup> buildWorkspaceGroups(
  List<Session> sessions,
  List<Project> projects,
) {
  final sortedProjects = [...projects]..sort((a, b) {
      if (a.isGlobal != b.isGlobal) return a.isGlobal ? 1 : -1;
      return a.worktree.compareTo(b.worktree);
    });

  String workspaceKeyFor(String? dir) {
    if (dir == null || dir.isEmpty) return '__ungrouped__';
    String? best;
    for (final p in sortedProjects) {
      final ws = p.worktree;
      if (ws.isEmpty) continue;
      if (dir == ws || dir.startsWith('$ws/')) {
        if (best == null || ws.length > best.length) best = ws;
      }
    }
    return best ?? '__ungrouped__';
  }

  final buckets = <String, List<Session>>{};
  for (final session in sessions) {
    final key = workspaceKeyFor(session.directory);
    buckets.putIfAbsent(key, () => []).add(session);
  }

  final global = sortedProjects.where((p) => p.isGlobal).firstOrNull;
  if (global != null && buckets['__ungrouped__'] != null) {
    buckets
        .putIfAbsent(global.worktree, () => [])
        .addAll(buckets.remove('__ungrouped__')!);
  }

  final groups = <WorkspaceGroup>[];
  for (final project in sortedProjects) {
    final key = project.worktree;
    groups.add(
      WorkspaceGroup(
        project: project,
        sessions: buckets.remove(key) ?? const [],
      ),
    );
  }
  final remaining = buckets.values.expand((e) => e).toList();
  if (remaining.isNotEmpty) {
    groups.add(
      WorkspaceGroup(
        project: Project(id: '__other__', worktree: '__other__'),
        sessions: remaining,
      ),
    );
  }
  return groups;
}
