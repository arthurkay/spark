import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/model_selector.dart';
import '../models/models_provider.dart';
import '../permissions/permission_banner.dart';
import '../sessions/workspace_provider.dart';
import '../../app/motion.dart';
import '../../core/api/connectivity_provider.dart';
import '../../core/api/providers.dart';
import '../../core/models/attachment.dart';
import '../../core/notifications/notification_service.dart';
import '../../shared/debouncer.dart';
import '../../shared/haptics.dart';
import '../terminal/terminal_sheet.dart';
import 'chat_provider.dart';
import 'message_bubble.dart';

/// How close to the bottom counts as "following the conversation".
const _nearBottomSlack = 120.0;

/// Maps a row of the bottom-anchored transcript to a message id.
///
/// The list runs `reverse: true`, so row 0 is the *newest* message and the
/// highest row is the oldest. Returns null for any row past the messages, which
/// is where the load-older header goes.
String? transcriptIdForRow(List<String> ids, int row) {
  if (row < 0 || row >= ids.length) return null;
  return ids[ids.length - 1 - row];
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();

  /// Persists the composer as you type.
  ///
  /// Saving only in [dispose] lost the draft whenever the process was killed
  /// rather than navigated away from — swipe the app away, or let Android
  /// reclaim it, and dispose never runs. Writing shortly after each keystroke
  /// means the draft is already on disk before the app is ever backgrounded.
  final _draftDebouncer = Debouncer(delay: const Duration(milliseconds: 400));
  // A ValueNotifier rather than screen state: attachments render inside the
  // composer, so editing them must not rebuild the message transcript.
  final _attachments = ValueNotifier<List<Attachment>>(const []);
  final _showScrollToBottom = ValueNotifier<bool>(false);
  late final AnimationController _workingAnimController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _composerController.addListener(_onComposerChanged);
    NotificationService.instance.requestPermission();
    _loadDraft();
    _workingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // dispose() disposes _showScrollToBottom, so leaving the chat within a
      // frame of opening it would write to a disposed notifier.
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _showScrollToBottom.value = !_isNearBottom;
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Reversed: the oldest messages are at maxScrollExtent, so that end is
    // where "scrolled back far enough to load more" happens.
    if (position.maxScrollExtent - position.pixels < 200) {
      final controller = ref.read(
        chatControllerProvider(widget.sessionId).notifier,
      );
      controller.loadOlder();
    }
    _showScrollToBottom.value = !_isNearBottom;
  }

  void _onComposerChanged() => _draftDebouncer.run(_saveDraft);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      // Write anything typed in the last few hundred milliseconds before the
      // process is at risk of being killed.
      _draftDebouncer.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composerController.removeListener(_onComposerChanged);
    _draftDebouncer.dispose();
    _saveDraft();
    _scrollController.removeListener(_onScroll);
    _composerController.dispose();
    _scrollController.dispose();
    _workingAnimController.dispose();
    _showScrollToBottom.dispose();
    _attachments.dispose();
    super.dispose();
  }

  static String _draftKey(String sessionId) => 'draft_$sessionId';

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString(_draftKey(widget.sessionId));
    if (draft != null && draft.isNotEmpty) {
      _composerController.text = draft;
    }
  }

  Future<void> _saveDraft() async {
    final text = _composerController.text;
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      await prefs.remove(_draftKey(widget.sessionId));
    } else {
      await prefs.setString(_draftKey(widget.sessionId), text);
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey(widget.sessionId));
  }

  /// Returns the transcript to the newest content.
  ///
  /// Only for discrete, user-perceived events — a message was sent, the
  /// scroll-to-bottom button was tapped. Streaming growth needs no scrolling at
  /// all now: the list is bottom-anchored, so a growing tail extends away from
  /// offset 0 and the viewport stays exactly where it is.
  void _pinToBottom({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.pixels == 0) return;
      if (animate) {
        _scrollController.animateTo(
          0,
          duration: Motion.base,
          curve: Motion.standard,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final added = <Attachment>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      final name = file.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mime = _mimeFromExtension(ext);
      added.add(Attachment(
        name: name,
        path: file.path ?? name,
        mime: mime,
        bytes: bytes,
      ));
    }
    if (added.isEmpty) return;
    _attachments.value = [..._attachments.value, ...added];
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
    final next = [..._attachments.value]..removeAt(index);
    _attachments.value = next;
  }

  Future<void> _send() async {
    final text = _composerController.text;
    if (text.trim().isEmpty && _attachments.value.isEmpty) return;
    final attachments = List<Attachment>.from(_attachments.value);
    _attachments.value = const [];
    _composerController.clear();
    _clearDraft();
    final model = ref.read(selectedModelProvider(widget.sessionId));
    final userAgent = ref.read(selectedAgentProvider);
    final agent = userAgent ?? ref.read(defaultAgentProvider) ?? 'build';
    await ref.read(chatControllerProvider(widget.sessionId).notifier).send(
          text,
          model: model,
          agent: agent,
          attachments: attachments,
        );
    _pinToBottom(animate: true);
  }

  void _showChatMenu(BuildContext context, WidgetRef ref) {
    final selectedModel = ref.read(selectedModelProvider(widget.sessionId));
    final currentModel = ref.read(currentModelProvider(widget.sessionId));
    final modelLabel = selectedModel?.modelID ?? currentModel;
    final selectedAgent = ref.read(selectedAgentProvider);
    final defaultAgent = ref.read(defaultAgentProvider);
    final agentLabel = selectedAgent ?? defaultAgent;
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
              const Text('Session options').h4,
              const Gap(16),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  context.push('/session/${widget.sessionId}/files');
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.folderOpen, size: 16),
                    Gap(10),
                    Text('Files'),
                  ],
                ),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  openTerminalSheet(
                    context,
                    sessionId: widget.sessionId,
                  );
                },
                child: const Row(
                  children: [
                    Icon(LucideIcons.terminal, size: 16),
                    Gap(10),
                    Text('Terminal'),
                  ],
                ),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  openModelPicker(
                    context: context,
                    ref: ref,
                    sessionId: widget.sessionId,
                  );
                },
                child: Row(
                  children: [
                    const Icon(LucideIcons.cpu, size: 16),
                    const Gap(10),
                    const Text('Models'),
                    if (modelLabel != null) ...[
                      const Spacer(),
                      Text(modelLabel).muted.xSmall,
                    ],
                  ],
                ),
              ),
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  openAgentPicker(context: context, ref: ref);
                },
                child: Row(
                  children: [
                    const Icon(LucideIcons.bot, size: 16),
                    const Gap(10),
                    const Text('Agents'),
                    if (agentLabel != null) ...[
                      const Spacer(),
                      Text(agentLabel).muted.xSmall,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _listenersAttached = false;

  /// The transcript is a `reverse: true` list, so offset 0 *is* the newest
  /// content and [ScrollPosition.maxScrollExtent] is the oldest. Everything
  /// below reads in those terms.
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels < _nearBottomSlack;
  }

  /// Registers the reactions that used to run as side effects inside `build`.
  /// `ref.listen` fires on change rather than on every rebuild, which is what
  /// scroll and animation control actually want.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    // Transcript shape changed: a row was added or removed.
    //
    // There is no initial scroll to perform — a bottom-anchored list opens at
    // offset 0, which already shows the newest message. That also removes the
    // one-frame flash where the transcript rendered from the top and snapped.
    ref.listenManual<VisibleMessageIds>(
      visibleMessageIdsProvider(widget.sessionId),
      (prev, next) {
        if (next.length == 0) return;
        // Ease back to the newest only if the reader had drifted slightly off
        // it. Sitting exactly at 0 — the normal case — does nothing.
        if ((prev?.length ?? 0) != next.length && _isNearBottom) {
          _pinToBottom(animate: true);
        }
      },
      fireImmediately: true,
    );

    // Deliberately no listener on the streaming tail's length. Following a
    // growing message used to mean a jumpTo() every 60ms, and each of those was
    // a visible teleport: the new text laid out at the old offset for one frame,
    // then snapped. Anchoring the list at the bottom makes the growth itself
    // move the text into place, so there is nothing left to chase.

    // Drive the typing dots off the working flag rather than from build().
    ref.listenManual<bool>(
      chatControllerProvider(widget.sessionId)
          .select((c) => c.state.working && !c.state.aborting),
      (prev, next) {
        if (next && !_workingAnimController.isAnimating) {
          _workingAnimController.repeat();
        } else if (!next && _workingAnimController.isAnimating) {
          _workingAnimController.stop();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    _attachListeners();

    // Only the coarse chrome state — never message content. A streamed token
    // changes none of these fields, so this screen does not rebuild for it.
    final chrome = ref.watch(
      chatControllerProvider(widget.sessionId)
          .select((c) => chatChromeOf(c.state)),
    );
    final visibleIds =
        ref.watch(visibleMessageIdsProvider(widget.sessionId)).ids;
    final controller =
        ref.read(chatControllerProvider(widget.sessionId).notifier);

    final currentModel = ref.watch(currentModelProvider(widget.sessionId));
    final currentAgent = ref.watch(currentModeProvider(widget.sessionId));
    final globalBusy = ref.watch(
      sessionActivityProvider.select((s) => s.contains(widget.sessionId)),
    );
    final working = (chrome.working || globalBusy) && !chrome.aborting;
    final agentLabel = currentAgent;
    final sessionDir =
        ref.watch(sessionDirectoryProvider(widget.sessionId)).value;
    final vcs = ref.watch(vcsProvider(sessionDir));
    final branch = vcs.value?.branch;
    final subtitleParts = [
      if (branch != null && branch.isNotEmpty) branch,
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
                      workspaceName.split('/').last,
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
              icon: const Icon(LucideIcons.audioLines),
              onPressed: () =>
                  context.push('/session/${widget.sessionId}/voice'),
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.ellipsisVertical),
              onPressed: () => _showChatMenu(context, ref),
            ),
          ],
        ),
      ],
      resizeToAvoidBottomInset: true,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _buildBody(
                  chrome,
                  visibleIds: visibleIds,
                  working: working,
                ),
              ),
              const PermissionBanner(),
              _Composer(
                sessionId: widget.sessionId,
                controller: _composerController,
                sending: chrome.sending,
                working: working,
                aborting: chrome.aborting,
                error: chrome.error,
                errorType: chrome.errorType,
                statusCode: chrome.statusCode,
                retryMessage: chrome.retryMessage,
                retryAction: chrome.retryAction,
                retryNext: chrome.retryNext,
                attachments: _attachments,
                onPickFiles: _pickFiles,
                onRemoveAttachment: _removeAttachment,
                onSend: _send,
                onAbort: controller.abort,
                onDismiss: controller.dismissStuck,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The permanent bottom slot holding the typing dots.
  ///
  /// Always present in the list and collapsed to zero height when idle, so
  /// starting and finishing a turn eases the height instead of inserting and
  /// removing a row. `bottomLeft` keeps the dots pinned to the bottom of the
  /// slot as it grows, matching the bottom-anchored list.
  Widget _buildWorkingSlot(bool working) {
    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.inOut,
      alignment: Alignment.bottomLeft,
      child: working
          ? Padding(
              padding: const EdgeInsets.only(top: 24),
              child: _buildWorkingIndicator(),
            )
          : const SizedBox(width: double.infinity),
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

  Widget _buildBody(
    ChatChrome chrome, {
    required List<String> visibleIds,
    required bool working,
  }) {
    if (chrome.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chrome.error != null && !chrome.hasMessages) {
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
                  chrome.error!,
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
    if (visibleIds.isEmpty) {
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
    final hasHeader = chrome.loadingOlder || chrome.hasMoreOlder;
    // The working slot is always in the list, collapsed to nothing when idle.
    // As a conditional row it was inserted and removed on every turn, and each
    // of those was a layout jump.
    final itemCount = 1 + visibleIds.length + (hasHeader ? 1 : 0);
    Widget? header;
    if (chrome.loadingOlder) {
      header = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (chrome.hasMoreOlder) {
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
              // Bottom-anchored: offset 0 is the newest message, and a growing
              // tail extends away from it. Nothing has to scroll to follow a
              // streaming reply, so nothing can judder while it arrives.
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: itemCount,
              // Index 0 is the working slot, which carries its own spacing.
              separatorBuilder: (context, index) =>
                  index == 0 ? const SizedBox.shrink() : const Gap(24),
              itemBuilder: (context, index) {
                if (index == 0) return _buildWorkingSlot(working);
                final id = transcriptIdForRow(visibleIds, index - 1);
                // Past the newest..oldest range is the load-older header, which
                // sits at the far (top) end of a reversed list.
                if (id == null) return header ?? const SizedBox.shrink();
                // Only the id is passed down: the bubble subscribes to its own
                // message, so a streamed token rebuilds that bubble alone.
                // ListView.separated already adds repaint boundaries per item.
                return _MessageBubbleSlot(
                  key: ValueKey(id),
                  sessionId: widget.sessionId,
                  messageId: id,
                );
              },
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showScrollToBottom,
          builder: (context, show, _) {
            return Positioned(
              right: 16,
              bottom: 16,
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedSlide(
                  offset: show ? Offset.zero : const Offset(0, 0.4),
                  duration: Motion.base,
                  curve: Motion.standard,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: Motion.base,
                    curve: Motion.standard,
                    child: GestureDetector(
                      onTap: () {
                        Haptics.tap();
                        _pinToBottom(animate: true);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.muted,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.arrowDown,
                          size: 18,
                          color: Theme.of(context).colorScheme.foreground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Subscribes to one message and renders its bubble.
///
/// This is the unit of rebuild during streaming: it watches
/// [chatMessageProvider] for a single id, so a delta applied to the tail
/// message leaves every other slot untouched.
class _MessageBubbleSlot extends ConsumerWidget {
  const _MessageBubbleSlot({
    super.key,
    required this.sessionId,
    required this.messageId,
  });

  final String sessionId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      chatMessageProvider(ChatMessageRef(sessionId, messageId)),
    );
    if (message == null) return const SizedBox.shrink();
    return _MessageEntrance(
      messageId: messageId,
      child: MessageBubble(message: message),
    );
  }
}

/// Fades and lifts a bubble into place the first time it is seen.
///
/// Ids that have already animated are remembered process-wide, so bubbles
/// recycled back into view while scrolling appear instantly instead of
/// replaying the animation.
class _MessageEntrance extends StatefulWidget {
  const _MessageEntrance({required this.messageId, required this.child});

  final String messageId;
  final Widget child;

  static final _seen = <String>{};
  static const _seenMaxSize = 500;

  @override
  State<_MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<_MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final alreadySeen = _MessageEntrance._seen.contains(widget.messageId);
    _MessageEntrance._seen.add(widget.messageId);
    if (_MessageEntrance._seen.length > _MessageEntrance._seenMaxSize) {
      _MessageEntrance._seen.clear();
      _MessageEntrance._seen.add(widget.messageId);
    }
    _controller = AnimationController(
      vsync: this,
      duration: Motion.entry,
      value: alreadySeen ? 1 : 0,
    );
    final curved = CurvedAnimation(parent: _controller, curve: Motion.standard);
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
    if (!alreadySeen) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
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
    required this.errorType,
    required this.statusCode,
    required this.retryMessage,
    required this.retryAction,
    required this.retryNext,
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
  final String? errorType;
  final int? statusCode;
  final String? retryMessage;
  final RetryAction? retryAction;
  final int? retryNext;
  final ValueListenable<List<Attachment>> attachments;
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
  bool _toolsExpanded = false;
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
          // No setState: mutating the controller notifies the TextField
          // directly. Partial dictation results arrive many times a second, and
          // rebuilding the whole composer for each one made dictation stutter.
          widget.controller.text = '$base$suffix${result.recognizedWords}';
          widget.controller.selection = TextSelection.fromPosition(
            TextPosition(offset: widget.controller.text.length),
          );
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
    final selectedModel = ref.watch(selectedModelProvider(widget.sessionId));
    final currentModel = ref.watch(currentModelProvider(widget.sessionId));
    final modelLabel = selectedModel?.modelID ?? currentModel;
    final selectedAgent = ref.watch(selectedAgentProvider);
    final defaultAgent = ref.watch(defaultAgentProvider);
    final agentLabel = selectedAgent ?? defaultAgent;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (widget.retryMessage != null) ...[
                const Gap(8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.rotateCcw,
                              size: 14, color: Colors.orange),
                          const Gap(6),
                          Expanded(
                            child: Text(widget.retryMessage!).xSmall,
                          ),
                        ],
                      ),
                      if (widget.retryAction != null) ...[
                        const Gap(6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.retryAction!.message,
                                style: const TextStyle(fontSize: 11),
                              ).muted,
                            ),
                            if (widget.retryAction!.link != null)
                              TextButton(
                                onPressed: () {
                                  final url = widget.retryAction!.link;
                                  if (url != null) {
                                    launchUrl(Uri.parse(url));
                                  }
                                },
                                child: Text(widget.retryAction!.label).xSmall,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (widget.error != null) ...[
                const Gap(8),
                Builder(
                  builder: (context) {
                    final isRateLimit = widget.statusCode == 429;
                    final isAuthError = widget.errorType == 'ProviderAuthError';
                    final isQuota = widget.statusCode == 402;
                    final color = isRateLimit
                        ? Colors.orange
                        : isAuthError
                            ? Colors.amber
                            : isQuota
                                ? Colors.purple
                                : Colors.red;
                    final icon = isRateLimit
                        ? LucideIcons.clock
                        : isAuthError
                            ? LucideIcons.keyRound
                            : isQuota
                                ? LucideIcons.wallet
                                : LucideIcons.triangleAlert;
                    final label = isRateLimit
                        ? 'Rate limited'
                        : isAuthError
                            ? 'Auth error'
                            : isQuota
                                ? 'Quota exceeded'
                                : null;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 14, color: color),
                              const Gap(6),
                              if (label != null) Text(label).xSmall.bold,
                              if (label != null) const Gap(4),
                              Expanded(
                                child: Text(widget.error!).xSmall,
                              ),
                            ],
                          ),
                          if (isRateLimit) ...[
                            const Gap(4),
                            Text(
                              'Try again in a moment or switch to a different model.',
                              style: TextStyle(
                                  fontSize: 11, color: color.withAlpha(180)),
                            ),
                          ],
                          if (isAuthError) ...[
                            const Gap(4),
                            Text(
                              'Check your API key in server settings.',
                              style: TextStyle(
                                  fontSize: 11, color: color.withAlpha(180)),
                            ),
                          ],
                          if (isQuota) ...[
                            const Gap(4),
                            Text(
                              'Your plan limit has been reached. Upgrade or wait for it to reset.',
                              style: TextStyle(
                                  fontSize: 11, color: color.withAlpha(180)),
                            ),
                          ],
                          const Gap(6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
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
                        ],
                      ),
                    );
                  },
                ),
              ],
              //const Gap(10),
              ValueListenableBuilder<List<Attachment>>(
                valueListenable: widget.attachments,
                builder: (context, attachments, _) {
                  return AnimatedSize(
                    duration: Motion.base,
                    curve: Motion.inOut,
                    alignment: Alignment.topCenter,
                    child: attachments.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : Column(
                            children: [
                              SizedBox(
                                height: 48,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: attachments.length,
                                  separatorBuilder: (_, __) => const Gap(6),
                                  itemBuilder: (context, index) {
                                    return _AttachmentChip(
                                      attachment: attachments[index],
                                      onRemove: () =>
                                          widget.onRemoveAttachment(index),
                                    );
                                  },
                                ),
                              ),
                              const Gap(8),
                            ],
                          ),
                  );
                },
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: widget.controller,
                      placeholder: const Text('Message SparkCode...'),
                      border: Border.all(color: Colors.transparent),
                      borderRadius: BorderRadius.zero,
                      maxLines: 5,
                      minLines: 2,
                      onSubmitted: (_) => widget.onSend(),
                    ),
                    Row(
                      children: [
                        if (_toolsExpanded)
                          IconButton.ghost(
                            icon: const Icon(LucideIcons.x, size: 18),
                            size: ButtonSize.small,
                            onPressed: () =>
                                setState(() => _toolsExpanded = false),
                          )
                        else
                          IconButton.ghost(
                            icon: const Icon(LucideIcons.plus, size: 18),
                            size: ButtonSize.small,
                            onPressed: () =>
                                setState(() => _toolsExpanded = true),
                          ),
                        if (_toolsExpanded) ...[
                          IconButton.ghost(
                            icon: const Icon(LucideIcons.paperclip, size: 18),
                            size: ButtonSize.small,
                            onPressed: () {
                              setState(() => _toolsExpanded = false);
                              widget.onPickFiles();
                            },
                          ),
                          if (_speechAvailable)
                            IconButton.ghost(
                              icon: _isListening
                                  ? const Icon(LucideIcons.circleDot,
                                      size: 18, color: Colors.red)
                                  : const Icon(LucideIcons.mic, size: 18),
                              size: ButtonSize.small,
                              onPressed: () {
                                if (!_isListening) {
                                  setState(() => _toolsExpanded = false);
                                }
                                _toggleListening();
                              },
                            ),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Haptics.tap();
                            openModelPicker(
                              context: context,
                              ref: ref,
                              sessionId: widget.sessionId,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.mutedForeground
                                  .withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              modelLabel ?? 'model',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        const Gap(4),
                        GestureDetector(
                          onTap: () {
                            Haptics.tap();
                            openAgentPicker(context: context, ref: ref);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.mutedForeground
                                  .withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              agentLabel ?? 'agent',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        const Gap(4),
                        if (widget.working ||
                            widget.aborting ||
                            widget.error != null)
                          // Primary, not destructive: this is the send button
                          // changing state while a turn runs, not an alarm.
                          IconButton.primary(
                            icon: const Icon(LucideIcons.square),
                            size: ButtonSize.small,
                            shape: ButtonShape.circle,
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
                                : const Icon(LucideIcons.send),
                            size: ButtonSize.small,
                            shape: ButtonShape.circle,
                            onPressed: widget.sending
                                ? null
                                : () {
                                    Haptics.commit();
                                    widget.onSend();
                                  },
                          ),
                      ],
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
