import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import 'sheet_keyboard_padding.dart';

typedef ServerDirectoryPickerCallback = void Function(String path);

class ServerDirectoryPickerSheet extends ConsumerStatefulWidget {
  const ServerDirectoryPickerSheet({
    super.key,
    required this.title,
    required this.onPick,
    this.initialPath = '/',
    this.helperText,
  });

  final String title;
  final String? helperText;
  final String initialPath;
  final ServerDirectoryPickerCallback onPick;

  static void show(
    BuildContext context, {
    required String title,
    required ServerDirectoryPickerCallback onPick,
    String initialPath = '/',
    String? helperText,
  }) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        return SheetKeyboardPadding(
          child: SafeArea(
            child: ProviderScope(
              child: ServerDirectoryPickerSheet(
                title: title,
                initialPath: initialPath,
                helperText: helperText,
                onPick: (p) {
                  onPick(p);
                  closeSheet(sheetContext);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<ServerDirectoryPickerSheet> createState() =>
      _ServerDirectoryPickerSheetState();
}

class _ServerDirectoryPickerSheetState
    extends ConsumerState<ServerDirectoryPickerSheet> {
  late final TextEditingController _searchController;
  String _currentPath = '/';
  List<FileNode> _entries = [];
  bool _loading = true;
  String? _error;
  String? _directoryScope;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _searchController = TextEditingController();
    _resolveScopeAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FileNode> get _filteredEntries {
    if (_filter.isEmpty) return _entries;
    final q = _filter.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _resolveScopeAndLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = ref.read(opencodeClientProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected to server';
      });
      return;
    }

    try {
      if (_directoryScope == null) {
        final current = await client.currentProject();
        if (current != null) {
          _directoryScope = current.worktree;
        } else {
          final projects = await client.listProjects();
          final nonGlobal = projects.where((p) => !p.isGlobal).toList();
          if (nonGlobal.isNotEmpty) {
            _directoryScope = nonGlobal.first.worktree;
          }
        }
      }
      await _loadDirectory(client);
    } on OpencodeApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _loadDirectory(OpencodeClient client) async {
    final scope = _directoryScope;
    try {
      final files = await client.listFiles(
        _currentPath,
        directory: scope,
      );
      if (!mounted) return;
      setState(() {
        _entries = files.where((f) => f.isDirectory).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _loading = false;
        _filter = '';
        _searchController.clear();
      });
    } on OpencodeApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
    });
    final client = ref.read(opencodeClientProvider);
    if (client != null) {
      setState(() => _loading = true);
      _loadDirectory(client);
    }
  }

  void _navigateToParent() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;
    parts.removeLast();
    _navigateTo('/${parts.join('/')}');
  }

  void _selectPath(String path) {
    widget.onPick(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredEntries;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.folderOpen, size: 20),
              const Gap(8),
              Text(widget.title).h4,
            ],
          ),
          if (widget.helperText != null) ...[
            const Gap(6),
            Text(widget.helperText!).muted.small,
          ],
          const Gap(16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.folder, size: 14).iconMutedForeground,
                const Gap(8),
                Expanded(
                  child: Text(
                    _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small,
                ),
                IconButton.ghost(
                  icon: const Icon(LucideIcons.arrowUp, size: 16),
                  size: ButtonSize.small,
                  density: ButtonDensity.compact,
                  onPressed: _currentPath == '/' ? null : _navigateToParent,
                ),
              ],
            ),
          ),
          const Gap(12),
          TextField(
            controller: _searchController,
            placeholder: const Text('Filter directories'),
            features: const [
              InputFeature.leading(Icon(LucideIcons.search, size: 16)),
            ],
            onChanged: (v) => setState(() => _filter = v.trim()),
          ),
          const Gap(12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(_error!).muted,
                  const Gap(8),
                  OutlineButton(
                    onPressed: _resolveScopeAndLoad,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _filter.isNotEmpty
                    ? 'No matching directories.'
                    : 'No subdirectories found.',
              ).muted.textCenter,
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Gap(2),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return GestureDetector(
                      onTap: () => _navigateTo(entry.path),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.muted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.folder, size: 16),
                            const Gap(10),
                            Expanded(
                              child: Text(entry.name).small.semiBold,
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              size: 14,
                            ).iconMutedForeground,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const Gap(12),
          PrimaryButton(
            onPressed: () => _selectPath(_currentPath),
            child: Text('Select $_currentPath'),
          ),
          const Gap(8),
        ],
      ),
    );
  }
}
