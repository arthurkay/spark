import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/motion.dart';
import '../../shared/data_uri_cache.dart';
import '../../shared/haptics.dart';
import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/question_provider.dart';
import '../../core/models/message.dart';
import '../../core/models/question.dart';
import '../sessions/workspace_provider.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/code_highlight_view.dart';
import '../../shared/widgets/markdown_view.dart';
import '../../shared/widgets/sheet_keyboard_padding.dart';
import 'tts_provider.dart';
import 'tts_equalizer.dart';
import 'pdf_service.dart';
import 'package:printing/printing.dart';

/// Cache entry keyed by a cheap hash. The inputs are kept so a hash collision
/// is detected rather than silently rendering the wrong diff.
class _DiffCacheEntry {
  const _DiffCacheEntry(this.oldText, this.newText, this.result);

  final String oldText;
  final String newText;
  final String result;
}

/// LRU-ish cache of rendered diffs, evicting the oldest entry rather than
/// clearing wholesale (a full clear meant periodically re-paying the entire
/// diff cost for every visible edit chip).
final _diffCache = <int, _DiffCacheEntry>{};
const _diffCacheLimit = 64;

/// Upper bound on the LCS table. Beyond this the diff degrades to a
/// block-replacement view instead of blocking the UI thread for hundreds of
/// milliseconds — an O(n·m) dynamic-programming pass over a large file is not
/// something a frame can absorb.
const _maxDiffCells = 160000; // e.g. 400 x 400 changed lines

@visibleForTesting
String unifiedEditDiff(String oldText, String newText) {
  // Hash rather than concatenate: the old key allocated a copy of both texts on
  // every call, including on cache hits.
  final key = Object.hash(
    oldText.hashCode,
    newText.hashCode,
    oldText.length,
    newText.length,
  );
  final cached = _diffCache[key];
  if (cached != null &&
      cached.oldText == oldText &&
      cached.newText == newText) {
    return cached.result;
  }
  final result = _computeDiff(oldText, newText);
  if (_diffCache.length >= _diffCacheLimit) {
    _diffCache.remove(_diffCache.keys.first);
  }
  _diffCache[key] = _DiffCacheEntry(oldText, newText, result);
  return result;
}

