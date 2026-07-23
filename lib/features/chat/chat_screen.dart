import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/model_selector.dart';
import '../models/models_provider.dart';
import '../permissions/permission_banner.dart';
import '../../core/api/connectivity_provider.dart';
import '../../core/api/providers.dart';
import '../../core/models/attachment.dart';
import '../../core/notifications/notification_service.dart';
import '../../shared/widgets/path_utils.dart';
import 'chat_provider.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Attachment> _attachments = [];
  bool _showScrollToBottom = false;
  late final AnimationController _workingAnimController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    NotificationService.instance.requestPermission();
    _workingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < 200) {
      final controller = ref.read(
        chatControllerProvider(widget.sessionId).notifier,
      );
      controller.loadOlder();
    }
    final nearBottom = position.maxScrollExtent - position.pixels < 120;
    if (nearBottom != _showScrollToBottom) {
      setState(() => _showScrollToBottom = !nearBottom);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _composerController.dispose();
    _scrollController.dispose();
    _workingAnimController.dispose();
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFromExtension(ext);
      setState(() {
        _attachments.add(Attachment(
          name: name,
          path: file.path ?? name,
          mime: mime,
          bytes: bytes,
        ));
      });
    }
  }

  String _mimeFromExtension(String ext) {
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'txt' || 'md' || 'markdown' => 'text/plain',
      'dart' ||
      'js' ||
      'ts' ||
      'py' ||
      'rb' ||
      'go' ||
      'rs' ||
      'java' ||
      'kt' ||
      'swift' ||
      'c' ||
      'cpp' ||
      'h' ||
      'cs' ||
      'sh' ||
      'bash' ||
      'zsh' ||
      'yaml' ||
      'yml' ||
      'toml' ||
      'xml' ||
      'html' ||
      'css' ||
      'scss' ||
      'sql' ||
      'csv' =>
        'text/plain',
      _ => 'application/octet-stream',
    };
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _send() async {
    final text = _composerController.text;
    if (text.trim().isEmpty && _attachments.isEmpty) return;
    final attachments = List<Attachment>.from(_attachments);
    setState(() => _attachments.clear());
    _composerController.clear();
    final model = ref.read(selectedModelProvider);
    final userAgent = ref.read(selectedAgentProvider);
    final agent = userAgent ?? ref.read(defaultAgentProvider) ?? 'build';
    await ref.read(chatControllerProvider(widget.sessionId).notifier).send(
          text,
          model: model,
          agent: agent,
          attachments: attachments,
        );
    _scrollToBottom();
  }

  int _lastMessageCount = 0;
  bool _initialScrollDone = false;

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 120;
  }

  bool get _isScrollable {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.maxScrollExtent > 40;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(chatControllerProvider(widget.sessionId));
    final state = controller.state;

    final count = state.messages.length;
    if (count != _lastMessageCount || (!_initialScrollDone && count > 0)) {
      _lastMessageCount = count;
      if (!_initialScrollDone && count > 0) {
        _initialScrollDone = true;
        _scrollToBottom(animate: false);
      } else if (_isNearBottom) {
        _scrollToBottom();
      }
    }
    final shouldShow = _isScrollable && !_isNearBottom;
    if (shouldShow != _showScrollToBottom) {
      _showScrollToBottom = shouldShow;
    }

    final currentModel = ref.watch(currentModelProvider(widget.sessionId));
    final currentAgent = ref.watch(currentModeProvider(widget.sessionId));
    final globalBusy =
        ref.watch(sessionActivityProvider).contains(widget.sessionId);
    final working = (state.working || globalBusy) && !state.aborting;
    final agentLabel = currentAgent;
    final subtitleParts = [
      if (working) 'working...',
      if (currentModel != null) currentModel,
      if (agentLabel != null) agentLabel,
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
          title: Builder(
            builder: (context) {
              final workspaceAsync =
                  ref.watch(sessionDirectoryProvider(widget.sessionId));
              final workspaceName = workspaceAsync.maybeWhen(
                data: (v) => v,
                orElse: () => null,
              );
              return workspaceName != null && workspaceName.isNotEmpty
                  ? Text(
                      compactPath(workspaceName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink();
            },
          ),
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
            // IconButton.ghost(
            //   icon: const Icon(LucideIcons.settings),
            //   onPressed: () =>
            //       context.push('/session/${widget.sessionId}/diff'),
            // ),
          ],
        ),
      ],
      resizeToAvoidBottomInset: true,
      child: Column(
        children: [
          Expanded(child: _buildBody(state, working: working)),
          const PermissionBanner(),
          _Composer(
            sessionId: widget.sessionId,
            controller: _composerController,
            sending: state.sending,
            working: working,
            aborting: state.aborting,
            error: state.error,
            attachments: _attachments,
            onPickFiles: _pickFiles,
            onRemoveAttachment: _removeAttachment,
            onSend: _send,
            onAbort: controller.abort,
            onDismiss: controller.dismissStuck,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _workingAnimController,
            builder: (context, child) {
              final t = (_workingAnimController.value - i * 0.15) % 1.0;
              final opacity = t < 0.5
                  ? (t * 2).clamp(0.2, 1.0)
                  : (2 - t * 2).clamp(0.2, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .mutedForeground
                      .withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _buildBody(ChatState state, {required bool working}) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.triangleAlert, size: 40)
                  .iconMutedForeground,
              const Gap(12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  state.error!,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ).muted,
              ),
            ],
          ),
        ),
      );
    }
    final visible = state.messages
        .where(
          (m) => m.parts.any(
            (p) =>
                (p.type == 'text' && (p.text?.trim().isNotEmpty ?? false)) ||
                p.type == 'tool' ||
                p.type == 'reasoning' ||
                p.type == 'file',
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
    final itemCount = visible.length + (hasHeader ? 1 : 0) + (working ? 1 : 0);
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
    return Stack(
      children: [
        Center(
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
                if (working && index == itemCount - 1) {
                  return _buildWorkingIndicator();
                }
                return RepaintBoundary(
                  child: MessageBubble(
                    key: ValueKey(visible[messageIndex].info.id),
                    message: visible[messageIndex],
                  ),
                );
              },
            ),
          ),
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 16,
            bottom: 16,
            child: IconButton.primary(
              icon: const Icon(LucideIcons.arrowDown, size: 18),
              onPressed: () => _scrollToBottom(),
            ),
          ),
      ],
    );
  }
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.sessionId,
    required this.controller,
    required this.sending,
    required this.working,
    required this.aborting,
    required this.error,
    required this.attachments,
    required this.onPickFiles,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onAbort,
    required this.onDismiss,
  });

  final String sessionId;
  final TextEditingController controller;
  final bool sending;
  final bool working;
  final bool aborting;
  final String? error;
  final List<Attachment> attachments;
  final VoidCallback onPickFiles;
  final void Function(int index) onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onAbort;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _textBeforeListening = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (_) => _stopListening(),
    );
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _stopListening();
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      _stopListening();
      return;
    }
    if (!_speechAvailable) {
      await _initSpeech();
      if (!_speechAvailable) return;
    }
    _textBeforeListening = widget.controller.text;
    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          final base = _textBeforeListening;
          final suffix = base.isNotEmpty && !base.endsWith(' ') ? ' ' : '';
          setState(() {
            widget.controller.text = '$base$suffix${result.recognizedWords}';
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          });
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
      ),
    );
    setState(() => _isListening = true);
  }

  void _stopListening() {
    _speech.stop();
    if (_isListening) setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
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
                  Expanded(
                      child: ModelSelectorBar(sessionId: widget.sessionId)),
                ],
              ),
              if (!ref.watch(connectivityProvider)) ...[
                const Gap(4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.wifiOff,
                          size: 12, color: Colors.orange),
                      const Gap(4),
                      Text('Offline — messages will be queued').xSmall,
                    ],
                  ),
                ),
              ],
              if (widget.error != null) ...[
                const Gap(8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.triangleAlert,
                          size: 14, color: Colors.red),
                      const Gap(6),
                      Expanded(
                        child: Text(widget.error!).xSmall,
                      ),
                      TextButton(
                        onPressed: widget.onDismiss,
                        child: const Text('Dismiss').xSmall,
                      ),
                      TextButton(
                        onPressed: widget.onAbort,
                        child: const Text('Abort session').xSmall,
                      ),
                    ],
                  ),
                ),
              ],
              const Gap(10),
              if (widget.attachments.isNotEmpty) ...[
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.attachments.length,
                    separatorBuilder: (_, __) => const Gap(6),
                    itemBuilder: (context, index) {
                      final a = widget.attachments[index];
                      return _AttachmentChip(
                        attachment: a,
                        onRemove: () => widget.onRemoveAttachment(index),
                      );
                    },
                  ),
                ),
                const Gap(8),
              ],
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton.ghost(
                      icon: const Icon(LucideIcons.paperclip, size: 18),
                      size: ButtonSize.small,
                      onPressed: widget.onPickFiles,
                    ),
                    if (_speechAvailable)
                      IconButton.ghost(
                        icon: _isListening
                            ? const Icon(LucideIcons.circleDot,
                                size: 18, color: Colors.red)
                            : const Icon(LucideIcons.mic, size: 18),
                        size: ButtonSize.small,
                        onPressed: _toggleListening,
                      ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        placeholder: const Text('Message SparkCode...'),
                        border: Border.all(color: Colors.transparent),
                        borderRadius: BorderRadius.zero,
                        maxLines: 5,
                        minLines: 1,
                        onSubmitted: (_) => widget.onSend(),
                      ),
                    ),
                    const Gap(4),
                    if (widget.working ||
                        widget.aborting ||
                        widget.error != null)
                      IconButton.destructive(
                        icon: const Icon(LucideIcons.square),
                        size: ButtonSize.small,
                        onPressed: widget.onAbort,
                      )
                    else
                      IconButton.primary(
                        icon: widget.sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.arrowUp),
                        size: ButtonSize.small,
                        onPressed: widget.sending ? null : widget.onSend,
                      ),
                  ],
                ),
              ),
              if (_isListening) ...[
                const Gap(6),
                Row(
                  children: [
                    const Icon(LucideIcons.circleDot,
                        size: 12, color: Colors.red),
                    const Gap(6),
                    Text('Listening...').xSmall.muted,
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.isImage ? LucideIcons.image : LucideIcons.file,
            size: 14,
            color: theme.colorScheme.mutedForeground,
          ),
          const Gap(6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small,
          ),
          const Gap(4),
          Text(attachment.sizeLabel).xSmall.muted,
          const Gap(2),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              LucideIcons.x,
              size: 12,
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
