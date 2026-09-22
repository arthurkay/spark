import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/haptics.dart';
import 'workspace_providers.dart';

void openQuickOpen({
  required BuildContext context,
  required WidgetRef ref,
  required String? directory,
  required ValueChanged<FileNode> onOpen,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  openSheetOverlay(
    context: context,
    position: OverlayPosition.bottom,
    barrierDismissible: true,
    builder: (context) => _QuickOpenBody(directory: directory, onOpen: onOpen),
  );
}

class _QuickOpenBody extends ConsumerStatefulWidget {
  const _QuickOpenBody({required this.directory, required this.onOpen});

  final String? directory;
  final ValueChanged<FileNode> onOpen;

  @override
  ConsumerState<_QuickOpenBody> createState() => _QuickOpenBodyState();
}

class _QuickOpenBodyState extends ConsumerState<_QuickOpenBody> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<FileNode>? _files;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(opencodeClientProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected';
      });
      return;
    }
    try {
      final files = await collectFiles(
        client,
        directory: widget.directory,
        path: '',
      );
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _open(FileNode node) {
    Haptics.selection();
    closeSheet(context);
    widget.onOpen(node);
  }

  @override
  Widget build(BuildContext context) {
    final results = _files == null
        ? const <FileNode>[]
        : rankFiles(_query, _files!);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.search, size: 16),
                const Gap(8),
                const Text('Go to file').h4,
                const Spacer(),
                Text('Esc to close').xSmall.muted,
              ],
            ),
            const Gap(12),
            TextField(
              focusNode: _focusNode,
              controller: _controller,
              placeholder: const Text('Type a file name…'),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) {
                if (results.isNotEmpty) _open(results.first);
              },
            ),
            const Gap(12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!).muted
            else if (_files != null && _files!.isEmpty)
              const Text('No files found').muted
            else if (_query.isNotEmpty && results.isEmpty)
              const Text('No matches').muted
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final node = results[index];
                    final dir = node.path.contains('/')
                        ? node.path.substring(0, node.path.lastIndexOf('/'))
                        : '';
                    return GhostButton(
                      alignment: Alignment.centerLeft,
                      onPressed: () => _open(node),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.file, size: 14),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              node.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small,
                          ),
                          if (dir.isNotEmpty)
                            Flexible(
                              child: Text(
                                dir,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ).xSmall.muted,
                            ),
                        ],
                      ),
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
