import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/file_node.dart';
import '../../shared/widgets/code_highlight_view.dart';

final _diffProvider = FutureProvider.family<List<FileDiff>, String>((
  ref,
  sessionId,
) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return [];
  final diffs = await client.sessionDiff(sessionId);
  if (diffs.isNotEmpty) return diffs;
  try {
    final messages = await client.listMessages(sessionId);
    final assistant = messages.lastWhere(
      (m) => m.info.role == 'assistant' && m.info.id.isNotEmpty,
    );
    final perMessage = await client.sessionDiff(
      sessionId,
      messageId: assistant.info.id,
    );
    if (perMessage.isNotEmpty) return perMessage;
  } on OpencodeApiException catch (_) {}
  return diffs;
});

class DiffScreen extends ConsumerWidget {
  const DiffScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diffAsync = ref.watch(_diffProvider(sessionId));
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          title: const Text('Changes'),
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () => ref.invalidate(_diffProvider(sessionId)),
            ),
          ],
        ),
      ],
      child: diffAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e is OpencodeApiException ? e.message : '$e').muted,
        ),
        data: (diffs) {
          if (diffs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('No changes detected for this session').muted,
                  const Gap(4),
                  Text(
                    'Changes appear once the session edits files in its project.',
                  ).muted.xSmall,
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: diffs.length,
            separatorBuilder: (context, index) => const Gap(12),
            itemBuilder: (context, index) => _DiffCard(diff: diffs[index]),
          );
        },
      ),
    );
  }
}

class _DiffCard extends StatelessWidget {
  const _DiffCard({required this.diff});

  final FileDiff diff;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  diff.file,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).semiBold.small,
              ),
              const Gap(8),
              if (diff.additions > 0 || diff.deletions > 0)
                Text('+${diff.additions} -${diff.deletions}').muted.xSmall,
            ],
          ),
          const Gap(8),
          const Divider(),
          const Gap(8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _DiffText(patch: diff.displayPatch, path: diff.file),
          ),
        ],
      ),
    );
  }
}

class _DiffText extends StatelessWidget {
  const _DiffText({required this.patch, this.path});

  final String patch;
  final String? path;

  @override
  Widget build(BuildContext context) {
    return CodeHighlightView(code: patch, language: 'diff', fontSize: 12);
  }
}