String _computeDiff(String oldText, String newText) {
  final a = oldText.split('\n');
  if (a.isNotEmpty && a.last.isEmpty) a.removeLast();
  final b = newText.split('\n');
  if (b.isNotEmpty && b.last.isEmpty) b.removeLast();
  final n = a.length;
  final m = b.length;

  // Trim the identical head and tail first. Real edits touch a small region of
  // a file, so this usually shrinks the LCS problem from "whole file" to "the
  // few lines that changed".
  var pre = 0;
  while (pre < n && pre < m && a[pre] == b[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < n - pre && suf < m - pre && a[n - 1 - suf] == b[m - 1 - suf]) {
    suf++;
  }

  final aMid = n - pre - suf;
  final bMid = m - pre - suf;

  // Edit script: list of (type, aLine, bLine) with absolute line indices.
  // type: 'e' = equal, 'd' = delete, 'i' = insert
  final edits = <(String, int, int)>[];
  for (var k = 0; k < pre; k++) {
    edits.add(('e', k, k));
  }

  if (aMid * bMid > _maxDiffCells) {
    // Too large to align line-by-line within a frame budget: show the changed
    // region as a wholesale replacement.
    for (var k = 0; k < aMid; k++) {
      edits.add(('d', pre + k, -1));
    }
    for (var k = 0; k < bMid; k++) {
      edits.add(('i', -1, pre + k));
    }
  } else if (aMid > 0 || bMid > 0) {
    final lcs = List.generate(aMid + 1, (_) => Uint32List(bMid + 1));
    for (var i = aMid - 1; i >= 0; i--) {
      final rowI = lcs[i];
      final rowNext = lcs[i + 1];
      for (var j = bMid - 1; j >= 0; j--) {
        rowI[j] = a[pre + i] == b[pre + j]
            ? rowNext[j + 1] + 1
            : (rowNext[j] >= rowI[j + 1] ? rowNext[j] : rowI[j + 1]);
      }
    }

    var i = 0;
    var j = 0;
    while (i < aMid && j < bMid) {
      if (a[pre + i] == b[pre + j]) {
        edits.add(('e', pre + i, pre + j));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        edits.add(('d', pre + i, -1));
        i++;
      } else {
        edits.add(('i', -1, pre + j));
        j++;
      }
    }
    while (i < aMid) {
      edits.add(('d', pre + i, -1));
      i++;
    }
    while (j < bMid) {
      edits.add(('i', -1, pre + j));
      j++;
    }
  }

  for (var k = 0; k < suf; k++) {
    edits.add(('e', n - suf + k, m - suf + k));
  }

  // Mark changed regions (consecutive d/i edits)
  final changeRanges = <(int start, int end)>[];
  var idx = 0;
  while (idx < edits.length) {
    if (edits[idx].$1 != 'e') {
      final start = idx;
      while (idx < edits.length && edits[idx].$1 != 'e') idx++;
      changeRanges.add((start, idx));
    } else {
      idx++;
    }
  }

  // Build hunks with context
  const contextLines = 3;
  final hunkRanges = <(int changeStart, int changeEnd)>[];
  for (final (cs, ce) in changeRanges) {
    final hunkStart = (cs - contextLines).clamp(0, edits.length);
    final hunkEnd = (ce + contextLines).clamp(0, edits.length);
    if (hunkRanges.isNotEmpty && hunkStart <= hunkRanges.last.$2) {
      // Merge overlapping hunks
      hunkRanges[hunkRanges.length - 1] = (hunkRanges.last.$1, hunkEnd);
    } else {
      hunkRanges.add((hunkStart, hunkEnd));
    }
  }

  if (hunkRanges.isEmpty) {
    return '';
  }

  final out = <String>[];

  for (final (hStart, hEnd) in hunkRanges) {
    var oldLine = 0;
    var newLine = 0;
    // Compute starting line numbers for hunk header
    for (var k = 0; k < hStart; k++) {
      final e = edits[k];
      if (e.$1 == 'e') {
        oldLine++;
        newLine++;
      } else if (e.$1 == 'd') {
        oldLine++;
      } else {
        newLine++;
      }
    }

    // Count lines in this hunk for the header
    var oldCount = 0;
    var newCount = 0;
    for (var k = hStart; k < hEnd && k < edits.length; k++) {
      final e = edits[k];
      if (e.$1 == 'e') {
        oldCount++;
        newCount++;
      } else if (e.$1 == 'd') {
        oldCount++;
      } else {
        newCount++;
      }
    }

    out.add('@@ -$oldLine,$oldCount +$newLine,$newCount @@');

    for (var k = hStart; k < hEnd && k < edits.length; k++) {
      final e = edits[k];
      if (e.$1 == 'e') {
        out.add(' ${a[e.$2]}');
      } else if (e.$1 == 'd') {
        out.add('-${a[e.$2]}');
      } else {
        out.add('+${b[e.$3]}');
      }
    }
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
    final timestamp = message.info.timeCreated;
    final timeLabel = _formatTimestamp(timestamp);
    return GestureDetector(
      onLongPress: () {
        Haptics.longPress();
        _showContextMenu(context);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isUser ? LucideIcons.user : LucideIcons.sparkles,
              size: 15,
              color: theme.colorScheme.foreground,
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...children,
                if (timeLabel != null) ...[
                  const Gap(4),
                  Text(timeLabel).xSmall.muted,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatTimestamp(int? millis) {
    if (millis == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1)
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showContextMenu(BuildContext context) {
    final text = message.parts
        .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
        .map((p) => p.text!)
        .join('\n\n');
    if (text.isEmpty) return;
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
              const Text('Message actions').h4,
              const Gap(12),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  Clipboard.setData(ClipboardData(text: text));
                  showAppToast(context, title: 'Copied to clipboard');
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.copy, size: 16),
                    Gap(10),
                    Text('Copy text'),
                  ],
                ),
              ),
              const Gap(8),
              Consumer(
                builder: (context, ref, _) {
                  final tts = ref.watch(ttsStateProvider);
                  final isSpeaking = tts.status != TtsStatus.idle &&
                      tts.messageId == message.info.id;
                  final isPaused = tts.status == TtsStatus.paused && isSpeaking;
                  return GhostButton(
                    alignment: Alignment.centerLeft,
                    onPressed: () {
                      closeSheet(sheetContext);
                      ref.read(ttsStateProvider.notifier).toggle(message);
                    },
                    child: Row(
                      children: [
                        if (isSpeaking) ...[
                          TtsEqualizer(
                            isPlaying: !isPaused,
                            isPaused: isPaused,
                            height: 14,
                          ),
                          const Gap(8),
                        ] else ...[
                          Icon(LucideIcons.volume2, size: 16),
                          const Gap(10),
                        ],
                        Text(
                          isSpeaking ? 'Stop speaking' : 'Read aloud',
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Gap(8),
              GhostButton(
                alignment: Alignment.centerLeft,
                onPressed: () {
                  closeSheet(sheetContext);
                  _exportToPdf(context);
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.fileDown, size: 16),
                    Gap(10),
                    Text('Export as PDF'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToPdf(BuildContext context) async {
    final text = message.parts
        .where((p) => p.type == 'text' && (p.text?.trim().isNotEmpty ?? false))
        .map((p) => p.text!)
        .join('\n\n');
    if (text.isEmpty) {
      showAppToast(context, title: 'No content to export');
      return;
    }
    try {
      final bytes = await buildMessagePdf(message);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'message-${message.info.id}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, title: 'Failed to export PDF');
      }
    }
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
    final streaming = message.info.timeCompleted == null;
    switch (part.type) {
      case 'text':
        final text = part.text?.trim();
        if (text == null || text.isEmpty) return null;
        final isMarkdown = !streaming && _markdownHint.hasMatch(text);
        // While streaming, text renders unformatted and then flips to full
        // markdown (and syntax highlighting) the moment the message completes.
        // Cross-fading that swap turns an abrupt one-frame hitch into an
        // intentional-looking transition.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedSwitcher(
            duration: Motion.base,
            switchInCurve: Motion.standard,
            switchOutCurve: Motion.standard,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: isMarkdown
                ? MarkdownView(key: const ValueKey('md'), data: text)
                : KeyedSubtree(
                    key: const ValueKey('plain'),
                    child: _text(context, text),
                  ),
          ),
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
      // Keyed by part id: these are stateful and built from a positional list,
      // so without keys a part appended mid-stream shifts state (e.g. which
      // tool chip is expanded) onto the wrong tool.
      case 'tool':
        return _ToolChip(key: ValueKey(part.id), part: part);
      case 'file':
        return _FilePartWidget(key: ValueKey(part.id), part: part);
      default:
        return null;
    }
  }
}

/// Cheap test for "this text probably contains markdown". Compiled once —
/// building a RegExp inside `build` recompiled it on every frame.
final _markdownHint = RegExp(r'[`*_#>\n]|^\s*- ');

/// How many extra lines beyond the visible window to keep, so the inner scroll
/// view still has somewhere to scroll before hitting the truncation notice.
const _visibleLineAllowance = 8;

/// Trims [text] to at most [maxLines] lines, appending a note about what was
/// left out. Clipping the string — rather than only constraining the painted
/// height — is what keeps text layout cost bounded.
String _clipToLines(String text, int maxLines) {
  if (maxLines <= 0) return text;
  var count = 0;
  var index = 0;
  while (index < text.length) {
    final next = text.indexOf('\n', index);
    if (next == -1) return text;
    count++;
    if (count >= maxLines) {
      final omittedLines = text.substring(next + 1).split('\n').length;
      if (omittedLines <= 1) return text;
      return '${text.substring(0, next)}\n… $omittedLines more lines';
    }
    index = next + 1;
  }
  return text;
}

const _expandableToolTypes = {
  'glob',
  'read',
  'edit',
  'todowrite',
  'write',
  'bash',
  'grep',
  'task',
  'websearch',
  'webfetch',
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
  const _ToolChip({super.key, required this.part});

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

  /// Payloads above this size start collapsed. Small tool results still show
  /// inline as before — it's the large ones (whole-file reads, long build logs)
  /// that cost real frame time to lay out and are unreadable inline anyway.
  static const _autoExpandLimit = 4000;

  @override
  void initState() {
    super.initState();
    _expanded = _isExpandable && _output.length <= _autoExpandLimit;
  }

  Map<String, dynamic>? get _state =>
      widget.part.raw['state'] as Map<String, dynamic>?;

  // Parsed lazily and then cached: this getter is hit several times per build
  // and the raw form is often a JSON string.
  Map<String, dynamic>? _inputCache;
  bool _inputParsed = false;
  Map<String, dynamic>? get _input {
    if (_inputParsed) return _inputCache;
    _inputParsed = true;
    final raw = _state?['input'];
    if (raw is Map<String, dynamic>) {
      _inputCache = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) _inputCache = parsed;
      } catch (_) {}
    }
    return _inputCache;
  }

  String get _output => (_state?['output'] as String?) ?? '';

  @override
  void didUpdateWidget(_ToolChip old) {
    super.didUpdateWidget(old);
    // The part object is replaced as the tool streams its result; drop memoized
    // derivations so they are recomputed from the new payload.
    if (!identical(old.part, widget.part)) {
      _inputParsed = false;
      _inputCache = null;
      _todoCache = null;
      _todoCacheKey = null;
    }
  }

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
                    code: unifiedEditDiff(oldString, newString),
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
      case 'task':
        final description = input?['description'] as String? ?? '';
        final prompt = input?['prompt'] as String? ?? '';
        if (description.isEmpty && prompt.isEmpty && output.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (description.isNotEmpty) ...[
              _contentLabel('Description'),
              const Gap(4),
              _codeBlock(context, description),
            ],
            if (prompt.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Prompt'),
              const Gap(4),
              _codeBlock(context, prompt, maxLines: 8),
            ],
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Result'),
              const Gap(4),
              _codeBlock(context, output, maxLines: 12),
            ],
          ],
        );
      case 'websearch':
        final query = input?['query'] as String? ?? '';
        if (query.isEmpty && output.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (query.isNotEmpty) ...[
              _contentLabel('Query'),
              const Gap(4),
              _codeBlock(context, query),
            ],
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Results'),
              const Gap(4),
              _codeBlock(context, output, maxLines: 12),
            ],
          ],
        );
      case 'webfetch':
        final url = input?['url'] as String? ?? '';
        final format = input?['format'] as String? ?? '';
        if (url.isEmpty && output.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (url.isNotEmpty) ...[
              _contentLabel('URL'),
              const Gap(4),
              _codeBlock(context, url),
            ],
            if (format.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Format'),
              const Gap(4),
              _codeBlock(context, format),
            ],
            if (output.isNotEmpty) ...[
              const Gap(8),
              _contentLabel('Content'),
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

  List<_TodoItem>? _todoCache;
  String? _todoCacheKey;

  List<_TodoItem> _parseTodos(String raw) {
    // jsonDecode per build is wasted work; the payload only changes when the
    // part does (handled in didUpdateWidget).
    if (_todoCacheKey == raw && _todoCache != null) return _todoCache!;
    final parsed = _parseTodosUncached(raw);
    _todoCacheKey = raw;
    _todoCache = parsed;
    return parsed;
  }

  List<_TodoItem> _parseTodosUncached(String raw) {
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
    // maxHeight only clips what is *painted*; the full string is still laid
    // out. Cut the string so a 200KB command output doesn't cost a full text
    // layout on every build.
    final display = _clipToLines(code, maxLines * _visibleLineAllowance);
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
          display,
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
                    // Rotates between states instead of swapping glyphs, so
                    // expanding reads as one continuous motion.
                    AnimatedRotation(
                      turns: _expanded || !_isTappable ? 0.25 : 0,
                      duration: Motion.base,
                      curve: Motion.standard,
                      child: const Icon(LucideIcons.chevronRight, size: 12)
                          .iconMutedForeground,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Always present so the expand/collapse actually animates; guarding
          // the AnimatedSize itself meant it was built at full size.
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.inOut,
            alignment: Alignment.topCenter,
            child: _expanded && hasContent
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildContentPreview(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
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
    final callID = (widget.part.raw['callID'] as String?) ?? widget.part.id;
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
                callKey: callID,
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

class _QuestionSheetBody extends ConsumerStatefulWidget {
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
  ConsumerState<_QuestionSheetBody> createState() => _QuestionSheetBodyState();
}

class _QuestionSheetBodyState extends ConsumerState<_QuestionSheetBody> {
  late final TextEditingController _controller;
  late List<List<String>> _selections;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _selections = List.generate(widget.questions.length, (_) => <String>[]);
  }

  @override
  void didUpdateWidget(_QuestionSheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questions.length != widget.questions.length) {
      _selections = List.generate(widget.questions.length, (_) => <String>[]);
    }
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
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      if (q['options'] is List && (q['options'] as List).isNotEmpty) {
        if (i >= _selections.length || _selections[i].isEmpty) return false;
      } else {
        if (_controller.text.trim().isEmpty) return false;
      }
    }
    if (widget.questions.isEmpty) {
      return _controller.text.trim().isNotEmpty;
    }
    return true;
  }

  QuestionRequest? _findQuestion() {
    final pending = ref.read(pendingQuestionsProvider);
    return pending[widget.messageKey] ??
        pending[widget.callKey] ??
        pending[widget.requestId];
  }

  String? _resolveDirectory() {
    return _findQuestion()?.directory;
  }

  String _resolveRequestId() {
    if (widget.requestId.isNotEmpty) return widget.requestId;
    return _findQuestion()?.id ?? '';
  }

  Future<String> _resolveRequestIdWithFetch() async {
    final id = _resolveRequestId();
    if (id.isNotEmpty) return id;
    final client = ref.read(opencodeClientProvider);
    if (client == null) return '';
    try {
      final requests = await client.listQuestions();
      for (final r in requests) {
        if (r.messageID == widget.messageKey ||
            r.callID == widget.callKey ||
            r.id == widget.requestId) {
          return r.id;
        }
      }
      final projects = await ref.read(projectsProvider.future);
      for (final project in projects) {
        if (project.isGlobal) continue;
        try {
          for (final r
              in await client.listQuestions(directory: project.worktree)) {
            if (r.messageID == widget.messageKey ||
                r.callID == widget.callKey ||
                r.id == widget.requestId) {
              return r.id;
            }
          }
        } on OpencodeApiException {
          // Ignore per-project errors.
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final requestId = await _resolveRequestIdWithFetch();
    if (requestId.isEmpty) {
      if (mounted) {
        showAppToast(context,
            title: 'Question not received from server. Try again.');
      }
      return;
    }
    final client = ref.read(opencodeClientProvider);
    final answers = <List<String>>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      if (q['options'] is List && (q['options'] as List).isNotEmpty) {
        answers.add(i < _selections.length ? _selections[i] : <String>[]);
      } else {
        answers.add([_controller.text.trim()]);
      }
    }
    try {
      await client?.replyQuestion(
        requestId: requestId,
        answers: answers,
        directory: _resolveDirectory(),
      );
      if (mounted) closeSheet(context);
    } on OpencodeApiException catch (e) {
      if (mounted) {
        showAppToast(context, title: 'Failed to submit: ${e.message}');
      }
    }
  }

  Future<void> _reject() async {
    final requestId = await _resolveRequestIdWithFetch();
    if (requestId.isEmpty) {
      if (mounted) {
        showAppToast(context,
            title: 'Question not received from server. Try again.');
      }
      return;
    }
    final client = ref.read(opencodeClientProvider);
    try {
      await client?.rejectQuestion(
        requestId: requestId,
        directory: _resolveDirectory(),
      );
      if (mounted) closeSheet(context);
    } on OpencodeApiException catch (e) {
      if (mounted) {
        showAppToast(context, title: 'Failed to reject: ${e.message}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pendingQuestionsProvider);
    final resolvedId = _resolveRequestId();
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
              child: Text(resolvedId.isNotEmpty
                  ? 'Submit'
                  : 'Submit (waiting for server…)'),
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

/// Inline attachments render at a fixed width.
const _imageWidth = 300.0;

class _FilePartWidget extends StatelessWidget {
  const _FilePartWidget({super.key, required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final url = part.raw['url'] as String? ?? '';
    final mime = part.raw['mime'] as String? ?? '';
    final filename = part.raw['filename'] as String? ?? 'file';
    final isImage = mime.startsWith('image/') && url.isNotEmpty;
    final isSvg = mime == 'image/svg+xml' || url.startsWith('data:image/svg');
    final theme = Theme.of(context);

    final cacheWidth = decodeWidthFor(
      _imageWidth,
      MediaQuery.devicePixelRatioOf(context),
    );

    if (isSvg) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        child: _buildSvgWidget(url, filename, theme),
      );
    }

    if (isImage) {
      if (url.startsWith('data:')) {
        return Container(
          margin: const EdgeInsets.only(top: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildDataImage(url, filename, mime, theme, cacheWidth),
          ),
        );
      }
      return Container(
        margin: const EdgeInsets.only(top: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            width: _imageWidth,
            cacheWidth: cacheWidth,
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

  Widget _buildSvgWidget(String url, String filename, ThemeData theme) {
    if (url.startsWith('data:')) {
      final decoded = DataUriCache.textOf(url);
      if (decoded == null) {
        return _FileChip(
            filename: filename, mime: 'image/svg+xml', theme: theme);
      }
      return SvgPicture.string(
        decoded,
        width: _imageWidth,
        fit: BoxFit.contain,
      );
    }
    return SvgPicture.network(
      url,
      width: _imageWidth,
      fit: BoxFit.contain,
      placeholderBuilder: (_) =>
          _FileChip(filename: filename, mime: 'image/svg+xml', theme: theme),
    );
  }

  Widget _buildDataImage(
    String url,
    String filename,
    String mime,
    ThemeData theme,
    int cacheWidth,
  ) {
    // Cached bytes, so the same list instance is handed to Image.memory on every
    // build and the image cache actually hits.
    final bytes = DataUriCache.bytesOf(url);
    if (bytes == null) {
      return _FileChip(filename: filename, mime: mime, theme: theme);
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      width: _imageWidth,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => _FileChip(
        filename: filename,
        mime: mime,
        theme: theme,
      ),
    );
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
