import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/models/message.dart';
import '../../shared/widgets/markdown_view.dart';

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
            color: _isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.muted,
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
      default:
        return null;
    }
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final name = part.toolName ?? 'tool';
    final status = part.state ?? '';
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.wrench, size: 13),
          const Gap(8),
          Text(name).small.semiBold,
          if (status.isNotEmpty) ...[const Gap(6), Text(status).muted.xSmall],
        ],
      ),
    );
  }
}
