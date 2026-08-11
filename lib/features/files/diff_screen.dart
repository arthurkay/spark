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
      orElse: () => throw StateError('no assistant message'),
    );
    final perMessage = await client.sessionDiff(
      sessionId,
      messageId: assistant.info.id,
    );
    if (perMessage.isNotEmpty) return perMessage;
  } on OpencodeApiException catch (_) {
  } on StateError catch (_) {}
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
          final totalAdd = diffs.fold(0, (s, d) => s + d.additions);
          final totalDel = diffs.fold(0, (s, d) => s + d.deletions);
          final combined = diffs
              .map((d) => d.displayPatch)
              .where((p) => p.isNotEmpty)
              .join('\n\n');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${diffs.length} file${diffs.length == 1 ? '' : 's'} changed',
                        ).semiBold.small,
                        const Gap(8),
                        Text(
                          '+$totalAdd',
                          style: const TextStyle(
                            color: Color(0xff22c55e),
                            fontWeight: FontWeight.w600,
                          ),
                        ).xSmall,
                        const Gap(8),
                        Text(
                          '-$totalDel',
                          style: const TextStyle(
                            color: Color(0xffef4444),
                            fontWeight: FontWeight.w600,
                          ),
                        ).xSmall,
                      ],
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final d in diffs)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .muted
                                  .withAlpha(40),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(d.file).xSmall.muted,
                          ),
                      ],
                    ),
                    const Gap(8),
                    const Divider(),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: CodeHighlightView(
                    code: combined,
                    language: 'diff',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
