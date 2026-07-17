import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/permission_provider.dart';
import '../../core/api/providers.dart';
import '../../core/models/message.dart';
import '../../core/models/permission.dart';
import '../../core/notifications/notification_service.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/markdown_view.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final MessageWithParts message;

  bool get _isUser => message.info.role == 'user';

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final part in message.parts) {
      final widget = _buildPart(context, part);
      if (widget != null) children.add(widget);
    }
    if (children.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color:
                _isUser ? theme.colorScheme.primary : theme.colorScheme.muted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _isUser ? LucideIcons.user : LucideIcons.sparkles,
            size: 15,
            color: _isUser ? Colors.white : theme.colorScheme.foreground,
          ),
        ),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _text(BuildContext context, String text) {
    final theme = Theme.of(context);
    return SelectableText(
      text,
      style: TextStyle(
        color: theme.colorScheme.foreground,
        fontSize: 15,
        height: 1.65,
      ),
    );
  }

  Widget? _buildPart(BuildContext context, MessagePart part) {
    switch (part.type) {
      case 'text':
        final text = part.text?.trim();
        if (text == null || text.isEmpty) return null;
        final isMarkdown = text.contains(RegExp(r'[`*_#>\n]|^\s*- '));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: isMarkdown ? MarkdownView(data: text) : _text(context, text),
        );
      case 'reasoning':
        final text = part.text?.trim();
        if (text == null || text.isEmpty) return null;
        return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 2),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.muted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.brain, size: 14).iconMutedForeground,
              const Gap(8),
              Expanded(child: Text(text).muted.small.italic),
            ],
          ),
        );
      case 'tool':
        return _ToolChip(part: part);
      case 'file':
        return _FilePartWidget(part: part);
      default:
        return null;
    }
  }
}

const _expandableToolTypes = {'glob', 'read', 'edit', 'todowrite', 'write', 'bash'};

IconData _toolIcon(String? name) {
  switch (name) {
    case 'bash':
      return LucideIcons.terminal;
    case 'question':
      return LucideIcons.circleHelp;
    case 'glob':
      return LucideIcons.folderSearch;
    case 'read':
      return LucideIcons.fileText;
    case 'edit':
      return LucideIcons.pencil;
    case 'write':
      return LucideIcons.filePlus;
    case 'todowrite':
      return LucideIcons.listChecks;
    case 'webfetch':
      return LucideIcons.globe;
    case 'websearch':
      return LucideIcons.search;
    case 'task':
      return LucideIcons.layers;
    case 'grep':
      return LucideIcons.searchCode;
    default:
      return LucideIcons.wrench;
  }
}

class _ToolChip extends StatefulWidget {
  const _ToolChip({required this.part});

  final MessagePart part;

  @override
  State<_ToolChip> createState() => _ToolChipState();
}

class _ToolChipState extends State<_ToolChip> {
  late bool _expanded;

  bool get _isExpandable => _expandableToolTypes.contains(widget.part.toolName);
  bool get _isQuestion => widget.part.toolName == 'question';
  bool get _isBash => widget.part.toolName == 'bash';
  bool get _isTappable => _isQuestion || _isBash;

  @override
  void initState() {
    super.initState();
    _expanded = _isExpandable;
  }

