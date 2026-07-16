import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../models/model_selector.dart';
import '../models/models_provider.dart';
import '../permissions/permission_sheet.dart';
import '../permissions/permission_banner.dart';
import '../../core/api/providers.dart';
import '../../core/notifications/notification_service.dart';
import 'chat_provider.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    NotificationService.instance.requestPermission();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels < 200) {
      final controller = ref.read(
        chatControllerProvider(widget.sessionId).notifier,
      );
      controller.loadOlder();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    });
  }

  Future<void> _send() async {
    final text = _composerController.text;
    if (text.trim().isEmpty) return;
    _composerController.clear();
    final model = ref.read(selectedModelProvider);
    final mode = ref.read(sessionModeProvider);
    final agent = mode == 'plan'
        ? 'plan'
        : ref.read(selectedAgentProvider) ?? 'build';
    await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(text, model: model, agent: agent);
    _scrollToBottom();
  }

  String? _shownPermissionId;
  int _lastMessageCount = 0;
  bool _initialScrollDone = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(chatControllerProvider(widget.sessionId));
    final state = controller.state;

    final permission = state.pendingPermission;
    if (permission != null && permission.id != _shownPermissionId) {
      _shownPermissionId = permission.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showPermissionSheet(
          context: context,
          permission: permission,
          onRespond: (response, remember) =>
              controller.respondPermission(response, remember: remember),
        );
      });
    }
    final count = state.messages.length;
    if (count != _lastMessageCount || (!_initialScrollDone && count > 0)) {
      _lastMessageCount = count;
      if (!_initialScrollDone && count > 0) {
        _initialScrollDone = true;
        _scrollToBottom(animate: false);
      } else {
        _scrollToBottom();
      }
    }

    final currentModel = ref.watch(currentModelProvider(widget.sessionId));
    final currentMode = ref.watch(currentModeProvider(widget.sessionId));
    final globalBusy = ref
        .watch(sessionActivityProvider)
        .contains(widget.sessionId);
    final working = state.working || globalBusy;
    final modeLabel = currentMode == 'plan'
        ? 'plan mode'
        : (currentMode == 'build' ? 'build mode' : null);
    final subtitleParts = [
      if (working) 'working...',
      if (currentModel != null) currentModel,
      if (modeLabel != null) modeLabel,
    ];

    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
          ],
          subtitle: subtitleParts.isNotEmpty
              ? DefaultTextStyle(
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.mutedForeground,
                    fontSize: 13,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitleParts.join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          trailing: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.folderTree),
              onPressed: () =>
                  context.push('/session/${widget.sessionId}/files'),
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.settings),
              onPressed: () =>
                  context.push('/session/${widget.sessionId}/diff'),
            ),
          ],
        ),
      ],
      resizeToAvoidBottomInset: true,
      child: Column(
        children: [
          Expanded(child: _buildBody(state)),
          const PermissionBanner(),
          _Composer(
            sessionId: widget.sessionId,
            controller: _composerController,
            sending: state.sending,
            working: working,
            onSend: _send,
            onAbort: controller.abort,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.triangleAlert, size: 40).iconMutedForeground,
            const Gap(12),
            Text(state.error!).muted.textCenter,
          ],
        ),
      );
    }
    final visible = state.messages
        .where(
          (m) => m.parts.any(
            (p) =>
                (p.type == 'text' && (p.text?.trim().isNotEmpty ?? false)) ||
                p.type == 'tool' ||
                p.type == 'reasoning',
          ),
        )
        .toList();
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.messagesSquare,
              size: 44,
            ).iconMutedForeground,
            const Gap(16),
            const Text('How can I help?').h3,
            const Gap(6),
            const Text(
              'Send a message to start the conversation.',
            ).muted.textCenter,
          ],
        ),
      );
    }
    final hasHeader =
        state.loadingOlder || (state.hasMoreOlder && visible.isNotEmpty);
    final itemCount = visible.length + (hasHeader ? 1 : 0);
    Widget? header;
    if (state.loadingOlder) {
      header = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (state.hasMoreOlder && visible.isNotEmpty) {
      header = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: const Text('Scroll up to load earlier messages').muted.small,
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: itemCount,
          separatorBuilder: (context, index) => const Gap(24),
          itemBuilder: (context, index) {
            if (hasHeader && index == 0) return header!;
            final messageIndex = hasHeader ? index - 1 : index;
            return MessageBubble(
              key: ValueKey(visible[messageIndex].info.id),
              message: visible[messageIndex],
            );
          },
        ),
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  const _Composer({
    required this.sessionId,
    required this.controller,
    required this.sending,
    required this.working,
    required this.onSend,
    required this.onAbort,
  });

  final String sessionId;
  final TextEditingController controller;
  final bool sending;
  final bool working;
  final VoidCallback onSend;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        border: Border(
          top: BorderSide(color: theme.colorScheme.border, width: 1),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const ModeToggle(),
                  const Spacer(),
                  Expanded(child: ModelSelectorBar(sessionId: sessionId)),
                ],
              ),
              const Gap(10),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        placeholder: const Text('Message opencode...'),
                        border: null,
                        borderRadius: BorderRadius.zero,
                        maxLines: 5,
                        minLines: 1,
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    const Gap(4),
                    if (working)
                      IconButton.destructive(
                        icon: const Icon(LucideIcons.square),
                        size: ButtonSize.small,
                        onPressed: onAbort,
                      )
                    else
                      IconButton.primary(
                        icon: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.arrowUp),
                        size: ButtonSize.small,
                        onPressed: sending ? null : onSend,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
