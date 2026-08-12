import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../shared/haptics.dart';
import '../../shared/file_type_utils.dart';
import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/data_uri_cache.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/path_utils.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';
import '../chat/chat_provider.dart';
import '../sessions/sessions_provider.dart';
import '../sessions/workspace_provider.dart';
import 'file_write_service.dart';
import 'file_ops_service.dart';

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

  /// Last segment of the browsed location, for display in the confirm sheet.
  String get _browseDirectoryLabel {
    final source = _path.isNotEmpty ? _path : (_directory ?? '');
    if (source.isEmpty) return 'this directory';
    return source.split('/').last;
  }

  /// Resolves the absolute directory currently being browsed. The server's
  /// file listing returns paths relative to the base directory, so `_path`
  /// must be joined with the base — a bare relative path is meaningless to
  /// the server as a `directory` argument. In session mode the base comes
  /// from the session's directory.
  Future<String> _resolveBrowseDirectory() async {
    var base = _directory ?? '';
    if (base.isEmpty && widget.sessionId != null) {
      final sessionDir =
          await ref.read(sessionDirectoryProvider(widget.sessionId!).future);
      base = sessionDir ?? '';
    }
    if (_path.isEmpty) return base;
    if (_path.startsWith('/') || base.isEmpty) return _path;
    return '$base/$_path';
  }

  Future<void> _createProject() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) return;
    final dir = await _resolveBrowseDirectory();
    if (dir.isEmpty) return;
    try {
      await client.initGitProject(directory: dir);
      ref.read(projectsRefreshProvider.notifier).state++;
      final newSession = await client.createSession(directory: dir);
      ref.read(sessionsRefreshProvider.notifier).state++;
      if (!mounted) return;
      context.push('/session/${newSession.id}');
    } on OpencodeApiException catch (e) {
      if (!mounted) return;
      showAppToast(context,
          title: 'Failed to create project', description: e.message);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context,
          title: 'Failed to create project', description: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;

    if (sessionId != null) {
      final directoryAsync = ref.watch(sessionDirectoryProvider(sessionId));
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
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => _showNewItemMenu(context, ref, directory),
            ),
          ],
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
          // ListView.builder, not ListView(children:): a directory with a few
          // thousand entries used to build every row up front, on every
          // navigation.
          final hasUp = _path.isNotEmpty;
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: nodes.length + (hasUp ? 1 : 0),
            itemBuilder: (context, index) {
              if (hasUp && index == 0) {
                return GhostButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    Haptics.selection();
                    setState(() {
                      final parts = _path.split('/')..removeLast();
                      _path = parts.join('/');
                    });
                  },
                  child: const Row(
                    children: [
                      Icon(LucideIcons.cornerLeftUp),
                      Gap(8),
                      Text('..'),
                    ],
                  ),
                );
              }
              final node = nodes[hasUp ? index - 1 : index];
              final ext =
                  node.isDirectory ? null : extensionFromPath(node.path);
              final isImage =
                  ext != null && isSupportedImageExtension(node.path);
              return GestureDetector(
                onLongPress: () {
                  Haptics.longPress();
                  _showFileActions(context, ref, node, directory);
                },
                child: GhostButton(
                  alignment: Alignment.centerLeft,
                  onPressed: () {
                    Haptics.selection();
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
                            : isImage
                                ? LucideIcons.image
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
                      if (!node.isDirectory && ext != null) ...[
                        const Gap(8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .muted
                                .withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('.$ext').xSmall.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// One "+" for the three things you can create here.
  ///
  /// These used to be two app-bar icons, one of which was a `folderPlus` that
  /// created a *git project* rather than a directory — leaving no way at all to
  /// make a folder. Labelled rows say what each one does and leave room for the
  /// third action on a phone-width bar.
  void _showNewItemMenu(
      BuildContext context, WidgetRef ref, String? directory) {
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
              const Text('Create').h4,
              const Gap(4),
              Text(_path.isEmpty ? 'In project root' : 'In $_path').muted.small,
              const Gap(12),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _showCreateDialog(context, ref, directory,
                      isDirectory: false);
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.filePlus, size: 16),
                    Gap(10),
                    Text('New file'),
                  ],
                ),
              ),
              const Gap(8),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _showCreateDialog(context, ref, directory, isDirectory: true);
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.folderPlus, size: 16),
                    Gap(10),
                    Text('New folder'),
                  ],
                ),
              ),
              const Gap(8),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _showCreateProjectSheet(context);
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.folderGit2, size: 16),
                    Gap(10),
                    Text('New project'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateProjectSheet(BuildContext context) {
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
                  const Icon(LucideIcons.folderGit2),
                  const Gap(8),
                  const Text('New project').h4,
                ],
              ),
              const Gap(12),
              Text(
                'Initialize git in $_browseDirectoryLabel and create a new session?',
              ).muted,
              const Gap(20),
              PrimaryButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  _createProject();
                },
                child: const Text('Create'),
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

  void _showFileActions(
      BuildContext context, WidgetRef ref, FileNode node, String? directory) {
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
              Text(node.name).h4,
              const Gap(12),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _renameItem(context, ref, node, directory);
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.pencil, size: 16),
                    Gap(10),
                    Text('Rename'),
                  ],
                ),
              ),
              const Gap(8),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _deleteItem(context, ref, node, directory);
                },
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2,
                        size: 16,
                        color: Theme.of(context).colorScheme.destructive),
                    const Gap(10),
                    Text('Delete',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.destructive)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameItem(BuildContext context, WidgetRef ref, FileNode node,
      String? directory) async {
    final controller = TextEditingController(text: node.name);
    String? result;
    // Awaited: openSheetOverlay returns as soon as the sheet is *shown*, so
    // reading `result` without waiting for it to close always saw null and
    // abandoned the rename.
    await openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SheetKeyboardPadding(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Rename').h4,
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: const Text('New name'),
                  onSubmitted: (_) {
                    result = controller.text.trim();
                    closeSheet(sheetContext);
                  },
                ),
                const Gap(16),
                PrimaryButton(
                  onPressed: () {
                    result = controller.text.trim();
                    closeSheet(sheetContext);
                  },
                  child: const Text('Rename'),
                ),
              ],
            ),
          ),
        ),
      ),
    ).future;
    if (result == null || !context.mounted) return;

    final newName = result!;
    if (newName.isEmpty || newName == node.name) return;

    final client = ref.read(opencodeClientProvider);
    if (client == null) return;

    final dir = directory ?? _resolveCurrentDirectory(node);
    // A file at the project root has no '/' in its path — substring(0, -1)
    // used to throw instead of renaming it.
    final slash = node.path.lastIndexOf('/');
    final newPath =
        slash < 0 ? newName : '${node.path.substring(0, slash)}/$newName';

    final service = FileOpsService(client: client);
    final opResult = await service.rename(node.path, newPath, directory: dir);
    if (!context.mounted) return;

    if (opResult.success) {
      ref.invalidate(_filesProvider);
      showAppToast(context, title: 'Renamed to $newName');
    } else {
      showAppToast(context,
          title: 'Failed to rename', description: opResult.error);
    }
  }

  Future<void> _deleteItem(BuildContext context, WidgetRef ref, FileNode node,
      String? directory) async {
    bool confirmed = false;
    await openSheetOverlay(
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
              const Text('Delete').h4,
              const Gap(12),
              Text('Delete "${node.name}"?').muted,
              const Gap(16),
              DestructiveButton(
                onPressed: () {
                  confirmed = true;
                  closeSheet(sheetContext);
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
    ).future;
    if (!confirmed || !context.mounted) return;

    final client = ref.read(opencodeClientProvider);
    if (client == null) return;

    final dir = directory ?? _resolveCurrentDirectory(node);
    final service = FileOpsService(client: client);
    final result = node.isDirectory
        ? await service.deleteDirectory(node.path, directory: dir)
        : await service.deleteFile(node.path, directory: dir);
    if (!context.mounted) return;

    if (result.success) {
      ref.invalidate(_filesProvider);
      showAppToast(context, title: 'Deleted ${node.name}');
    } else {
      showAppToast(context,
          title: 'Failed to delete', description: result.error);
    }
  }

  String _resolveCurrentDirectory(FileNode node) {
    final parts = node.path.split('/');
    parts.removeLast();
    return parts.join('/');
  }

  Future<void> _showCreateDialog(
      BuildContext context, WidgetRef ref, String? directory,
      {required bool isDirectory}) async {
    final controller = TextEditingController();
    String? nameResult;
    await openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) => SheetKeyboardPadding(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isDirectory ? 'New Folder' : 'New File').h4,
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  placeholder: Text(isDirectory ? 'Folder name' : 'File name'),
                  onSubmitted: (_) {
                    nameResult = controller.text.trim();
                    closeSheet(sheetContext);
                  },
                ),
                const Gap(16),
                PrimaryButton(
                  onPressed: () {
                    nameResult = controller.text.trim();
                    closeSheet(sheetContext);
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    ).future;
    if (nameResult == null || !context.mounted) return;

    final name = nameResult!;
    if (name.isEmpty) return;

    final client = ref.read(opencodeClientProvider);
    if (client == null) return;

    final basePath = _path.isEmpty ? '' : '$_path/';
    final newPath = '$basePath$name';

    final service = FileOpsService(client: client);
    final opResult = isDirectory
        ? await service.createDirectory(newPath, directory: directory)
        : await service.createFile(newPath, directory: directory);
    if (!context.mounted) return;

    if (opResult.success) {
      ref.invalidate(_filesProvider);
      showAppToast(context, title: 'Created $name');
    } else {
      showAppToast(context,
          title: 'Failed to create', description: opResult.error);
    }
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

class _FileViewer extends ConsumerStatefulWidget {
  const _FileViewer({required this.path, required this.name, this.directory});

  final String path;
  final String name;
  final String? directory;

  @override
  ConsumerState<_FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends ConsumerState<_FileViewer> {
  late Future<FileContent> _contentFuture;
  TextEditingController? _editController;
  bool _editing = false;
  bool _saving = false;
  PtyFileWriter? _writer;

  @override
  void initState() {
    super.initState();
    _contentFuture = _fetch();
  }

  Future<FileContent> _fetch() {
    final client = ref.read(opencodeClientProvider);
    if (client == null) {
      return Future.error(OpencodeApiException('Not connected'));
    }
    return client.readFile(widget.path, directory: widget.directory);
  }

  void _startEdit(String content) {
    setState(() {
      _editController = TextEditingController(text: content);
      _editing = true;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _save() async {
    final client = ref.read(opencodeClientProvider);
    final controller = _editController;
    if (client == null || controller == null) return;
    setState(() => _saving = true);
    final writer = PtyFileWriter(client: client);
    _writer = writer;
    try {
      await writer.write(
        path: widget.path,
        directory: widget.directory,
        content: controller.text,
      );
      if (!mounted) return;
      showAppToast(context, title: 'File saved');
      setState(() {
        _editing = false;
        _contentFuture = _fetch();
        _editController?.dispose();
        _editController = null;
      });
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Failed to save file',
        description: switch (e) {
          OpencodeApiException(:final message) => message,
          FileWriteException(:final message) => message,
          _ => '$e',
        },
      );
    } finally {
      _writer = null;
      // Always clear the spinner here: any future that resolves — or throws —
      // must leave the button usable again.
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _writer?.cancel();
    _editController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<FileContent>(
          future: _contentFuture,
          builder: (context, snapshot) {
            final loaded = snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError;
            final fileContent = snapshot.data;
            final content = fileContent?.content ?? '';
            final isBinary = fileContent?.isBinary ?? false;
            final mimeType = fileContent?.mimeType;
            final isBase64 = fileContent?.isBase64Encoded ?? false;
            final isImage = isBinary && isImageMime(mimeType) && isBase64;
            final canEdit = loaded && !isBinary && !isImage;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ).h4,
                    ),
                    if (_editing) ...[
                      OutlineButton(
                        size: ButtonSize.small,
                        density: ButtonDensity.compact,
                        onPressed: _saving ? null : _cancelEdit,
                        child: const Text('Cancel').small,
                      ),
                      const Gap(8),
                      PrimaryButton(
                        size: ButtonSize.small,
                        density: ButtonDensity.compact,
                        onPressed: _saving ? null : _save,
                        leading: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.check, size: 16),
                        child: const Text('Save').small,
                      ),
                    ] else ...[
                      if (canEdit)
                        IconButton.ghost(
                          icon: const Icon(LucideIcons.pencil, size: 16),
                          size: ButtonSize.small,
                          density: ButtonDensity.compact,
                          onPressed: () => _startEdit(content),
                        ),
                      IconButton.ghost(
                        icon: const Icon(LucideIcons.x, size: 16),
                        size: ButtonSize.small,
                        density: ButtonDensity.compact,
                        onPressed: () => closeSheet(context),
                      ),
                    ],
                  ],
                ),
                const Gap(12),
                Flexible(
                  child: !loaded
                      ? (snapshot.hasError
                          ? Text(
                              snapshot.error is OpencodeApiException
                                  ? (snapshot.error as OpencodeApiException)
                                      .message
                                  : '${snapshot.error}',
                            ).muted
                          : const Center(child: CircularProgressIndicator()))
                      : isImage
                          ? _buildImageView(content, mimeType)
                          : isBinary
                              ? _buildBinaryPlaceholder(mimeType)
                              : _editing
                                  ? TextArea(
                                      controller: _editController,
                                      enabled: !_saving,
                                      expandableHeight: true,
                                      initialHeight: 420,
                                      minHeight: 200,
                                      maxHeight: 520,
                                      style: TextStyle(
                                        fontFamily: CodeHighlightView
                                            .monoFamilies.first,
                                        fontFamilyFallback: CodeHighlightView
                                            .monoFamilies
                                            .skip(1)
                                            .toList(),
                                        fontSize: 13,
                                      ),
                                    )
                                  : CodeHighlightView(
                                      code: content,
                                      path: widget.path,
                                      lineNumbers: true,
                                      constraints:
                                          const BoxConstraints(maxHeight: 460),
                                    ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageView(String base64Content, String? mimeType) {
    Uint8List? bytes;
    try {
      bytes = base64Decode(base64Content);
    } catch (_) {}
    if (bytes == null) {
      return _buildBinaryPlaceholder(mimeType);
    }
    final cacheWidth = decodeWidthFor(
      400,
      MediaQuery.devicePixelRatioOf(context),
    );
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                cacheWidth: cacheWidth,
                errorBuilder: (_, _, _) => _buildBinaryPlaceholder(
                  mimeType ?? 'image/*',
                ),
              ),
            ),
            if (mimeType != null) ...[
              const Gap(8),
              Text(mimeType).muted.xSmall,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBinaryPlaceholder(String? mimeType) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.fileX, size: 48).muted,
          const Gap(12),
          const Text('Binary file').muted,
          const Gap(4),
          Text(
            'This file type cannot be displayed',
          ).muted.xSmall,
          if (mimeType != null) ...[
            const Gap(8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.muted.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(mimeType).muted.xSmall,
            ),
          ],
        ],
      ),
    );
  }
}