  Map<String, dynamic>? get _state =>
      widget.part.raw['state'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _input {
    final raw = _state?['input'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) return parsed;
      } catch (_) {}
    }
    return null;
  }

  String get _output => (_state?['output'] as String?) ?? '';

  List<Map<String, dynamic>> _extractQuestions() {
    final state = widget.part.raw['state'] as Map<String, dynamic>?;
    if (state == null) return const [];
    final input = state['input'] as Map<String, dynamic>?;
    if (input == null) return const [];
    final questions = input['questions'];
    if (questions is List) {
      return questions.whereType<Map<String, dynamic>>().toList();
    }
    final single = <String, dynamic>{};
    for (final key in ['question', 'content', 'message', 'prompt', 'text']) {
      final value = input[key];
      if (value is String && value.isNotEmpty) {
        single['question'] = value;
        break;
      }
    }
    if (single.isEmpty && input.isNotEmpty) {
      final first = input.values.firstWhere(
        (v) => v is String && v.isNotEmpty,
        orElse: () => null,
      );
      if (first is String) single['question'] = first;
    }
    return single.isEmpty ? const [] : [single];
  }

  Widget _buildContentPreview(BuildContext context) {
    final input = _input;
    final output = _output;
    final name = widget.part.toolName ?? '';

    switch (name) {
      case 'glob':
        final pattern = input?['pattern'] as String? ?? '';
        if (pattern.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _contentLabel('Pattern'),
            const Gap(4),
            _codeBlock(context, pattern),
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Results'),
              const Gap(4),
              _codeBlock(context, output, maxLines: 8),
            ],
          ],
        );
      case 'read':
        final filePath =
            input?['filePath'] as String? ?? input?['path'] as String? ?? '';
        if (filePath.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _contentLabel('File'),
            const Gap(4),
            _codeBlock(context, filePath),
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Content'),
              const Gap(4),
              _codeBlock(context, output, maxLines: 12),
            ],
          ],
        );
      case 'edit':
        final filePath =
            input?['filePath'] as String? ?? input?['path'] as String? ?? '';
        final oldString = input?['oldString'] as String? ??
            input?['old_string'] as String? ??
            '';
        final newString = input?['newString'] as String? ??
            input?['new_string'] as String? ??
            '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filePath.isNotEmpty) ...[
              _contentLabel('File'),
              const Gap(4),
              _codeBlock(context, filePath),
            ],
            if (oldString.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Removed'),
              const Gap(4),
              _diffBlock(context, oldString, isRemoved: true),
            ],
            if (newString.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Added'),
              const Gap(4),
              _diffBlock(context, newString, isRemoved: false),
            ],
          ],
        );
      case 'write':
        final filePath =
            input?['filePath'] as String? ?? input?['path'] as String? ?? '';
        final content = input?['content'] as String? ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filePath.isNotEmpty) ...[
              _contentLabel('File'),
              const Gap(4),
              _codeBlock(context, filePath),
            ],
            if (content.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Content'),
              const Gap(4),
              _codeBlock(context, content, maxLines: 12),
            ],
          ],
        );
      case 'todowrite':
        final todoContent = input?['content'] as String? ??
            input?['todo'] as String? ??
            input?['text'] as String? ??
            output;
        if (todoContent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _contentLabel('Tasks'),
            const Gap(4),
            _codeBlock(context, todoContent, maxLines: 8),
          ],
        );
      case 'bash':
        final command = input?['command'] as String? ??
            input?['cmd'] as String? ??
            '';
        if (command.isEmpty && output.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (command.isNotEmpty) ...[
              _contentLabel('Command'),
              const Gap(4),
              _codeBlock(context, command),
            ],
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Output'),
              const Gap(4),
              _codeBlock(context, output, maxLines: 12),
            ],
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _contentLabel(String text) {
    return Text(text).xSmall.semiBold.muted;
  }

  Widget _codeBlock(BuildContext context, String code, {int maxLines = 6}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.border.withAlpha(120),
        ),
      ),
      child: SelectableText(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: theme.colorScheme.foreground,
          height: 1.5,
        ),
        maxLines: maxLines,
      ),
    );
  }

  Widget _diffBlock(
    BuildContext context,
    String text, {
    required bool isRemoved,
  }) {
    final theme = Theme.of(context);
    final bg =
        isRemoved ? Colors.red.withAlpha(15) : Colors.green.withAlpha(15);
    final border =
        isRemoved ? Colors.red.withAlpha(60) : Colors.green.withAlpha(60);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: theme.colorScheme.foreground,
          height: 1.5,
        ),
        maxLines: 6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.part.toolName ?? 'tool';
    final status = widget.part.state ?? '';
    final theme = Theme.of(context);
    final hasContent = _isExpandable && (_input != null || _output.isNotEmpty);

    final chip = Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: hasContent
                ? () => setState(() => _expanded = !_expanded)
                : (_isTappable
                    ? () => _isQuestion
                        ? _showQuestionSheet(context)
                        : _showBashSheet(context)
                    : null),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(_toolIcon(name), size: 14),
                  const Gap(8),
                  Expanded(
                    child: Text(name).small.semiBold,
                  ),
                  if (status.isNotEmpty) ...[
                    const Gap(6),
                    _StatusBadge(status: status),
                  ],
                  if (hasContent || _isTappable) ...[
                    const Gap(6),
                    Icon(
                      _expanded
                          ? LucideIcons.chevronDown
                          : (_isTappable
                              ? LucideIcons.chevronRight
                              : LucideIcons.chevronDown),
                      size: 12,
                    ).iconMutedForeground,
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && hasContent) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildContentPreview(context),
            ),
          ],
        ],
      ),
    );

    if (_isTappable && !_isExpandable) {
      return GestureDetector(
        onTap: () =>
            _isQuestion ? _showQuestionSheet(context) : _showBashSheet(context),
        child: chip,
      );
    }

    return chip;
  }

  PermissionRequest? _findPermission(Map<String, PermissionRequest> pending) {
    final callID = widget.part.raw['callID'] as String?;
    final messageID = widget.part.raw['messageID'] as String?;
    final sessionID = widget.part.raw['sessionID'] as String?;

    if (callID != null) {
      final byCall =
          pending.values.where((p) => p.callID == callID).firstOrNull;
      if (byCall != null) return byCall;
    }
    if (messageID != null) {
      final byMsg =
          pending.values.where((p) => p.messageID == messageID).firstOrNull;
      if (byMsg != null) return byMsg;
    }
    if (sessionID != null) {
      final bySession =
          pending.values.where((p) => p.sessionID == sessionID).firstOrNull;
      if (bySession != null) return bySession;
    }
    return null;
  }

  void _showQuestionSheet(BuildContext context) {
    final questions = _extractQuestions();
    final pending =
        ProviderScope.containerOf(context).read(pendingPermissionsProvider);
    final permission = _findPermission(pending);
    final sessionID = (widget.part.raw['sessionID'] as String?) ??
        permission?.sessionID ??
        '';

    final rawState = widget.part.raw['state'];
    final stateMap = rawState is Map<String, dynamic> ? rawState : null;
    final output = stateMap?['output'] as String?;
    final isCompleted = widget.part.state == 'completed' ||
        widget.part.state == 'error' ||
        widget.part.state == 'timeout';

    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        return SheetKeyboardPadding(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _QuestionSheetBody(
                questions: questions,
                permission: permission,
                sessionID: sessionID,
                toolName: widget.part.toolName ?? 'question',
                state: widget.part.state ?? '',
                answer: isCompleted ? output : null,
                isRunning: !isCompleted && permission != null,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBashSheet(BuildContext context) {
    final rawState = widget.part.raw['state'];
    Map<String, dynamic>? state;
    if (rawState is Map<String, dynamic>) {
      state = rawState;
    }
    Map<String, dynamic>? input;
    var rawInput = state?['input'];
    if (rawInput is Map<String, dynamic>) {
      input = rawInput;
    } else if (rawInput is String && rawInput.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawInput);
        if (parsed is Map<String, dynamic>) input = parsed;
      } catch (_) {}
    }
    final command = (input?['command'] as String?) ?? '';
    final output = (state?['output'] as String?) ?? '';
    final metadata = state?['metadata'] is Map<String, dynamic>
        ? (state?['metadata'] as Map<String, dynamic>)
        : null;
    final exitCode = metadata?['exit'];
    final status = widget.part.state ?? 'running';

    openSheetOverlay(
      context: context,
      position: OverlayPosition.bottom,
      barrierDismissible: true,
      builder: (sheetContext) {
        return SheetKeyboardPadding(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.terminal),
                        const Gap(8),
                        const Text('Bash command').h4,
                        const Spacer(),
                        if (exitCode != null)
                          Text('exit $exitCode').muted.small
                        else
                          Text(status).muted.small,
                      ],
                    ),
                    const Gap(12),
                    if (command.isNotEmpty)
                      CodeHighlightView(
                        code: command,
                        language: 'bash',
                        lineNumbers: true,
                        constraints: const BoxConstraints(maxHeight: 240),
                      ),
                    if (output.isNotEmpty) ...[
                      const Gap(12),
                      const Text('Output').semiBold.small,
                      const Gap(6),
                      CodeHighlightView(
                        code: output,
                        language: 'bash',
                        constraints: const BoxConstraints(maxHeight: 240),
                      ),
                    ],
                    if (command.isEmpty && output.isEmpty) ...[
                      const Gap(8),
                      const Text(
                        'Command is still running or produced no captured '
                        'output.',
                      ).muted.small,
                    ],
                    const Gap(12),
                    const Text(
                      'Bash permissions are handled from the permission banner.',
                    ).muted.xSmall,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      'running' => ('running', theme.colorScheme.primary),
      'completed' => ('done', Colors.green),
      'error' => ('error', Colors.red),
      'timeout' => ('timeout', Colors.orange),
      _ => (status, theme.colorScheme.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

Widget _questionCard(List<Map<String, dynamic>> questions) {
  return Card(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final q in questions) ...[
          if (q['header'] is String) ...[
            Text(q['header'] as String).semiBold,
            const Gap(4),
          ],
          SelectableText(
            (q['question'] as String?) ?? '',
          ),
          if (q['options'] is List) ...[
            const Gap(8),
            for (final opt in (q['options'] as List)) ...[
              if (opt is Map<String, dynamic>) ...[
                Text('• ${(opt['label'] as String?) ?? ''}').small.muted,
                if (opt['description'] is String) ...[
                  Text('  ${(opt['description'] as String)}').xSmall.muted,
                ],
              ] else if (opt is String) ...[
                Text('• $opt').small.muted,
              ],
              const Gap(2),
            ],
          ],
          if (q != questions.last) const Gap(12),
        ],
      ],
    ),
  );
}

