import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/models/permission.dart';
import '../../core/storage/settings_provider.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';

const _filePermissionTypes = {'glob', 'read', 'edit', 'write'};

typedef PermissionResponder = void Function(String response, bool remember);

void showPermissionSheet({
  required BuildContext context,
  required PermissionRequest permission,
  required PermissionResponder onRespond,
}) {
  openSheetOverlay(
    context: context,
    position: OverlayPosition.bottom,
    barrierDismissible: false,
    builder: (context) {
      return _PermissionSheetContent(
        permission: permission,
        onRespond: onRespond,
      );
    },
  );
}

class _PermissionSheetContent extends ConsumerStatefulWidget {
  const _PermissionSheetContent({
    required this.permission,
    required this.onRespond,
  });

  final PermissionRequest permission;
  final PermissionResponder onRespond;

  @override
  ConsumerState<_PermissionSheetContent> createState() =>
      _PermissionSheetContentState();
}

class _PermissionSheetContentState
    extends ConsumerState<_PermissionSheetContent> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    final collapsed = ref.read(collapseFilePermissionsProvider);
    final isFile = _filePermissionTypes.contains(widget.permission.type);
    _expanded = isFile ? !collapsed : true;
  }

  @override
  Widget build(BuildContext context) {
    final permission = widget.permission;
    final patterns = permission.pattern;
    final hasMetadata = permission.metadata.isNotEmpty;

    return SheetKeyboardPadding(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(permissionIcon(permission.type)),
                  const Gap(8),
                  const Text('Permission request').h4,
                ],
              ),
              const Gap(12),
              Text(
                permission.title ?? permission.type ?? 'Allow this action?',
              ),
              if (hasMetadata) ...[
                const Gap(12),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Details').muted.small.semiBold,
                      ),
                      Icon(
                        _expanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight,
                        size: 14,
                      ).iconMutedForeground,
                    ],
                  ),
                ),
                if (_expanded) ...[
                  const Gap(8),
                  Card(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final e in permission.metadata.entries) ...[
                          if (_isCommandEntry(e.key, e.value)) ...[
                            CodeHighlightView(
                              code: e.value.toString(),
                              language: 'bash',
                              constraints: const BoxConstraints(maxHeight: 200),
                            ),
                          ] else
                            SelectableText(
                              '${e.key}: ${e.value}',
                            ).mono.small,
                          const Gap(6),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
              if (patterns != null && patterns.isNotEmpty) ...[
                const Gap(12),
                Text('Always allow will approve:').muted.small.semiBold,
                const Gap(4),
                Card(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    patterns.join('\n'),
                  ).mono.small,
                ),
              ],
              const Gap(20),
              PrimaryButton(
                onPressed: () {
                  widget.onRespond('always', true);
                  closeSheet(context);
                },
                child: const Text('Always allow'),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  widget.onRespond('once', false);
                  closeSheet(context);
                },
                child: const Text('Allow once'),
              ),
              const Gap(8),
              DestructiveButton(
                onPressed: () {
                  widget.onRespond('reject', false);
                  closeSheet(context);
                },
                child: const Text('Reject'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isCommandEntry(String key, dynamic value) {
  if (value is! String || value.isEmpty) return false;
  final lowerKey = key.toLowerCase();
  if (lowerKey.contains('command') || lowerKey == 'cmd') return true;
  const commands = {
    'bash',
    'sh',
    'git',
    'npm',
    'yarn',
    'pnpm',
    'deno',
    'bun',
    'cargo',
    'go',
    'python',
    'python3',
    'node',
    'npx',
    'docker',
    'kubectl',
    'make',
    'sudo',
  };
  final firstWord = value.trim().split(RegExp(r'\s+')).first;
  return commands.contains(firstWord);
}
