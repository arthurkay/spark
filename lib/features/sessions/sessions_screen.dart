import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/project.dart';
import '../../core/models/session.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/path_utils.dart';
import '../permissions/permission_banner.dart';
import 'sessions_provider.dart';
import 'workspace_provider.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _filter = 'all';
  final Set<String> _expanded = {};

  Future<void> _createSession(
    BuildContext context,
    WidgetRef ref, {
    String? directory,
  }) async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final session = await client.createSession(directory: directory);
      ref.read(sessionsRefreshProvider.notifier).state++;
      if (!context.mounted) return;
      context.push('/session/${session.id}');
    } on OpencodeApiException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, title: 'Failed to create', description: e.message);
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Session session) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.trash2, color: Colors.red),
                  const Gap(8),
                  const Text('Delete session').h4,
                ],
              ),
              const Gap(12),
              Text(
                'This will permanently delete '
                '"${session.title?.trim().isNotEmpty == true ? session.title! : 'this session'}". '
                'This cannot be undone.',
              ).muted,
              const Gap(20),
              DestructiveButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  _deleteSession(context, ref, session);
                },
                child: const Text('Delete'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () => closeSheet(sheetContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      await client.deleteSession(session.id);
      ref.read(sessionsRefreshProvider.notifier).state++;
    } on OpencodeApiException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, title: 'Failed to delete', description: e.message);
    }
  }

  List<_WorkspaceGroup> _buildWorkspaces(
    List<Session> sessions,
    List<Project> projects,
  ) {
    final sortedProjects = [...projects]
      ..sort((a, b) {
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

    final groups = <_WorkspaceGroup>[];
    for (final project in sortedProjects) {
      final key = project.isGlobal ? project.worktree : project.worktree;
      groups.add(
        _WorkspaceGroup(
          project: project,
          sessions: buckets.remove(key) ?? const [],
        ),
      );
    }
    final remaining = buckets.values.expand((e) => e).toList();
    if (remaining.isNotEmpty) {
      groups.add(
        _WorkspaceGroup(
          project: Project(id: '__other__', worktree: '__other__'),
          sessions: remaining,
        ),
      );
    }
    return groups;
  }

  bool _projectMatchesQuery(Project project) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return true;
    if (project.isGlobal) return 'global'.contains(q);
    return compactPath(project.worktree).toLowerCase().contains(q);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Session> _filterSessions(List<Session> sessions) {
    final q = _query.toLowerCase();
    final active = ref.watch(sessionActivityProvider);
    return sessions.where((s) {
      final matchesQuery =
          q.isEmpty ||
          (s.title?.toLowerCase().contains(q) ?? false) ||
          (s.directory?.toLowerCase().contains(q) ?? false);
      final matchesFilter =
          _filter == 'all' ||
          (_filter == 'active' && active.contains(s.id)) ||
          (_filter == 'idle' && !active.contains(s.id));
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final sessionsAsync = ref.watch(allSessionsProvider);
    final projectsAsync = ref.watch(projectsProvider);

    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event != null && event.type == 'server.reconnected') {
        ref.read(sessionsRefreshProvider.notifier).state++;
      }
    });

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.menu),
              onPressed: () => context.push('/settings'),
            ),
          ],
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () {
                ref.read(projectsRefreshProvider.notifier).state++;
                ref.read(sessionsRefreshProvider.notifier).state++;
              },
            ),
          ],
        ),
      ],
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('opencode').h1,
                  const Gap(16),
                  TextField(
                    controller: _searchController,
                    placeholder: const Text('Search projects and sessions'),
                    features: const [
                      InputFeature.leading(Icon(LucideIcons.search, size: 16)),
                    ],
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const Gap(12),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 3,
                      separatorBuilder: (_, _) => const Gap(8),
                      itemBuilder: (context, index) {
                        final options = [
                          ('all', 'All'),
                          ('active', 'Active'),
                          ('idle', 'Idle'),
                        ];
                        final opt = options[index];
                        final selected = _filter == opt.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _filter = opt.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context).colorScheme.foreground
                                  : Theme.of(context).colorScheme.muted,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              opt.$2,
                              style: TextStyle(
                                color: selected
                                    ? Theme.of(context).colorScheme.background
                                    : Theme.of(context).colorScheme.foreground,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(16),
                  const Text('Projects').small.semiBold.muted,
                  const Gap(16),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: const SliverToBoxAdapter(child: PermissionBanner()),
          ),
          const SliverToBoxAdapter(child: Gap(12)),
          projectsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: _ErrorState(
                message: e is OpencodeApiException ? e.message : '$e',
                onRetry: () =>
                    ref.read(sessionsRefreshProvider.notifier).state++,
              ),
            ),
            data: (projects) {
              if (projects.isEmpty) {
                return const SliverToBoxAdapter(
                  child: _EmptyState(),
                );
              }
              return sessionsAsync.when(
                loading: () => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return _WorkspaceTile(
                        project: project,
                        sessions: const [],
                        onTap: () => _createSession(
                          context,
                          ref,
                          directory: project.isGlobal ? null : project.worktree,
                        ),
                      );
                    },
                  ),
                ),
                error: (_, _) => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return _WorkspaceTile(
                        project: project,
                        sessions: const [],
                        onTap: () => _createSession(
                          context,
                          ref,
                          directory: project.isGlobal ? null : project.worktree,
                        ),
                      );
                    },
                  ),
                ),
                data: (sessions) {
                  final filtered = _filterSessions(sessions);
                  final workspaces = _buildWorkspaces(filtered, projects);
                  final hasQuery = _query.trim().isNotEmpty || _filter != 'all';
                  final anyMatch = workspaces.any(
                    (w) =>
                        _projectMatchesQuery(w.project) ||
                        w.sessions.isNotEmpty,
                  );
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount:
                          workspaces.length + (hasQuery && !anyMatch ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < workspaces.length) {
                          final group = workspaces[index];
                          final visible =
                              _projectMatchesQuery(group.project) ||
                              group.sessions.isNotEmpty;
                          if (!visible) {
                            return const SizedBox.shrink();
                          }
                          final name = group.project.isGlobal
                              ? 'Global'
                              : (group.project.id == '__other__'
                                    ? 'Other'
                                    : compactPath(group.project.worktree));
                          final displaySessions = group.sessions;
                          return _WorkspaceTile(
                            key: ValueKey(group.project.worktree),
                            project: group.project,
                            titleOverride: name,
                            sessions: displaySessions,
                            initiallyExpanded: _expanded.contains(
                              group.project.worktree,
                            ),
                            onExpansionChanged: (v) {
                              setState(() {
                                final key = group.project.worktree;
                                if (v) {
                                  _expanded.add(key);
                                } else {
                                  _expanded.remove(key);
                                }
                              });
                            },
                            onTap: () => _createSession(context, ref),
                            onDeleteSession: (s) =>
                                _confirmDelete(context, ref, s),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.search,
                                  size: 40,
                                ).iconMutedForeground,
                                const Gap(12),
                                const Text('No matching results').h4,
                                const Gap(4),
                                const Text(
                                  'Try a different search or filter.',
                                ).muted,
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
          const SliverToBoxAdapter(child: Gap(80)),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  final Session session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = session.title?.trim().isNotEmpty == true
        ? session.title!
        : 'Untitled session';
    final busy = ref.watch(sessionActivityProvider).contains(session.id);
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.folder,
              size: 20,
              color: theme.colorScheme.foreground,
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  if (session.directory != null) ...[
                    const Gap(2),
                    Text(
                      compactPath(session.directory!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).muted.small,
                  ],
                ],
              ),
            ),
            const Gap(8),
            if (busy) const SecondaryBadge(child: Text('working')),
            Icon(
              LucideIcons.externalLink,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
            const Gap(8),
            GestureDetector(
              onTap: onDelete,
              child: Icon(
                LucideIcons.trash2,
                size: 16,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceGroup {
  const _WorkspaceGroup({required this.project, required this.sessions});

  final Project project;
  final List<Session> sessions;
}

class _WorkspaceTile extends StatefulWidget {
  const _WorkspaceTile({
    super.key,
    required this.project,
    required this.sessions,
    required this.onTap,
    this.onDeleteSession,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.titleOverride,
  });

  final Project project;
  final String? titleOverride;
  final List<Session> sessions;
  final VoidCallback onTap;
  final void Function(Session)? onDeleteSession;
  final bool initiallyExpanded;
  final void Function(bool)? onExpansionChanged;

  @override
  State<_WorkspaceTile> createState() => _WorkspaceTileState();
}

class _WorkspaceTileState extends State<_WorkspaceTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    if (widget.sessions.isEmpty) {
      widget.onTap();
      return;
    }
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.titleOverride ?? compactPath(widget.project.worktree);
    final count = widget.sessions.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.border,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded ? LucideIcons.folderOpen : LucideIcons.folderGit2,
                    size: 20,
                    color: theme.colorScheme.foreground,
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (count > 0) Text('$count').small.muted,
                  const Gap(8),
                  Icon(
                    _expanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 16,
                    color: theme.colorScheme.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.sessions.map(
              (session) => _SessionTile(
                session: session,
                onTap: () => context.push('/session/${session.id}'),
                onDelete: widget.onDeleteSession != null
                    ? () => widget.onDeleteSession!(session)
                    : () {},
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onCreate});

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.messagesSquare, size: 48).iconMutedForeground,
          const Gap(16),
          const Text('No workspaces yet').h4,
          const Gap(8),
          const Text(
            'Connect to a server to see its workspaces.',
          ).muted,
          if (onCreate != null) ...[
            const Gap(24),
            PrimaryButton(
              onPressed: onCreate,
              child: const Text('New session'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.triangleAlert, size: 48).iconMutedForeground,
          const Gap(16),
          const Text('Failed to load sessions').h4,
          const Gap(8),
          Text(message).muted.textCenter,
          const Gap(24),
          PrimaryButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
