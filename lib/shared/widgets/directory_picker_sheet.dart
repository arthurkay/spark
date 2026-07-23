import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'path_utils.dart';
import 'sheet_keyboard_padding.dart';

typedef DirectoryPickerCallback = void Function(String path);

class DirectoryPickerSheet extends StatefulWidget {
  const DirectoryPickerSheet({
    super.key,
    required this.title,
    required this.onPick,
    required this.recentDirectories,
    this.initialPath,
    this.helperText,
  });

  final String title;
  final String? initialPath;
  final String? helperText;
  final List<String> recentDirectories;
  final DirectoryPickerCallback onPick;

  static void show(
    BuildContext context, {
    required String title,
    required DirectoryPickerCallback onPick,
    required List<String> recentDirectories,
    String? initialPath,
    String? helperText,
  }) {
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        return SheetKeyboardPadding(
          child: SafeArea(
            child: DirectoryPickerSheet(
              title: title,
              initialPath: initialPath,
              helperText: helperText,
              recentDirectories: recentDirectories,
              onPick: (p) {
                onPick(p);
                closeSheet(sheetContext);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  State<DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends State<DirectoryPickerSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    widget.onPick(trimmed);
  }

  void _navigateToParent() {
    final current = _controller.text;
    if (current.isEmpty) return;
    final parts = current.split('/');
    if (parts.length <= 1) return;
    parts.removeLast();
    _controller.text = parts.join('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPath = _controller.text;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.folderPlus, size: 20),
              const Gap(8),
              Text(widget.title).h4,
            ],
          ),
          if (widget.helperText != null) ...[
            const Gap(6),
            Text(widget.helperText!).muted.small,
          ],
          const Gap(16),
          TextField(
            controller: _controller,
            placeholder: const Text('/absolute/path/to/folder'),
            onSubmitted: _select,
          ),
          if (currentPath.contains('/') && currentPath != '/') ...[
            const Gap(4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _navigateToParent,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.arrowUp, size: 12),
                    const Gap(4),
                    Text('Parent: ${compactPath(_parentOf(currentPath))}'),
                  ],
                ),
              ),
            ),
          ],
          const Gap(16),
          PrimaryButton(
            onPressed: () => _select(currentPath),
            child: const Text('Select'),
          ),
          if (widget.recentDirectories.isNotEmpty) ...[
            const Gap(20),
            Row(
              children: [
                const Icon(LucideIcons.clock, size: 14).iconMutedForeground,
                const Gap(6),
                const Text('Recent projects').small.semiBold.muted,
              ],
            ),
            const Gap(8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.recentDirectories.length,
                  separatorBuilder: (_, __) => const Gap(2),
                  itemBuilder: (context, index) {
                    final dir = widget.recentDirectories[index];
                    return GestureDetector(
                      onTap: () => _select(dir),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    compactPath(dir),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ).small.semiBold,
                                  Text(
                                    dir,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ).muted.xSmall,
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
            ),
          ],
          const Gap(8),
        ],
      ),
    );
  }

  String _parentOf(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return path;
    parts.removeLast();
    return parts.join('/');
  }
}
