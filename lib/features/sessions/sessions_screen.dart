import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/project.dart';
import '../../core/models/server_config.dart';
import '../../core/models/session.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/path_utils.dart';
import '../../shared/widgets/shimmer_loading.dart';

import '../connection/connection_screen.dart';

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

  final _scrollController = ScrollController();
  final _titleKey = GlobalKey();
  final _titleProgress = ValueNotifier<double>(0.0);

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

  void _showProjectMenu(BuildContext context, WidgetRef ref, Project project) {
    if (project.isGlobal) return;
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
              const Text('Project actions').h4,
              const Gap(16),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  _renameProject(context, ref, project);
                },
                child: const Text('Rename'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  context.push(
                    '/workspace/${Uri.encodeComponent(project.worktree)}/files',
                  );
                },
                child: const Text('Open files'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameProject(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    final controller =
        TextEditingController(text: project.worktree.split('/').last);
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Rename project').h4,
                const Gap(12),
                TextField(
                  controller: controller,
                  placeholder: const Text('Project name'),
                ),
                const Gap(16),
                PrimaryButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    closeSheet(sheetContext);
                    try {
                      await ref
                          .read(opencodeClientProvider)!
                          .updateProject(project.id, name: name);
                      ref.read(projectsRefreshProvider.notifier).state++;
                    } on OpencodeApiException catch (e) {
                      if (!context.mounted) return;
                      showAppToast(context,
                          title: 'Failed to rename', description: e.message);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_WorkspaceGroup> _buildWorkspaces(
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
  void initState() {
    super.initState();
    _scrollController.addListener(_checkTitleVisibility);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_checkTitleVisibility);
    _scrollController.dispose();
    _titleProgress.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkTitleVisibility() {
    final key = _titleKey;
    final ctx = key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final titleTop = pos.dy;
    final titleHeight = box.size.height;
    double progress;
    if (titleTop >= 0) {
      progress = 0.0;
    } else if (titleTop <= -titleHeight) {
      progress = 1.0;
    } else {
      progress = (-titleTop) / titleHeight;
    }
    progress = progress.clamp(0.0, 1.0);
    _titleProgress.value = progress;
  }

  List<Session> _filterSessions(List<Session> sessions) {
    final q = _query.toLowerCase();
    final active = ref.watch(sessionActivityProvider);
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

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final sessionsAsync = ref.watch(allSessionsProvider);
    final projectsAsync = ref.watch(projectsProvider);
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      if (event.type == 'server.reconnected') {
        ref.read(sessionsRefreshProvider.notifier).state++;
        ref.read(vcsRefreshProvider.notifier).state++;
      } else if (event.type == 'vcs.branch.updated') {
        ref.read(vcsRefreshProvider.notifier).state++;
      }
    });

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.zap),
              onPressed: () => context.push('/settings'),
            ),
          ],
          title: ValueListenableBuilder<double>(
            valueListenable: _titleProgress,
            builder: (context, progress, child) {
              return Opacity(
                opacity: progress,
                child: child,
              );
            },
            child: const Text('SparkCode'),
          ),
          alignment: Alignment.centerLeft,
          trailing: [],
        ),
      ],
      child: RefreshTrigger(
        onRefresh: () async {
          ref.read(projectsRefreshProvider.notifier).state++;
          ref.read(sessionsRefreshProvider.notifier).state++;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _titleProgress,
                      builder: (context, progress, child) {
                        return Opacity(
                          opacity: 1.0 - progress,
                          child: child,
                        );
                      },
                      child: Text('SparkCode', key: _titleKey).h1,
                    ),
                    const Gap(12),
                    _ServerSwitcher(),
                    const Gap(16),
                    TextField(
                      controller: _searchController,
                      placeholder: const Text('Search projects and sessions'),
                      border: Border.all(color: Colors.transparent),
                      features: const [
                        InputFeature.leading(
                            Icon(LucideIcons.search, size: 16)),
                      ],
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                    ),
                    const Gap(12),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 3,
                        separatorBuilder: (_, __) => const Gap(8),
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
                                      : Theme.of(context)
                                          .colorScheme
                                          .foreground,
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
                    Row(
                      children: [
                        const Text('Projects').small.semiBold.muted,
                        const Spacer(),
                      ],
                    ),
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
              loading: () => SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  itemCount: 3,
                  itemBuilder: (context, index) {
                    return ShimmerLoading(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const SkeletonBox(width: 20, height: 20),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SkeletonBox(
                                    width: 120 + (index * 40).toDouble(),
                                    height: 14,
                                  ),
                                  const Gap(6),
                                  SkeletonBox(
                                    width: 80 + (index * 20).toDouble(),
                                    height: 10,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
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
                          onCreateSession: (ctx) => _createSession(
                            ctx,
                            ref,
                            directory:
                                project.isGlobal ? null : project.worktree,
                          ),
                          onShowProjectMenu: (ctx) =>
                              _showProjectMenu(ctx, ref, project),
                        );
                      },
                    ),
                  ),
                  error: (_, __) => SliverPadding(
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
                            directory:
                                project.isGlobal ? null : project.worktree,
                          ),
                          onShowProjectMenu: (ctx) =>
                              _showProjectMenu(ctx, ref, project),
                        );
                      },
                    ),
                  ),
                  data: (sessions) {
                    final filtered = _filterSessions(sessions);
                    final workspaces = _buildWorkspaces(filtered, projects);
                    final hasQuery =
                        _query.trim().isNotEmpty || _filter != 'all';
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
                              onCreateSession: (ctx) => _createSession(
                                ctx,
                                ref,
                                directory: group.project.isGlobal
                                    ? null
                                    : group.project.worktree,
                              ),
                              onDeleteSession: (s) =>
                                  _confirmDelete(context, ref, s),
                              onShowProjectMenu: (ctx) =>
                                  _showProjectMenu(ctx, ref, group.project),
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

  void _showSessionMenu(BuildContext context, WidgetRef ref) {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
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
              const Text('Session actions').h4,
              const Gap(16),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  _renameSession(context, ref);
                },
                child: const Text('Rename'),
              ),
              const Gap(8),
              DestructiveButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  onDelete();
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameSession(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: session.title ?? '');
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Rename session').h4,
                const Gap(12),
                TextField(
                  controller: controller,
                  placeholder: const Text('Session title'),
                ),
                const Gap(16),
                PrimaryButton(
                  onPressed: () async {
                    final title = controller.text.trim();
                    if (title.isEmpty) return;
                    closeSheet(sheetContext);
                    try {
                      await ref
                          .read(opencodeClientProvider)!
                          .renameSession(session.id, title);
                      ref.read(sessionsRefreshProvider.notifier).state++;
                    } on OpencodeApiException catch (e) {
                      if (!context.mounted) return;
                      showAppToast(context,
                          title: 'Failed to rename', description: e.message);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
            GestureDetector(
              onTap: () => _showSessionMenu(context, ref),
              child: Icon(
                LucideIcons.ellipsisVertical,
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

class _WorkspaceTile extends ConsumerStatefulWidget {
  const _WorkspaceTile({
    super.key,
    required this.project,
    required this.sessions,
    required void Function(BuildContext context) onCreateSession,
    this.onDeleteSession,
    this.onShowProjectMenu,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.titleOverride,
  }) : _onCreateSession = onCreateSession;

  final Project project;
  final String? titleOverride;
  final List<Session> sessions;
  final void Function(BuildContext context) _onCreateSession;
  final void Function(Session)? onDeleteSession;
  final void Function(BuildContext context)? onShowProjectMenu;
  final bool initiallyExpanded;
  final void Function(bool)? onExpansionChanged;

  @override
  ConsumerState<_WorkspaceTile> createState() => _WorkspaceTileState();
}

class _WorkspaceTileState extends ConsumerState<_WorkspaceTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    if (widget.sessions.isEmpty) {
      _openWorkspaceFiles();
      return;
    }
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  void _openWorkspaceFiles() {
    final worktree = widget.project.worktree;
    if (worktree.isEmpty) return;
    context.push('/workspace/${Uri.encodeComponent(worktree)}/files');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.titleOverride ?? compactPath(widget.project.worktree);
    final count = widget.sessions.length;
    final vcs = ref.watch(vcsProvider);
    final branch = vcs.value?.branch;
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
                    child: Row(
                      children: [
                        Flexible(
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
                        if (branch != null && branch.isNotEmpty) ...[
                          const Gap(6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.muted,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              branch,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (count > 0) Text('$count').small.muted,
                  const Gap(8),
                  if (_expanded || count == 0)
                    GestureDetector(
                      onTap: () => widget._onCreateSession(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.muted,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          LucideIcons.plus,
                          size: 14,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  const Gap(8),
                  if (!widget.project.isGlobal)
                    GestureDetector(
                      onTap: () => widget.onShowProjectMenu?.call(context),
                      child: Icon(
                        LucideIcons.ellipsisVertical,
                        size: 16,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
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
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: Column(
                children: widget.sessions
                    .map(
                      (session) => _SessionTile(
                        session: session,
                        onTap: () => context.push('/session/${session.id}'),
                        onDelete: widget.onDeleteSession != null
                            ? () => widget.onDeleteSession!(session)
                            : () {},
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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

class _ServerSwitcher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managerState = ref.watch(serverManagerProvider);
    final configs = managerState.configs;
    final active = managerState.activeConfig;

    if (configs.isEmpty) {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConnectionScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.muted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.plus, size: 14),
              const Gap(6),
              const Text('Add server').small,
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showServerPicker(context, ref, configs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.server, size: 14),
            const Gap(6),
            Text(
              active?.name ?? 'No server',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small,
            const Gap(4),
            const Icon(LucideIcons.chevronDown, size: 12).iconMutedForeground,
          ],
        ),
      ),
    );
  }

  void _showServerPicker(
    BuildContext context,
    WidgetRef ref,
    List<ServerConfig> configs,
  ) {
    final managerState = ref.read(serverManagerProvider);
    final activeId = managerState.activeId;
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
              const Text('Switch server').h4,
              const Gap(12),
              for (final config in configs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GhostButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () {
                      closeSheet(sheetContext);
                      ref
                          .read(serverManagerProvider.notifier)
                          .setActive(config.id);
                      ref.read(sessionsRefreshProvider.notifier).state++;
                      ref.read(projectsRefreshProvider.notifier).state++;
                    },
                    child: Row(
                      children: [
                        Icon(
                          config.id == activeId
                              ? LucideIcons.circleCheck
                              : LucideIcons.circle,
                          size: 16,
                          color: config.id == activeId
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        const Gap(10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(config.name).small,
                              Text(config.connection.baseUrl).xSmall.muted,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Gap(8),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConnectionScreen(),
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.plus, size: 16),
                    Gap(10),
                    Text('Add server'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
