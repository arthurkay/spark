import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/haptics.dart';
import '../../shared/widgets/app_toast.dart';
import '../chat/chat_provider.dart';
import '../chat/chat_screen.dart';
import '../files/file_write_service.dart';
import 'editor_pane.dart';
import 'file_tree.dart';
import 'quick_open.dart';
import 'workspace_providers.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _treeVisible = true;
  bool _chatVisible = false;
  final _autoSaveTimers = <String, Timer>{};
  final _savingPaths = <String>{};

  bool _layoutInitialized = false;

  @override
  void initState() {
    super.initState();
    Future(() {
      if (!mounted) return;
      ref.read(workspaceProvider.notifier).ensureSession(widget.sessionId);
    });
  }

  @override
  void dispose() {
    for (final timer in _autoSaveTimers.values) {
      timer.cancel();
    }
    _autoSaveTimers.clear();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_layoutInitialized) return;
    _layoutInitialized = true;
    final width = MediaQuery.sizeOf(context).width;
    if (width < 900) _treeVisible = false;
    if (width >= 1280) _chatVisible = true;
  }

  Future<void> _openFile(FileNode node) async {
    final notifier = ref.read(workspaceProvider.notifier);
    final existing = ref
        .read(workspaceProvider)
        .tabs
        .where((t) => t.path == node.path)
        .firstOrNull;
    if (existing != null) {
      notifier.setActive(node.path);
      return;
    }

    notifier.openTab(path: node.path, name: node.name, loading: true);
    _loadTab(node.path, node.name);
  }

  Future<void> _loadTab(String path, String name) async {
    final client = ref.read(opencodeClientProvider);
    final notifier = ref.read(workspaceProvider.notifier);
    if (client == null) {
      notifier.setError(path, 'Not connected');
      return;
    }
    final directory = await ref.read(
      sessionDirectoryProvider(widget.sessionId).future,
    );
    try {
      final content = await client.readFile(path, directory: directory);
      if (!mounted) return;
      if (content.isBinary) {
        notifier.openTab(
          path: path,
          name: name,
          buffer: '',
          saved: '',
          isBinary: true,
          loading: false,
        );
        return;
      }
      final text = content.content
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      notifier.openTab(
        path: path,
        name: name,
        buffer: text,
        saved: text,
        isBinary: false,
        loading: false,
      );
    } catch (e) {
      if (!mounted) return;
      notifier.setError(path, switch (e) {
        OpencodeApiException(:final message) => message,
        _ => '$e',
      });
    }
  }

  Future<void> _saveActive() async {
    final tab = ref.read(workspaceProvider).activeTab;
    if (tab == null) return;
    await _saveTab(tab);
  }

  Future<void> _saveTab(WorkspaceTab tab, {bool silent = false}) async {
    final client = ref.read(opencodeClientProvider);
    if (client == null || tab.isBinary || tab.loading) return;
    if (!tab.dirty || _savingPaths.contains(tab.path)) return;

    final directory = await ref.read(
      sessionDirectoryProvider(widget.sessionId).future,
    );
    final content = tab.buffer;
    _savingPaths.add(tab.path);
    try {
      await PtyFileWriter(
        client: client,
      ).write(path: tab.path, directory: directory, content: content);
      if (!mounted) return;
      ref.read(workspaceProvider.notifier).markSaved(tab.path, content);
      if (!silent) showAppToast(context, title: 'Saved ${tab.name}');
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        title: 'Failed to save',
        description: switch (e) {
          OpencodeApiException(:final message) => message,
          FileWriteException(:final message) => message,
          _ => '$e',
        },
      );
    } finally {
      _savingPaths.remove(tab.path);
    }
  }

  void _onContentChanged(String path, String content) {
    ref.read(workspaceProvider.notifier).updateBuffer(path, content);
    if (!ref.read(autoSaveFilesProvider)) return;
    _autoSaveTimers[path]?.cancel();
    _autoSaveTimers[path] = Timer(const Duration(seconds: 2), () {
      _autoSaveTimers.remove(path);
      if (!mounted) return;
      final tab = ref
          .read(workspaceProvider)
          .tabs
          .where((t) => t.path == path)
          .firstOrNull;
      if (tab == null || !ref.read(autoSaveFilesProvider)) return;
      _saveTab(tab, silent: true);
    });
  }

  Future<void> _closeTab(String path) async {
    final tab = ref
        .read(workspaceProvider)
        .tabs
        .where((t) => t.path == path)
        .firstOrNull;
    if (tab == null) return;
    if (!tab.dirty) {
      Haptics.selection();
      ref.read(workspaceProvider.notifier).closeTab(path);
      return;
    }

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
              const Text('Unsaved changes').h4,
              const Gap(12),
              Text('"${tab.name}" has unsaved changes.').muted,
              const Gap(20),
              PrimaryButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  _saveActive().then((_) {
                    if (!mounted) return;
                    ref.read(workspaceProvider.notifier).closeTab(path);
                  });
                },
                child: const Text('Save and close'),
              ),
              const Gap(8),
              DestructiveButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  Haptics.commit();
                  ref.read(workspaceProvider.notifier).closeTab(path);
                },
                child: const Text('Discard'),
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

  void _openQuickOpen() {
    openQuickOpen(
      context: context,
      ref: ref,
      directory: ref
          .read(sessionDirectoryProvider(widget.sessionId))
          .maybeWhen(data: (v) => v, orElse: () => null),
      onOpen: _openFile,
    );
  }

  void _toggleChat() {
    Haptics.selection();
    final width = MediaQuery.sizeOf(context).width;
    if (!_chatVisible && width < 1100) {
      context.push('/session/${widget.sessionId}');
      return;
    }
    setState(() => _chatVisible = !_chatVisible);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final directoryAsync = ref.watch(
      sessionDirectoryProvider(widget.sessionId),
    );
    final directory = directoryAsync.maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );
    final active = state.activeTab;
    final width = MediaQuery.sizeOf(context).width;
    final canSideChat = width >= 1100;
    final showChat = _chatVisible && canSideChat;
    final showTree = _treeVisible && width >= 720;

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Workspace'),
          subtitle: directory != null && directory.isNotEmpty
              ? Text(
                  directory.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).muted
              : null,
          trailing: [
            IconButton.ghost(
              icon: Tooltip(
                tooltip: (_) => const Text('Files (Ctrl+B)'),
                child: Icon(
                  LucideIcons.panelLeft,
                  color: showTree
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              onPressed: () => setState(() => _treeVisible = !_treeVisible),
            ),
            IconButton.ghost(
              icon: Tooltip(
                tooltip: (_) => const Text('Go to file (Ctrl+P)'),
                child: const Icon(LucideIcons.search),
              ),
              onPressed: _openQuickOpen,
            ),
            IconButton.ghost(
              icon: Tooltip(
                tooltip: (_) => const Text('Chat'),
                child: Icon(
                  LucideIcons.messagesSquare,
                  color: showChat
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              onPressed: _toggleChat,
            ),
            IconButton.ghost(
              icon: Tooltip(
                tooltip: (_) => const Text('Save (Ctrl+S)'),
                child: Icon(
                  LucideIcons.save,
                  color: active?.dirty == true
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              onPressed: _saveActive,
            ),
          ],
        ),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyP, control: true):
              _openQuickOpen,
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
              _openQuickOpen,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              _saveActive,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              _saveActive,
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
            setState(() => _treeVisible = !_treeVisible);
          },
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
            setState(() => _treeVisible = !_treeVisible);
          },
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTree)
              SizedBox(
                width: 260,
                child: FileTree(
                  directory: directory,
                  activePath: state.activePath,
                  onOpenFile: _openFile,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.tabs.isNotEmpty)
                    _TabStrip(
                      tabs: state.tabs,
                      activePath: state.activePath,
                      onSelect: (path) {
                        Haptics.selection();
                        ref.read(workspaceProvider.notifier).setActive(path);
                      },
                      onClose: _closeTab,
                    ),
                  Expanded(child: _buildEditor(active)),
                ],
              ),
            ),
            if (showChat)
              SizedBox(
                width: 400,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.border,
                      ),
                    ),
                  ),
                  child: ChatScreen(
                    sessionId: widget.sessionId,
                    embedded: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(WorkspaceTab? active) {
    if (active == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.squareCode, size: 44).iconMutedForeground,
            const Gap(16),
            const Text('No file open').h3,
            const Gap(6),
            const Text(
              'Pick a file from the tree or press Ctrl+P.',
            ).muted.textCenter,
            const Gap(16),
            OutlineButton(
              onPressed: _openQuickOpen,
              child: const Text('Go to file'),
            ),
          ],
        ),
      );
    }
    return EditorPane(
      key: ValueKey('${active.path}:${active.loading}'),
      path: active.path,
      initialContent: active.buffer,
      isBinary: active.isBinary,
      loading: active.loading,
      error: active.error,
      onChanged: (content) => _onContentChanged(active.path, content),
      onSave: _saveActive,
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.activePath,
    required this.onSelect,
    required this.onClose,
  });

  final List<WorkspaceTab> tabs;
  final String? activePath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.card,
        border: Border(bottom: BorderSide(color: scheme.border)),
      ),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final selected = tab.path == activePath;
            return GestureDetector(
              onTap: () => onSelect(tab.path),
              onDoubleTap: () => onClose(tab.path),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.only(left: 12, right: 6),
                constraints: const BoxConstraints(maxWidth: 200),
                decoration: BoxDecoration(
                  color: selected ? scheme.background : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: selected ? Border.all(color: scheme.border) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.loading)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        tab.isBinary
                            ? LucideIcons.fileWarning
                            : LucideIcons.fileCode,
                        size: 13,
                        color: selected
                            ? scheme.foreground
                            : scheme.mutedForeground,
                      ),
                    const Gap(8),
                    const Gap(8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        tab.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected
                              ? scheme.foreground
                              : scheme.mutedForeground,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    const Gap(6),
                    if (tab.dirty)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    IconButton.ghost(
                      size: ButtonSize.small,
                      icon: const Icon(LucideIcons.x, size: 13),
                      onPressed: () => onClose(tab.path),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