class _QuestionSheetBody extends StatefulWidget {
  const _QuestionSheetBody({
    required this.questions,
    required this.permission,
    required this.sessionID,
    required this.toolName,
    required this.state,
    this.answer,
    this.isRunning = false,
  });

  final List<Map<String, dynamic>> questions;
  final PermissionRequest? permission;
  final String sessionID;
  final String toolName;
  final String state;
  final String? answer;
  final bool isRunning;

  @override
  State<_QuestionSheetBody> createState() => _QuestionSheetBodyState();
}

class _QuestionSheetBodyState extends State<_QuestionSheetBody> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String response, {bool remember = false}) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) return;
    final container = ProviderScope.containerOf(context);
    final client = container.read(opencodeClientProvider);
    final permission = widget.permission;
    if (permission != null) {
      final map = {...container.read(pendingPermissionsProvider)};
      if (map.remove(permission.id) != null) {
        container.read(pendingPermissionsProvider.notifier).state =
            map.isEmpty ? const {} : map;
        if (map.isEmpty) NotificationService.instance.cancelPermission();
      }
      client
          ?.respondPermission(
            sessionId: permission.sessionID,
            permissionId: permission.id,
            response: trimmed,
            remember: remember,
          )
          .catchError((_) {});
    }
    if (mounted) closeSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasAnswer = widget.answer != null && widget.answer!.isNotEmpty;
    final showInput = !hasAnswer && widget.isRunning;

    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.circleHelp),
              const Gap(8),
              const Text('Question').h4,
              const Spacer(),
              Text(widget.state).muted.small,
            ],
          ),
          const Gap(12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.questions.isNotEmpty)
                    _questionCard(widget.questions)
                  else
                    Card(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(widget.toolName).mono.small,
                    ),
                  const Gap(12),
                  if (hasAnswer)
                    Card(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Answer').muted.xSmall.semiBold,
                          const Gap(4),
                          SelectableText(widget.answer!).mono.small,
                        ],
                      ),
                    )
                  else if (showInput)
                    TextArea(
                      controller: _controller,
                      placeholder: const Text('Type your answer…'),
                      minLines: 2,
                      maxLines: 6,
                    )
                  else
                    Card(
                      padding: const EdgeInsets.all(12),
                      child: const Text(
                        'This question is no longer active.',
                      ).muted.small,
                    ),
                ],
              ),
            ),
          ),
          const Gap(12),
          if (hasAnswer || !showInput)
            OutlineButton(
              onPressed: () => closeSheet(context),
              child: const Text('Close'),
            )
          else ...[
            PrimaryButton(
              onPressed: () => _submit(_controller.text),
              child: const Text('Send answer'),
            ),
            if (widget.permission != null) ...[
              const Gap(8),
              Row(
                children: [
                  Expanded(
                    child: OutlineButton(
                      onPressed: () => _submit('always', remember: true),
                      child: const Text('Always allow'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: OutlineButton(
                      onPressed: () => _submit('once'),
                      child: const Text('Allow once'),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              DestructiveButton(
                onPressed: () => _submit('reject'),
                child: const Text('Reject'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilePartWidget extends StatelessWidget {
  const _FilePartWidget({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final url = part.raw['url'] as String? ?? '';
    final mime = part.raw['mime'] as String? ?? '';
    final filename = part.raw['filename'] as String? ?? 'file';
    final isImage = mime.startsWith('image/') && url.isNotEmpty;
    final theme = Theme.of(context);

    if (isImage) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            width: 300,
            errorBuilder: (context, error, stack) => _FileChip(
              filename: filename,
              mime: mime,
              theme: theme,
            ),
          ),
        ),
      );
    }

    return _FileChip(filename: filename, mime: mime, theme: theme);
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({
    required this.filename,
    required this.mime,
    required this.theme,
  });

  final String filename;
  final String mime;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.file, size: 14),
          const Gap(8),
          Flexible(
            child: Text(
              filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small,
          ),
          if (mime.isNotEmpty) ...[
            const Gap(6),
            Text(mime.split('/').last).muted.xSmall,
          ],
        ],
      ),
    );
  }
}
