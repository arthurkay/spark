import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/path_utils.dart';

final _sessionDirectoryProvider = FutureProvider.family<String?, String>((
  ref,
  sessionId,
) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return null;
  final session = await client.getSession(sessionId);
  return session?.directory;
});

final _filesProvider = FutureProvider.family<List<FileNode>, _FileQuery>((
  ref,
  query,
) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  final nodes = await client.listFiles(query.path, directory: query.directory);
  nodes.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return nodes;
});

class _FileQuery {
  const _FileQuery(this.path, this.directory);

  final String path;
  final String? directory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FileQuery && other.path == path && other.directory == directory;

  @override
  int get hashCode => Object.hash(path, directory);
}

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, this.sessionId, this.directory})
      : assert(sessionId != null || directory != null,
            'Either sessionId or directory must be provided');

  final String? sessionId;
  final String? directory;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _path = '';

  String? get _directory => widget.directory;

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;

    if (sessionId != null) {
      final directoryAsync = ref.watch(_sessionDirectoryProvider(sessionId));
      return directoryAsync.when(
        loading: () => const Scaffold(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          child: Center(
            child: Text(e is OpencodeApiException ? e.message : '$e').muted,
          ),
        ),
        data: (_) => _buildBody(ref, directoryAsync.value),
      );
    }

    return _buildBody(ref, _directory);
  }

  Widget _buildBody(WidgetRef ref, String? directory) {
    final filesAsync = ref.watch(
      _filesProvider(_FileQuery(_path, directory)),
    );

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Files'),
          subtitle: directory != null && directory.isNotEmpty
              ? Text(compactPath(directory)).muted.small
              : const Text('Project root').muted.small,
        ),
      ],
      child: filesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e is OpencodeApiException ? e.message : '$e').muted,
        ),
        data: (nodes) {
          if (nodes.isEmpty) {
            return Center(child: const Text('Empty directory').muted);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (_path.isNotEmpty)
                GhostButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () => setState(() {
                    final parts = _path.split('/')..removeLast();
                    _path = parts.join('/');
                  }),
                  child: const Row(
                    children: [
                      Icon(LucideIcons.cornerLeftUp),
                      Gap(8),
                      Text('..'),
                    ],
                  ),
                ),
              for (final node in nodes)
                GhostButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    if (node.isDirectory) {
                      setState(() => _path = node.path);
                    } else {
                      _openFile(context, node, directory);
                    }
                  },
                  child: Row(
                    children: [
                      Icon(
                        node.isDirectory
                            ? LucideIcons.folder
                            : LucideIcons.file,
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openFile(BuildContext context, FileNode node, String? directory) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      builder: (context) =>
          _FileViewer(path: node.path, name: node.name, directory: directory),
    );
  }
}

class _FileViewer extends ConsumerWidget {
  const _FileViewer({required this.path, required this.name, this.directory});

  final String path;
  final String name;
  final String? directory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(opencodeClientProvider);
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).h4,
                ),
                IconButton.ghost(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => closeSheet(context),
                ),
              ],
            ),
            const Gap(12),
            Flexible(
              child: FutureBuilder(
                future: client?.readFile(path, directory: directory),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('${snapshot.error}').muted;
                  }
                  final content = snapshot.data?.content ?? '';
                  final isBinary = snapshot.data?.isBinary ?? false;
                  if (isBinary) {
                    return Center(child: const Text('Binary file').muted);
                  }
                  return CodeHighlightView(
                    code: content,
                    path: path,
                    lineNumbers: true,
                    constraints: const BoxConstraints(maxHeight: 460),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
