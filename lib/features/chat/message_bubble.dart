import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/providers.dart';
import '../../core/api/question_provider.dart';
import '../../core/models/message.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/markdown_view.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';

String _unifiedEditDiff(String oldText, String newText) {
  final a = oldText.split('\n');
  if (a.isNotEmpty && a.last.isEmpty) a.removeLast();
  final b = newText.split('\n');
  if (b.isNotEmpty && b.last.isEmpty) b.removeLast();
  final n = a.length;
  final m = b.length;
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <String>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(' ${a[i]}');
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add('-$a[i]');
      i++;
    } else {
      out.add('+$b[j]');
      j++;
    }
  }
  while (i < n) {
    out.add('-$a[i]');
    i++;
  }
  while (j < m) {
    out.add('+$b[j]');
    j++;
  }
  return out.join('\n');
}

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

const _expandableToolTypes = {
  'glob',
  'read',
  'edit',
  'todowrite',
  'write',
  'bash',
  'grep'
};

class _TodoItem {
  const _TodoItem({
    required this.content,
    required this.status,
    required this.priority,
  });

  final String content;
  final String status;
  final String priority;

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress' || status == 'inprogress';
  bool get isCancelled => status == 'cancelled' || status == 'canceled';
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo});

  final _TodoItem todo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final IconData icon;
    final Color color;
    if (todo.isCompleted) {
      icon = LucideIcons.check;
      color = Colors.green;
    } else if (todo.isCancelled) {
      icon = LucideIcons.x;
      color = theme.colorScheme.mutedForeground;
    } else if (todo.isInProgress) {
      icon = LucideIcons.loader;
      color = theme.colorScheme.primary;
    } else {
      icon = LucideIcons.circle;
      color = theme.colorScheme.mutedForeground;
    }
    final textColor = todo.isCompleted || todo.isCancelled
        ? theme.colorScheme.mutedForeground
        : theme.colorScheme.foreground;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: color),
        ),
        const Gap(8),
        Expanded(
          child: Text(
            todo.content,
            style: TextStyle(
              color: textColor,
              decoration: todo.isCompleted
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ).small,
        ),
        if (todo.priority.isNotEmpty) ...[
          const Gap(6),
          _TodoPriorityBadge(priority: todo.priority),
        ],
      ],
    );
  }
}

