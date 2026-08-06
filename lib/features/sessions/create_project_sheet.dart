import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/project.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/path_utils.dart';
import '../../shared/widgets/server_directory_picker_sheet.dart';
import 'workspace_provider.dart';

enum _CreateMode { worktree, copy }

class CreateProjectSheet extends ConsumerStatefulWidget {
  const CreateProjectSheet({super.key});

  @override
  ConsumerState<CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends ConsumerState<CreateProjectSheet> {
  _CreateMode? _mode;
  Project? _sourceProject;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsProvider);

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
              Text(_mode == null ? 'Add project' : _modeTitle()).h4,
            ],
          ),
          const Gap(6),
          Text(_modeSubtitle()).muted.small,
          const Gap(16),
          if (_mode == null) ..._buildModePicker(),
          if (_mode == _CreateMode.worktree) ...[
            projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e').muted,
              data: (projects) {
                final candidates = projects.where((p) => !p.isGlobal).toList();
                if (candidates.isEmpty) {
                  return Text(
                    'No existing projects to create a worktree from.',
                  ).muted;
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Gap(6),
                      itemBuilder: (context, index) {
                        final p = candidates[index];
                        return _ProjectChoiceTile(
                          project: p,
                          selected: _sourceProject?.id == p.id,
                          onTap: () => setState(() => _sourceProject = p),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const Gap(12),
            PrimaryButton(
              onPressed:
                  (_sourceProject == null || _busy) ? null : _onPickForWorktree,
              child: const Text('Choose worktree path'),
            ),
          ],
          if (_mode == _CreateMode.copy) ...[
            projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e').muted,
              data: (projects) {
                final candidates = projects.where((p) => !p.isGlobal).toList();
                if (candidates.isEmpty) {
                  return Text('No projects available to copy.').muted;
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Gap(6),
                      itemBuilder: (context, index) {
                        final p = candidates[index];
                        return _ProjectChoiceTile(
                          project: p,
                          selected: _sourceProject?.id == p.id,
                          onTap: () => setState(() => _sourceProject = p),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const Gap(12),
            PrimaryButton(
              onPressed:
                  (_sourceProject == null || _busy) ? null : _onPickForCopy,
              child: const Text('Choose destination folder'),
            ),
          ],
          if (_mode != null) ...[
            const Gap(8),
            OutlineButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _mode = null;
                        _sourceProject = null;
                      }),
              child: const Text('Back'),
            ),
          ],
        ],
      ),
    );
  }

  String _modeTitle() {
    switch (_mode) {
      case _CreateMode.worktree:
        return 'Create worktree';
      case _CreateMode.copy:
        return 'Copy project';
      default:
        return 'Add project';
    }
  }

  String _modeSubtitle() {
    switch (_mode) {
      case _CreateMode.worktree:
        return 'Create a new worktree from an existing project. The worktree becomes a new project.';
      case _CreateMode.copy:
        return 'Copy an existing project to a new location. The copy becomes a new project.';
      default:
        return 'Pick how you want to add a project.';
    }
  }

  List<Widget> _buildModePicker() {
    return [
      _ModeTile(
        icon: LucideIcons.gitFork,
        title: 'Create worktree',
        subtitle: 'Branch a new working copy from an existing git project.',
        onTap: () => setState(() => _mode = _CreateMode.worktree),
      ),
      const Gap(8),
      _ModeTile(
        icon: LucideIcons.copy,
        title: 'Copy project',
        subtitle: 'Duplicate an existing project to a new folder.',
        onTap: () => setState(() => _mode = _CreateMode.copy),
      ),
    ];
  }

  void _onPickForWorktree() {
    final source = _sourceProject;
    if (source == null) return;
    final initial = parentOf(source.worktree);
    ServerDirectoryPickerSheet.show(
      context,
      title: 'Choose worktree path',
      initialPath: initial.isNotEmpty ? initial : '/',
      helperText: 'The new worktree will be created in this folder.',
      onPick: (path) async {
        final branch = await _promptText(
          'Worktree branch name',
          initial: 'feature/new',
        );
        if (branch == null || branch.isEmpty) return;
        await _runBusy(() async {
          final client = ref.read(opencodeClientProvider);
          if (client == null) return;
          try {
            await client.createWorktree({
              'directory': path,
              'branch': branch,
            }, directory: source.worktree);
            ref.read(projectsRefreshProvider.notifier).state++;
            if (!mounted) return;
            showAppToast(context,
                title: 'Worktree created', description: '$path ($branch)');
            closeSheet(context);
          } on OpencodeApiException catch (e) {
            if (!mounted) return;
            showAppToast(context,
                title: 'Failed to create worktree', description: e.message);
          }
        });
      },
    );
  }

  void _onPickForCopy() {
    final source = _sourceProject;
    if (source == null) return;
    ServerDirectoryPickerSheet.show(
      context,
      title: 'Choose destination folder',
      helperText: 'The project copy will be placed in this folder.',
      onPick: (path) async {
        await _runBusy(() async {
          final client = ref.read(opencodeClientProvider);
          if (client == null) return;
          try {
            final name = await client.generateProjectCopyName(
              source.id,
              directory: source.worktree,
            );
            await client.createProjectCopy(
              source.id,
              directory: path,
              name: name.isNotEmpty ? name : null,
              sourceDirectory: source.worktree,
            );
            ref.read(projectsRefreshProvider.notifier).state++;
            if (!mounted) return;
            showAppToast(context, title: 'Project copied', description: path);
            closeSheet(context);
          } on OpencodeApiException catch (e) {
            if (!mounted) return;
            showAppToast(context,
                title: 'Failed to copy project', description: e.message);
          }
        });
      },
    );
  }

  Future<String?> _promptText(String title, {String? initial}) async {
    final completer = _AsyncCompleter<String?>();
    final controller = TextEditingController(text: initial ?? '');
    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title).h4,
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onSubmitted: (v) {
                    closeSheet(sheetContext);
                    completer.complete(v.trim());
                  },
                ),
                const Gap(16),
                PrimaryButton(
                  onPressed: () {
                    closeSheet(sheetContext);
                    completer.complete(controller.text.trim());
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
    final result = await completer.future;
    controller.dispose();
    return (result ?? '').isEmpty ? null : result;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AsyncCompleter<T> {
  final List<void Function(T)> _listeners = [];
  T? _value;
  bool _completed = false;

  Future<T> get future {
    if (_completed) return Future.value(_value as T);
    return Future(() async {
      while (!_completed) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _value as T;
    });
  }

  void complete(T value) {
    if (_completed) return;
    _value = value;
    _completed = true;
    for (final l in _listeners) {
      l(value);
    }
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title).semiBold,
                  const Gap(2),
                  Text(subtitle).muted.small,
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 16).iconMutedForeground,
          ],
        ),
      ),
    );
  }
}

class _ProjectChoiceTile extends StatelessWidget {
  const _ProjectChoiceTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.check : LucideIcons.circle,
              size: 16,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.worktree.split('/').last,
                  ).small.semiBold,
                  Text(
                    project.worktree,
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
  }
}
