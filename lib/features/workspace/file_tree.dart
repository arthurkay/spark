import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/file_type_utils.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/shimmer_loading.dart';
import 'workspace_providers.dart';

class FileTree extends ConsumerStatefulWidget {
  const FileTree({
    super.key,
    required this.directory,
    required this.activePath,
    required this.onOpenFile,
  });

  final String? directory;
  final String? activePath;
  final ValueChanged<FileNode> onOpenFile;

  @override
  ConsumerState<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends ConsumerState<FileTree> {
  final _searchController = TextEditingController();
  String _query = '';
  List<FileNode>? _searchFiles;
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    Future(() {
      if (!mounted) return;
      if (!ref.read(workspaceProvider).expandedDirs.contains('')) {
        ref.read(workspaceProvider.notifier).toggleDir('');
      }
    });
  }

  @override
  void didUpdateWidget(FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      _searchFiles = null;
      if (_query.isNotEmpty) _loadSearchFiles();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    if (value.isNotEmpty && _searchFiles == null && !_searchLoading) {
      _loadSearchFiles();
    }
  }

  Future<void> _loadSearchFiles() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    setState(() => _searchLoading = true);
    try {
      final files = await collectFiles(
        client,
        directory: widget.directory,
        path: '',
      );
      if (!mounted) return;
      setState(() {
        _searchFiles = files;
        _searchLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(workspaceProvider.select((s) => s.expandedDirs));
    final activePath = widget.activePath;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.card,
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                const Icon(LucideIcons.folderTree, size: 14),
                const Gap(8),
                Expanded(
                  child: Text(
                    widget.directory == null || widget.directory!.isEmpty
                        ? 'Project'
                        : widget.directory!.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small.semiBold.muted,
                ),
              ],
            ),
          ),
          const Divider(indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: TextField(
              controller: _searchController,
              placeholder: const Text('Search files'),
              features: const [
                InputFeature.leading(Icon(LucideIcons.search, size: 14)),
              ],
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(child: _buildBody(expanded, activePath)),
        ],
      ),
    );
  }

  Widget _buildBody(Set<String> expanded, String? activePath) {
    if (_query.isNotEmpty) return _buildSearchResults(activePath);
    return SingleChildScrollView(
      child: _TreeLevel(
        path: '',
        depth: 0,
        expanded: expanded,
        activePath: activePath,
        directory: widget.directory,
        onOpenFile: widget.onOpenFile,
      ),
    );
  }

  Widget _buildSearchResults(String? activePath) {
    if (_searchLoading || _searchFiles == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: ShimmerLoading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: 140, height: 12),
              Gap(8),
              SkeletonBox(width: 116, height: 12),
              Gap(8),
              SkeletonBox(width: 92, height: 12),
            ],
          ),
        ),
      );
    }
    final results = rankFiles(_query, _searchFiles!);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: const Text('No matches').muted.xSmall,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final node = results[index];
        return _FileRow(
          node: node,
          depth: 0,
          active: node.path == activePath,
          onTap: () {
            Haptics.selection();
            widget.onOpenFile(node);
          },
        );
      },
    );
  }
}

class _TreeLevel extends ConsumerWidget {
  const _TreeLevel({
    required this.path,
    required this.depth,
    required this.expanded,
    required this.activePath,
    required this.directory,
    required this.onOpenFile,
  });

  final String path;
  final int depth;
  final Set<String> expanded;
  final String? activePath;
  final String? directory;
  final ValueChanged<FileNode> onOpenFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(
      fileListProvider(FileListQuery(path, directory)),
    );

    return nodesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.fromLTRB(12 + depth * 14.0, 8, 12, 8),
        child: ShimmerLoading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const Gap(8),
                SkeletonBox(width: 140.0 - i * 24.0, height: 12),
              ],
            ],
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.fromLTRB(12 + depth * 14.0, 8, 12, 8),
        child: Text('$e').muted.xSmall,
      ),
      data: (nodes) {
        if (nodes.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(12 + depth * 14.0, 8, 12, 8),
            child: const Text('Empty').muted.xSmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final node in nodes)
              node.isDirectory
                  ? _DirRow(
                      node: node,
                      depth: depth,
                      expanded: expanded.contains(node.path),
                      children: expanded.contains(node.path)
                          ? _TreeLevel(
                              path: node.path,
                              depth: depth + 1,
                              expanded: expanded,
                              activePath: activePath,
                              directory: directory,
                              onOpenFile: onOpenFile,
                            )
                          : null,
                    )
                  : _FileRow(
                      node: node,
                      depth: depth,
                      active: node.path == activePath,
                      onTap: () {
                        Haptics.selection();
                        onOpenFile(node);
                      },
                    ),
          ],
        );
      },
    );
  }
}

class _DirRow extends ConsumerWidget {
  const _DirRow({
    required this.node,
    required this.depth,
    required this.expanded,
    this.children,
  });

  final FileNode node;
  final int depth;
  final bool expanded;
  final Widget? children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhostButton(
          alignment: Alignment.centerLeft,
          onPressed: () {
            Haptics.selection();
            ref.read(workspaceProvider.notifier).toggleDir(node.path);
          },
          child: Padding(
            padding: EdgeInsets.only(left: 8 + depth * 14.0),
            child: Row(
              children: [
                Icon(
                  expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14,
                ),
                const Gap(6),
                Icon(
                  expanded ? LucideIcons.folderOpen : LucideIcons.folder,
                  size: 14,
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small,
                ),
              ],
            ),
          ),
        ),
        if (expanded && children != null) children!,
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.node,
    required this.depth,
    required this.active,
    required this.onTap,
  });

  final FileNode node;
  final int depth;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = extensionFromPath(node.path);
    final icon = switch (ext) {
      'dart' || 'json' => LucideIcons.braces,
      'md' || 'markdown' => LucideIcons.text,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => LucideIcons.image,
      'yml' || 'yaml' || 'toml' || 'ini' => LucideIcons.settings2,
      'sh' || 'bash' || 'zsh' => LucideIcons.terminal,
      _ => LucideIcons.file,
    };
    final color = active ? scheme.primary : scheme.foreground;

    return GhostButton(
      alignment: Alignment.centerLeft,
      onPressed: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 8 + depth * 14.0, top: 2, bottom: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const SizedBox(width: 20),
              Icon(icon, size: 14, color: color),
              const Gap(8),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : null,
                  ),
                ).small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
