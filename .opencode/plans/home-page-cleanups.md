# Home Page Cleanups Plan

## Overview
Dead code removal and structural refactoring in `lib/features/sessions/sessions_screen.dart`.
No behavioral changes — same UI, cleaner code.

---

## 1. Dead Code Removal

### 1a. Redundant ternary (line 246)

**Current:**
```dart
final key = project.isGlobal ? project.worktree : project.worktree;
```

**Fix:** Replace with:
```dart
final key = project.worktree;
```

### 1b. Dead "Projects" label row (lines 447-452)

**Current:**
```dart
Row(
  children: [
    const Text('Projects').small.semiBold.muted,
    const Spacer(),
  ],
),
```

**Fix:** Remove entirely. The workspace tiles already display project names as their headers. This row adds visual noise with no information.

### 1c. Duplicated `_WorkspaceTile` builder (lines 512-554)

The `loading` and `error` branches of `sessionsAsync.when()` both build identical `_WorkspaceTile` lists with empty sessions. Extract to a helper:

```dart
Widget _buildProjectTiles(List<Project> projects, WidgetRef ref) {
  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        return _WorkspaceTile(
          project: project,
          sessions: const [],
          onCreateSession: (ctx) => _createSession(
            ctx,
            ref,
            directory: project.isGlobal ? null : project.worktree,
          ),
          onShowProjectMenu: (ctx) => _showProjectMenu(ctx, ref, project),
        );
      },
    ),
  );
}
```

Then the `sessionsAsync.when()` becomes:
```dart
loading: () => _buildProjectTiles(projects, ref),
error: (_, __) => _buildProjectTiles(projects, ref),
data: (sessions) { ... },
```

---

## 2. Structural Refactor

### 2a. Extract `_buildWorkspaces` to `lib/shared/widgets/workspace_utils.dart`

Move the workspace grouping logic out of `_ProjectsScreenState` into a standalone pure function:

```dart
// lib/shared/widgets/workspace_utils.dart
List<WorkspaceGroup> buildWorkspaceGroups(
  List<Session> sessions,
  List<Project> projects,
) { ... }
```

Also move `_WorkspaceGroup` class here (rename to `WorkspaceGroup` — public).

Update `sessions_screen.dart` to import and call `buildWorkspaceGroups()` instead of `_buildWorkspaces()`.

### 2b. Fix `_filterSessions` provider read

**Current (line 311):**
```dart
List<Session> _filterSessions(List<Session> sessions) {
  final q = _query.toLowerCase();
  final active = ref.watch(sessionActivityProvider);  // called on every filter pass
```

**Fix:** Read `sessionActivityProvider` once at the top of `build()` and pass it in:

```dart
// In build():
final activeSessions = ref.watch(sessionActivityProvider);

// Method signature:
List<Session> _filterSessions(List<Session> sessions, Set<String> active) {
  final q = _query.toLowerCase();
  return sessions.where((s) {
    final matchesQuery = q.isEmpty ||
        (s.title?.toLowerCase().contains(q) ?? false) ||
        (s.directory?.toLowerCase().contains(q) ?? false);
    final matchesFilter = _filter == 'all' ||
        (_filter == 'active' && active.contains(s.id)) ||
        (_filter == 'idle' && !active.contains(s.id));
    return matchesQuery && matchesFilter;
  }).toList();
}
```

### 2c. Extract filter chip widget

Replace the 36-line inline `GestureDetector` + `Container` + `Text` builder (lines 407-443) with a small `_FilterChip` widget:

```dart
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.foreground
              : Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Theme.of(context).colorScheme.background
                : Theme.of(context).colorScheme.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
```

Then the filter row becomes:
```dart
SizedBox(
  height: 34,
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: 3,
    separatorBuilder: (_, __) => const Gap(8),
    itemBuilder: (context, index) {
      final options = [('all', 'All'), ('active', 'Active'), ('idle', 'Idle')];
      final opt = options[index];
      return _FilterChip(
        label: opt.$2,
        selected: _filter == opt.$1,
        onTap: () => setState(() => _filter = opt.$1),
      );
    },
  ),
),
```

---

## Files Summary

| File | Action | Lines (est.) |
|------|--------|-------------|
| `lib/features/sessions/sessions_screen.dart` | Edit — remove dead code, refactor | -40 net |
| `lib/shared/widgets/workspace_utils.dart` | **New** — extracted workspace grouping | ~60 |

**Net change: ~20 fewer lines, cleaner structure**

---

## Verification

- Run `flutter analyze` — no new warnings
- Run `dart format .` — formatting clean
- Manual: home page renders identically (same tiles, same filtering, same expand/collapse)
- Manual: search + filter still work correctly
- Manual: workspace grouping unchanged (projects with sessions show correctly)