class _TodoPriorityBadge extends StatelessWidget {
  const _TodoPriorityBadge({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    switch (priority) {
      case 'high':
        color = Colors.red;
      case 'medium':
        color = Colors.orange;
      case 'low':
        color = Colors.green;
      default:
        color = theme.colorScheme.mutedForeground;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        priority,
        style: TextStyle(color: color),
      ).xSmall.semiBold,
    );
  }
}

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
      case 'grep':
        final pattern = input?['pattern'] as String? ?? '';
        final path =
            input?['path'] as String? ?? input?['glob'] as String? ?? '';
        if (pattern.isEmpty && path.isEmpty && output.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pattern.isNotEmpty) ...[
              _contentLabel('Pattern'),
              const Gap(4),
              _codeBlock(context, pattern),
            ],
            if (path.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Path'),
              const Gap(4),
              _codeBlock(context, path),
            ],
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
        final hasBoth = oldString.isNotEmpty && newString.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (filePath.isNotEmpty) ...[
              _contentLabel('File'),
              const Gap(4),
              _codeBlock(context, filePath),
            ],
            if (hasBoth) ...[
              const Gap(8),
              _contentLabel('Diff'),
              const Gap(4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: CodeHighlightView(
                    code: _unifiedEditDiff(oldString, newString),
                    language: 'diff',
                    fontSize: 12,
                  ),
                ),
              ),
            ] else ...[
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
        final theme = Theme.of(context);
        final todos = _parseTodos(todoContent);
        if (todos.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _contentLabel('Tasks'),
              const Gap(4),
              _codeBlock(context, todoContent, maxLines: 8),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _contentLabel('Tasks'),
                const Gap(6),
                Text('${todos.where((t) => t.status == 'completed').length}/${todos.length}')
                    .xSmall
                    .muted,
              ],
            ),
            const Gap(8),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.border.withAlpha(120),
                ),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < todos.length; i++) ...[
                    if (i > 0) const Gap(8),
                    _TodoRow(todo: todos[i]),
                  ],
                ],
              ),
            ),
          ],
        );
      case 'bash':
        final command =
            input?['command'] as String? ?? input?['cmd'] as String? ?? '';
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

  List<_TodoItem> _parseTodos(String raw) {
    String? text = raw.trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('{')) text = '[$text]';
    try {
      final decoded = jsonDecode(text);
      final list =
          decoded is List ? decoded : (decoded is Map ? [decoded] : null);
      if (list == null) return const [];
      return list.whereType<Map<String, dynamic>>().map((m) {
        final status = (m['status'] as String? ?? 'pending').toLowerCase();
        final priority = (m['priority'] as String? ?? '').toLowerCase();
        final content = (m['content'] as String? ??
                m['todo'] as String? ??
                m['text'] as String? ??
                m['title'] as String? ??
                '')
            .toString();
        return _TodoItem(
          content: content,
          status: status,
          priority: priority,
        );
      }).toList();
    } on FormatException {
      return const [];
    }
  }

  Widget _codeBlock(BuildContext context, String code, {int maxLines = 6}) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: 16.0 * maxLines + 20),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.border.withAlpha(120),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: theme.colorScheme.foreground,
            height: 1.5,
          ),
        ),
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
      constraints: const BoxConstraints(maxHeight: 116),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: theme.colorScheme.foreground,
            height: 1.5,
          ),
        ),
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

  void _showQuestionSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final rawState = widget.part.raw['state'];
    final stateMap = rawState is Map<String, dynamic> ? rawState : null;
    final output = stateMap?['output'] as String?;
    final isCompleted = widget.part.state == 'completed' ||
        widget.part.state == 'error' ||
        widget.part.state == 'timeout';

    final messageID = widget.part.raw['messageID'] as String?;
    final callID = widget.part.raw['callID'] as String?;
    final pendingQuestions = container.read(pendingQuestionsProvider);
    final question = pendingQuestions[messageID] ?? pendingQuestions[callID];

    final questions = question?.questions
            .map((q) => {
                  if (q.header != null) 'header': q.header,
                  'question': q.question,
                  'options': q.options
                      .map((o) => {
                            'label': o.label,
                            if (o.description != null)
                              'description': o.description,
                          })
                      .toList(),
                  'multiple': q.multiple,
                  'custom': q.custom,
                })
            .toList() ??
        _extractQuestions();

    final requestId = question?.id ?? '';
    final sessionID =
        question?.sessionID ?? (widget.part.raw['sessionID'] as String?) ?? '';

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
                requestId: requestId,
                sessionID: sessionID,
                toolName: widget.part.toolName ?? 'question',
                state: widget.part.state ?? '',
                messageKey: messageID ?? '',
                callKey: callID ?? '',
                answer: isCompleted ? output : null,
                isRunning: !isCompleted,
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

Widget _questionCard(
  BuildContext context,
  List<Map<String, dynamic>> questions,
  List<List<String>> selections,
  void Function(int, String) onSelect,
) {
  return Card(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var qi = 0; qi < questions.length; qi++)
          _questionItem(context, qi, questions, selections, onSelect),
      ],
    ),
  );
}

Widget _questionItem(
  BuildContext context,
  int qi,
  List<Map<String, dynamic>> questions,
  List<List<String>> selections,
  void Function(int, String) onSelect,
) {
  final q = questions[qi];
  final children = <Widget>[
    if (q['header'] is String) ...[
      Text(q['header'] as String).semiBold,
      const Gap(4),
    ],
    SelectableText((q['question'] as String?) ?? ''),
  ];
  if (q['options'] is List && (q['options'] as List).isNotEmpty) {
    children.add(const Gap(8));
    for (final opt in (q['options'] as List)) {
      if (opt is Map<String, dynamic>) {
        children.add(
          _QuestionOptionTile(
            label: (opt['label'] as String?) ?? '',
            description: opt['description'] as String?,
            selected: selections[qi].contains(opt['label']),
            onTap: () => onSelect(qi, opt['label'] as String),
          ),
        );
      } else if (opt is String) {
        children.add(
          _QuestionOptionTile(
            label: opt,
            selected: selections[qi].contains(opt),
            onTap: () => onSelect(qi, opt),
          ),
        );
      }
      children.add(const Gap(6));
    }
  } else if (q['custom'] == true) {
    children.add(const Gap(8));
    children.add(const Text('Free-form answer above.').xSmall.muted);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...children,
      if (qi != questions.length - 1) const Gap(12),
    ],
  );
}

