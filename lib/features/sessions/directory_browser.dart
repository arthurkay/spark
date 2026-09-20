import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/path_utils.dart';
import 'sessions_provider.dart';
import 'workspace_provider.dart';

final _dirsProvider = FutureProvider.family<List<FileNode>, _DirQuery>((
  ref,
  query,
) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  try {
    final nodes = await client.listFiles('', directory: query.dir);
    return nodes.where((n) => n.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } catch (_) {
    return [];
  }
});

class _DirQuery {
  const _DirQuery(this.dir);
  final String dir;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _DirQuery && other.dir == dir;

  @override
  int get hashCode => dir.hashCode;
}

class DirectoryBrowserScreen extends ConsumerStatefulWidget {
  const DirectoryBrowserScreen({super.key, this.directory});

  final String? directory;

  @override
  ConsumerState<DirectoryBrowserScreen> createState() =>
      _DirectoryBrowserScreenState();
}

class _DirectoryBrowserScreenState
    extends ConsumerState<DirectoryBrowserScreen> {
  late String _currentDir;
  final _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentDir = widget.directory ?? '/';
    _pathController.text = _currentDir;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  String get _parentDir {
    final trimmed = _currentDir.endsWith('/')
        ? _currentDir.substring(0, _currentDir.length - 1)
        : _currentDir;
    final parts = trimmed.split('/');
    if (parts.length <= 1) return '/';
    parts.removeLast();
    final result = parts.join('/');
    return result.isEmpty ? '/' : result;
  }

  String get _currentDirName =>
      _currentDir.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '/';

  void _navigateInto(String dirName) {
    Haptics.selection();
    final base = _currentDir.endsWith('/') ? _currentDir : '$_currentDir/';
    setState(() {
      _currentDir = '$base$dirName';
      _pathController.text = _currentDir;
    });
  }

  void _navigateUp() {
    Haptics.selection();
    setState(() {
      _currentDir = _parentDir;
      _pathController.text = _currentDir;
    });
  }

  void _applyTypedPath() {
    final typed = _pathController.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _currentDir = typed;
    });
  }

  Future<void> _startSession() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    try {
      final session = await client.createSession(directory: _currentDir);
      ref.read(sessionsRefreshProvider.notifier).state++;
      if (!mounted) return;
      context.go('/session/${session.id}');
    } on OpencodeApiException catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Failed to create session',
        description: e.message,
      );
    }
  }

  Widget _buildPathBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: TextField(
        controller: _pathController,
        placeholder: const Text('/path/to/directory'),
        features: const [
          InputFeature.leading(Icon(LucideIcons.folderOpen, size: 16)),
        ],
        onSubmitted: (_) => _applyTypedPath(),
        onChanged: (_) {},
      ),
    );
  }

  Widget _buildProjectChips() {
    final theme = Theme.of(context);
    final projectsAsync = ref.watch(projectsProvider);
    return projectsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (projects) {
        final projectDirs = projects.where((p) => !p.isGlobal).toList();
        if (projectDirs.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: projectDirs.length,
            separatorBuilder: (_, __) => const Gap(8),
            itemBuilder: (context, index) {
              final project = projectDirs[index];
              final name =
                  project.worktree
                      .split('/')
                      .where((s) => s.isNotEmpty)
                      .lastOrNull ??
                  project.worktree;
              final isActive = _currentDir == project.worktree;
              return GestureDetector(
                onTap: () {
                  Haptics.selection();
                  setState(() {
                    _currentDir = project.worktree;
                    _pathController.text = _currentDir;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary.withAlpha(30)
                        : theme.colorScheme.muted.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive
                          ? theme.colorScheme.primary.withAlpha(60)
                          : theme.colorScheme.border,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.folderGit2,
                        size: 12,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.mutedForeground,
                      ),
                      const Gap(4),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirsAsync = ref.watch(_dirsProvider(_DirQuery(_currentDir)));
    final canGoUp = _currentDir != '/';

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () {
                if (canGoUp) {
                  _navigateUp();
                } else {
                  context.pop();
                }
              },
            ),
          ],
          title: Text(_currentDirName),
        ),
      ],
      child: Column(
        children: [
          _buildPathBar(),
          _buildProjectChips(),
          const Gap(8),
          Expanded(
            child: dirsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(e is OpencodeApiException ? e.message : '$e').muted,
              ),
              data: (dirs) {
                if (dirs.isEmpty && !canGoUp) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.folderOpen,
                          size: 40,
                          color: theme.colorScheme.mutedForeground,
                        ),
                        const Gap(12),
                        const Text('Empty directory').h4,
                        const Gap(4),
                        const Text(
                          'Type a path above or pick a project.',
                        ).muted,
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: dirs.length + (canGoUp ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 44),
                  itemBuilder: (context, index) {
                    if (canGoUp && index == 0) {
                      return GhostButton(
                        alignment: Alignment.centerLeft,
                        onPressed: _navigateUp,
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.cornerLeftUp,
                              size: 20,
                              color: theme.colorScheme.mutedForeground,
                            ),
                            const Gap(12),
                            Text(
                              '..',
                              style: TextStyle(
                                fontSize: 15,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final node = dirs[canGoUp ? index - 1 : index];
                    return GhostButton(
                      alignment: Alignment.centerLeft,
                      onPressed: () => _navigateInto(node.name),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.folder,
                            size: 20,
                            color: theme.colorScheme.mutedForeground,
                          ),
                          const Gap(12),
                          Expanded(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.background,
              border: Border(
                top: BorderSide(color: theme.colorScheme.border, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    compactPath(_currentDir),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Gap(8),
                  PrimaryButton(
                    onPressed: _startSession,
                    child: const Text('Start session here'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