class _QuestionOptionTile extends StatelessWidget {
  const _QuestionOptionTile({
    required this.label,
    this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.border;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withAlpha(18)
              : theme.colorScheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: selected ? 1.5 : 1),
        ),
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
                  Text(label).small.semiBold,
                  if (description != null && description!.isNotEmpty) ...[
                    const Gap(2),
                    Text(description!).xSmall.muted,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionSheetBody extends StatefulWidget {
  const _QuestionSheetBody({
    required this.questions,
    required this.requestId,
    required this.sessionID,
    required this.toolName,
    required this.state,
    required this.messageKey,
    required this.callKey,
    this.answer,
    this.isRunning = false,
  });

  final List<Map<String, dynamic>> questions;
  final String requestId;
  final String sessionID;
  final String toolName;
  final String state;
  final String messageKey;
  final String callKey;
  final String? answer;
  final bool isRunning;

  @override
  State<_QuestionSheetBody> createState() => _QuestionSheetBodyState();
}

class _QuestionSheetBodyState extends State<_QuestionSheetBody> {
  late final TextEditingController _controller;
  late List<List<String>> _selections;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _selections = List.generate(widget.questions.length, (_) => <String>[]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasOptions {
    return widget.questions.any(
      (q) => q['options'] is List && (q['options'] as List).isNotEmpty,
    );
  }

  bool get _canSubmit {
    if (_hasOptions) {
      return _selections.every((s) => s.isNotEmpty);
    }
    return _controller.text.trim().isNotEmpty;
  }

  String _resolveRequestId() {
    if (widget.requestId.isNotEmpty) return widget.requestId;
    final container = ProviderScope.containerOf(context);
    final pending = container.read(pendingQuestionsProvider);
    final byKey = pending[widget.messageKey] ?? pending[widget.callKey];
    return byKey?.id ?? '';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final requestId = _resolveRequestId();
    if (requestId.isEmpty) return;
    final container = ProviderScope.containerOf(context);
    final client = container.read(opencodeClientProvider);
    final answers = <List<String>>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      if (q['options'] is List && (q['options'] as List).isNotEmpty) {
        answers.add(_selections[i]);
      } else {
        answers.add([_controller.text.trim()]);
      }
    }
    await client
        ?.replyQuestion(requestId: requestId, answers: answers)
        .catchError((_) {});
    if (mounted) closeSheet(context);
  }

  Future<void> _reject() async {
    final container = ProviderScope.containerOf(context);
    final client = container.read(opencodeClientProvider);
    if (widget.requestId.isNotEmpty) {
      await client
          ?.rejectQuestion(requestId: widget.requestId)
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
                    _questionCard(context, widget.questions, _selections,
                        (qi, label) {
                      setState(() {
                        final multiple =
                            widget.questions[qi]['multiple'] == true;
                        if (multiple) {
                          if (_selections[qi].contains(label)) {
                            _selections[qi].remove(label);
                          } else {
                            _selections[qi].add(label);
                          }
                        } else {
                          _selections[qi] = [label];
                        }
                      });
                    })
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
                  else if (showInput && !_hasOptions)
                    TextArea(
                      controller: _controller,
                      placeholder: const Text('Type your answer…'),
                      minLines: 2,
                      maxLines: 6,
                    )
                  else if (!showInput)
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
              onPressed: _canSubmit ? _submit : null,
              child: const Text('Submit'),
            ),
            const Gap(8),
            DestructiveButton(
              onPressed: _reject,
              child: const Text('Reject'),
            ),
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
