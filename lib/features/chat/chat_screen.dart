import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/model_selector.dart';
import '../models/models_provider.dart';
import '../../app/desktop_shell.dart';
import '../../app/motion.dart';
import '../permissions/permission_banner.dart';
import '../permissions/permission_sheet.dart';
import '../../core/models/permission.dart';
import '../sessions/workspace_provider.dart';
import '../../core/api/connectivity_provider.dart';
import '../../core/api/permission_provider.dart';
import '../../core/api/providers.dart';
import '../../core/api/session_error_provider.dart';
import '../../core/models/attachment.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/storage/settings_store.dart';
import '../../core/storage/settings_provider.dart';
import '../local_server/opencode_locator.dart';
import '../terminal/terminal_sheet.dart';
import 'chat_provider.dart';
import 'message_bubble.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/chat_loading_skeleton.dart';

const _scrollNearBottomThreshold = 120.0;

String scrollKey(String sessionId) => 'chat_$sessionId';

bool isNearBottom(double pixels, double maxScrollExtent) {
  return maxScrollExtent - pixels < _scrollNearBottomThreshold;
}

enum ScrollRestoreDecision { jumpToPosition, scrollToBottom, waitForLayout }

ScrollRestoreDecision decideScrollRestore({
  required double? savedPosition,
  required double maxScrollExtent,
}) {
  if (maxScrollExtent <= 0) return ScrollRestoreDecision.waitForLayout;
  if (savedPosition != null && savedPosition > 0) {
    return ScrollRestoreDecision.jumpToPosition;
  }
  return ScrollRestoreDecision.scrollToBottom;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.sessionId, this.embedded = false});

  final String sessionId;
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Attachment> _attachments = [];
  final _showScrollToBottom = ValueNotifier<bool>(false);
  late final AnimationController _workingAnimController;
  Timer? _scrollSaveTimer;
  bool _scrollPositionRestored = false;
  bool _restoringScroll = false;
  double? _pendingScrollPosition;

  bool _listenersInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    NotificationService.instance.requestPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeChatSessionProvider.notifier).state = widget.sessionId;
      _clearSessionErrorNotice();
    });
    _loadDraft();
    _workingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _workingAnimController.addListener(_onWorkingTick);
  }

  void _clearSessionErrorNotice() {
    final errors = {...ref.read(sessionErrorsProvider)};
    if (errors.remove(widget.sessionId) != null) {
      ref.read(sessionErrorsProvider.notifier).state = errors;
    }
    NotificationService.instance.cancelSessionError();
  }

  void _setupListenersIfNeeded() {
    if (_listenersInitialized) return;
    _listenersInitialized = true;
    _setupListeners();
    if (!_initialScrollDone && !_scrollPositionRestored) {
      final visibleIds = ref.read(visibleMessageIdsProvider(widget.sessionId));
      if (visibleIds.length > 0) {
        _initialScrollDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startScrollRestore();
        });
      }
    }
    // Sync animation with current state (ref.listen only fires on changes).
    final chrome = ref.read(
      chatControllerProvider(widget.sessionId).select(
        (c) => chatChromeOf(c.state, initialLoadDone: c.initialLoadDone),
      ),
    );
    final globalBusy = ref
        .read(sessionActivityProvider)
        .contains(widget.sessionId);
    final working =
        (chrome.working || globalBusy) &&
        !ref.read(chatControllerProvider(widget.sessionId).notifier).aborting;
    if (working && !_workingAnimController.isAnimating) {
      _workingAnimController.repeat();
    }
  }

  void _setupListeners() {
    // Working animation: only reacts to working/aborting changes.
    ref.listen(
      chatControllerProvider(widget.sessionId).select(
        (c) => chatChromeOf(c.state, initialLoadDone: c.initialLoadDone),
      ),
      (prev, next) {
        final globalBusy = ref
            .read(sessionActivityProvider)
            .contains(widget.sessionId);
        final working =
            (next.working || globalBusy) &&
            !ref
                .read(chatControllerProvider(widget.sessionId).notifier)
                .aborting;
        if (working && !_workingAnimController.isAnimating) {
          _workingAnimController.repeat();
        } else if (!working && _workingAnimController.isAnimating) {
          _workingAnimController.stop();
        }
      },
    );

    // Session activity: also drive working animation.
    ref.listen(sessionActivityProvider, (prev, next) {
      final chrome = ref.read(
        chatControllerProvider(widget.sessionId).select(
          (c) => chatChromeOf(c.state, initialLoadDone: c.initialLoadDone),
        ),
      );
      final globalBusy = next.contains(widget.sessionId);
      final working =
          (chrome.working || globalBusy) &&
          !ref.read(chatControllerProvider(widget.sessionId).notifier).aborting;
      if (working && !_workingAnimController.isAnimating) {
        _workingAnimController.repeat();
      } else if (!working && _workingAnimController.isAnimating) {
        _workingAnimController.stop();
      }
    });

    // Streaming: scroll when working state changes.
    ref.listen(
      chatControllerProvider(widget.sessionId).select(
        (c) => chatChromeOf(c.state, initialLoadDone: c.initialLoadDone),
      ),
      (prev, next) {
        if (!next.working) return;
        if (_isNearBottom) {
          _smoothScrollToBottom();
        }
      },
    );

    // Message count changed: auto-scroll on new messages.
    ref.listen(visibleMessageIdsProvider(widget.sessionId), (prev, next) {
      final prevCount = prev?.length ?? 0;
      final nextCount = next.length;
      if (nextCount != prevCount) {
        if (!_initialScrollDone && nextCount > 0) {
          _initialScrollDone = true;
          _startScrollRestore();
        } else if (_restoringScroll) {
          if (_pendingScrollPosition == null) {
            _scrollToBottomNoSave();
          } else {
            _attemptScrollRestore();
          }
        } else if (_initialScrollDone && !_restoringScroll && _isNearBottom) {
          _scrollToBottom();
        }
      }
    });
  }

  double? _lastScrollPosition;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final scrolledUp =
        _lastScrollPosition != null &&
        position.pixels < _lastScrollPosition! - 2;
    _lastScrollPosition = position.pixels;
    if (scrolledUp && _isAnimatingScroll) {
      _scrollController.jumpTo(position.pixels);
      _isAnimatingScroll = false;
      _followPaused = true;
    }
    if (position.pixels < 200) {
      final controller = ref.read(
        chatControllerProvider(widget.sessionId).notifier,
      );
      controller.loadOlder();
    }
    final nearBottom =
        position.maxScrollExtent - position.pixels < _scrollNearBottomThreshold;
    _showScrollToBottom.value = !nearBottom;
    if (!nearBottom) {
      _followPaused = true;
    }
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(seconds: 1), _saveScrollPosition);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      if (ref.read(activeChatSessionProvider) == widget.sessionId) {
        ref.read(activeChatSessionProvider.notifier).state = null;
      }
    } catch (_) {}
    _saveDraft();
    _saveScrollPosition();
    _scrollSaveTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _composerController.dispose();
    _scrollController.dispose();
    _workingAnimController.removeListener(_onWorkingTick);
    _workingAnimController.dispose();
    _showScrollToBottom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraft();
      _saveScrollPosition();
    }
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

  void _saveScrollPosition() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = isNearBottom(position.pixels, position.maxScrollExtent);
    if (atBottom) {
      SettingsStore().saveScrollPosition(scrollKey(widget.sessionId), -1);
    } else {
      SettingsStore().saveScrollPosition(
        scrollKey(widget.sessionId),
        _scrollController.offset,
      );
    }
  }

  void _startScrollRestore() {
    if (_scrollPositionRestored) return;
    _restoringScroll = true;
    Timer(const Duration(seconds: 3), () {
      if (mounted && _restoringScroll && !_scrollPositionRestored) {
        _scrollToBottomNoSave();
      }
    });
    SettingsStore().loadScrollPosition(scrollKey(widget.sessionId)).then((
      saved,
    ) {
      if (!mounted) return;
      if (saved == null) {
        _scrollToBottomNoSave();
        return;
      }
      _pendingScrollPosition = saved;
      _attemptScrollRestore();
    });
  }

  int _pinGeneration = 0;
  int _pinStableFrames = 0;
  double _pinLastMax = -1;

  void _scrollToBottomNoSave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(max);
      _markRestored();
      _pinToBottom(finishRestore: false, budget: 15, stableNeeded: 2);
    });
  }

  /// Keeps jumping to the end of the list until the layout settles.
  ///
  /// A single jumpTo is not enough: ListView.builder lays out lazily, so the
  /// first maxScrollExtent only covers the items built so far, and the network
  /// load() can prepend older messages afterwards and shift everything down.
  /// This re-pins every frame until the viewport sits at the bottom and
  /// maxScrollExtent stops growing.
  void _pinToBottom({
    required bool finishRestore,
    bool requireLoaded = false,
    int budget = 60,
    int stableNeeded = 3,
  }) {
    _pinGeneration++;
    _pinStableFrames = 0;
    _pinLastMax = -1;
    _pinFrame(
      generation: _pinGeneration,
      finishRestore: finishRestore,
      requireLoaded: requireLoaded,
      remaining: budget,
      stableNeeded: stableNeeded,
    );
  }

  void _finishPin(bool finishRestore) {
    if (finishRestore) _markRestored();
  }

  void _markRestored() {
    if (_scrollPositionRestored && !_restoringScroll) return;
    _restoringScroll = false;
    _scrollPositionRestored = true;
    if (mounted) setState(() {});
  }

  void _pinFrame({
    required int generation,
    required bool finishRestore,
    required bool requireLoaded,
    required int remaining,
    required int stableNeeded,
  }) {
    if (remaining <= 0 || !mounted) {
      _finishPin(finishRestore);
      return;
    }
    void next() => _pinFrame(
      generation: generation,
      finishRestore: finishRestore,
      requireLoaded: requireLoaded,
      remaining: remaining - 1,
      stableNeeded: stableNeeded,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _pinGeneration) return;
      if (!_scrollController.hasClients) {
        next();
        return;
      }
      final position = _scrollController.position;
      final max = position.maxScrollExtent;
      if (max <= 0) {
        _pinStableFrames = 0;
        next();
        return;
      }
      if (position.pixels < max - 0.5) {
        _scrollController.jumpTo(max);
        _pinStableFrames = 0;
        _pinLastMax = max;
        next();
        return;
      }
      if ((max - _pinLastMax).abs() < 0.5) {
        _pinStableFrames++;
      } else {
        _pinStableFrames = 0;
        _pinLastMax = max;
      }
      if (_pinStableFrames >= stableNeeded) {
        if (requireLoaded) {
          final notifier = ref.read(
            chatControllerProvider(widget.sessionId).notifier,
          );
          if (notifier.state.loading || !notifier.initialLoadDone) {
            _pinStableFrames = 0;
            next();
            return;
          }
        }
        _finishPin(finishRestore);
        return;
      }
      next();
    });
  }

  void _attemptScrollRestore() {
    if (!mounted || _scrollPositionRestored) return;

    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptScrollRestore();
      });
      return;
    }

    final saved = _pendingScrollPosition;
    if (saved == null) {
      // SharedPreferences hasn't returned yet — wait for next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptScrollRestore();
      });
      return;
    }

    final max = _scrollController.position.maxScrollExtent;
    final decision = decideScrollRestore(
      savedPosition: saved,
      maxScrollExtent: max,
    );
    switch (decision) {
      case ScrollRestoreDecision.waitForLayout:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _attemptScrollRestore();
        });
        return;
      case ScrollRestoreDecision.jumpToPosition:
        break;
      case ScrollRestoreDecision.scrollToBottom:
        break;
    }

    _markRestored();
    if (decision == ScrollRestoreDecision.jumpToPosition) {
      _scrollController.jumpTo(saved.clamp(0.0, max));
    } else {
      _scrollToBottom(animate: false);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    _followPaused = false;
    if (!animate) {
      _isAnimatingScroll = false;
      _pinToBottom(finishRestore: false, budget: 45, stableNeeded: 4);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _smoothScrollToBottom();
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
        _attachments.add(
          Attachment(
            name: name,
            path: file.path ?? name,
            mime: mime,
            bytes: bytes,
          ),
        );
      });
    }
  }

  Future<void> _takePicture() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    final name = photo.name;
    setState(() {
      _attachments.add(
        Attachment(
          name: name,
          path: photo.path,
          mime: 'image/jpeg',
          bytes: bytes,
        ),
      );
    });
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
      'csv' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _send() async {
    final text = _composerController.text;
    if (text.trim().isEmpty && _attachments.isEmpty) return;
    FocusScope.of(context).unfocus();
    final attachments = List<Attachment>.from(_attachments);
    setState(() => _attachments.clear());
    _composerController.clear();
    _clearDraft();
    final model = ref.read(selectedModelProvider(widget.sessionId));
    final userAgent = ref.read(selectedAgentProvider);
    final agent = userAgent ?? ref.read(defaultAgentProvider) ?? 'build';
    await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(text, model: model, agent: agent, attachments: attachments);
    _scrollToBottom(animate: false);
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
              if (isDesktopPlatform) ...[
                const Gap(8),
                OutlineButton(
                  onPressed: () {
                    closeSheet(sheetContext);
                    context.push('/session/${widget.sessionId}/workspace');
                  },
                  child: const Row(
                    children: [
                      Icon(LucideIcons.squareCode, size: 16),
                      Gap(10),
                      Text('Workspace'),
                    ],
                  ),
                ),
              ],
              const Gap(8),
              OutlineButton(
                onPressed: () {
                  closeSheet(sheetContext);
                  openTerminalSheet(context, sessionId: widget.sessionId);
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
              const Gap(16),
              OutlineButton(
                onPressed: () {
                  final current = ref.read(autoApprovePermissionsProvider);
                  ref
                      .read(autoApprovePermissionsProvider.notifier)
                      .setValue(!current);
                  if (!current) {
                    ref.read(pendingPermissionsProvider.notifier).state =
                        const {};
                    NotificationService.instance.cancelPermission();
                  }
                },
                child: Row(
                  children: [
                    const Icon(LucideIcons.zap, size: 16),
                    const Gap(10),
                    const Expanded(child: Text('Auto-allow permissions')),
                    Switch(
                      value: ref.watch(autoApprovePermissionsProvider),
                      onChanged: null,
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

  bool _isAnimatingScroll = false;
  bool _followPaused = false;

  void _onWorkingTick() {
    if (_isAnimatingScroll || _followPaused) return;
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final gap = pos.maxScrollExtent - pos.pixels;
    if (gap > 0.5 &&
        gap < _scrollNearBottomThreshold &&
        pos.maxScrollExtent > 0) {
      _smoothScrollToBottom();
    }
  }

  void _smoothScrollToBottom() {
    if (_isAnimatingScroll) return;
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final gap = pos.maxScrollExtent - pos.pixels;
    if (gap <= 0.5 || pos.maxScrollExtent <= 0) return;
    _isAnimatingScroll = true;
    _scrollController
        .animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          _isAnimatingScroll = false;
          if (mounted && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onWorkingTick();
            });
          }
        });
  }

  bool _initialScrollDone = false;

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return isNearBottom(position.pixels, position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    _setupListenersIfNeeded();
    final chrome = ref.watch(
      chatControllerProvider(widget.sessionId).select(
        (c) => chatChromeOf(c.state, initialLoadDone: c.initialLoadDone),
      ),
    );
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );

    final currentModel = ref.watch(currentModelProvider(widget.sessionId));
    final selectedModel = ref.watch(selectedModelProvider(widget.sessionId));
    final currentAgent = ref.watch(currentModeProvider(widget.sessionId));
    final globalBusy = ref
        .watch(sessionActivityProvider)
        .contains(widget.sessionId);
    final working = (chrome.working || globalBusy) && !controller.aborting;

    final modelLabel = selectedModel?.modelID ?? currentModel;
    final agentLabel = currentAgent;
    final directoryAsync = ref.watch(
      sessionDirectoryProvider(widget.sessionId),
    );
    final directory = directoryAsync.maybeWhen(
      data: (v) => v,
      orElse: () => null,
    );
    final vcs = ref.watch(vcsProvider(directory));
    final branch = vcs.value?.branch;
    final subtitleParts = [
      if (branch != null && branch.isNotEmpty) branch,
      if (working) 'working...',
      if (currentModel != null) currentModel,
      if (agentLabel != null) agentLabel,
    ];

    final wide = MediaQuery.sizeOf(context).width >= desktopBreakpoint;
    final autoAllow = ref.watch(autoApprovePermissionsProvider);
    final canPop = context.canPop();

    return Scaffold(
      headers: [
        AppBar(
          leading: widget.embedded
              ? const <Widget>[]
              : [
                  if (!wide || canPop)
                    IconButton.ghost(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                    ),
                ],
          title: widget.embedded
              ? null
              : Builder(
                  builder: (context) {
                    final workspaceAsync = ref.watch(
                      sessionDirectoryProvider(widget.sessionId),
                    );
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
            if (wide) ...[
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => const Text('Files'),
                  child: const Icon(LucideIcons.folderOpen),
                ),
                onPressed: () =>
                    context.push('/session/${widget.sessionId}/files'),
              ),
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => const Text('Workspace'),
                  child: const Icon(LucideIcons.squareCode),
                ),
                onPressed: () =>
                    context.push('/session/${widget.sessionId}/workspace'),
              ),
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => const Text('Terminal'),
                  child: const Icon(LucideIcons.terminal),
                ),
                onPressed: () =>
                    openTerminalSheet(context, sessionId: widget.sessionId),
              ),
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => Text(
                    modelLabel != null ? 'Model: $modelLabel' : 'Models',
                  ),
                  child: const Icon(LucideIcons.cpu),
                ),
                onPressed: () => openModelPicker(
                  context: context,
                  ref: ref,
                  sessionId: widget.sessionId,
                ),
              ),
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => Text(
                    agentLabel != null ? 'Agent: $agentLabel' : 'Agents',
                  ),
                  child: const Icon(LucideIcons.bot),
                ),
                onPressed: () => openAgentPicker(context: context, ref: ref),
              ),
              IconButton.ghost(
                icon: Tooltip(
                  tooltip: (_) => const Text('Auto-allow permissions'),
                  child: Icon(
                    LucideIcons.zap,
                    color: autoAllow
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                onPressed: () {
                  ref
                      .read(autoApprovePermissionsProvider.notifier)
                      .setValue(!autoAllow);
                  if (!autoAllow) {
                    ref.read(pendingPermissionsProvider.notifier).state =
                        const {};
                    NotificationService.instance.cancelPermission();
                  }
                },
              ),
              const Gap(4),
            ],
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
          _buildBody(chrome, working: working),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.background.withValues(alpha: 0.0),
                          Theme.of(context).colorScheme.background,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PermissionBanner(),
                _Composer(
                  sessionId: widget.sessionId,
                  controller: _composerController,
                  sending: chrome.sending,
                  working: working,
                  aborting: controller.aborting,
                  error: chrome.error,
                  errorType: chrome.errorType,
                  statusCode: chrome.statusCode,
                  retryMessage: chrome.retryMessage,
                  retryAction: chrome.retryAction,
                  retryNext: chrome.retryNext,
                  attachments: _attachments,
                  onPickFiles: _pickFiles,
                  onTakePicture: _takePicture,
                  onRemoveAttachment: _removeAttachment,
                  onSend: _send,
                  onAbort: controller.abort,
                  onDismiss: controller.dismissStuck,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingReplyDivider() {
    final border = Theme.of(context).colorScheme.border;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Text('Sent — awaiting reply').xSmall.muted,
          ),
          Expanded(child: Container(height: 1, color: border)),
        ],
      ),
    );
  }

  Widget _buildWorkingIndicator() {
    final pending = ref.watch(pendingPermissionsProvider);
    final sessionPerms = pending.values
        .where((p) => p.sessionID == widget.sessionId)
        .toList();
    if (sessionPerms.isNotEmpty) {
      final perm = sessionPerms.first;
      return GestureDetector(
        onTap: () {
          final client = ref.read(opencodeClientProvider);
          showPermissionSheet(
            context: context,
            permission: perm,
            onRespond: (response) {
              final map = {...ref.read(pendingPermissionsProvider)};
              if (map.remove(perm.id) != null) {
                ref.read(pendingPermissionsProvider.notifier).state =
                    map.isEmpty ? const {} : map;
                if (map.isEmpty) {
                  NotificationService.instance.cancelPermission();
                }
              }
              client
                  ?.respondPermission(
                    sessionId: perm.sessionID,
                    permissionId: perm.id,
                    reply: response,
                    directory: perm.directory,
                  )
                  .catchError((_) {});
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(permissionIcon(perm.type), size: 14, color: Colors.orange),
              const Gap(8),
              Expanded(
                child: Text(
                  'Waiting for permission: ${perm.title ?? perm.type ?? "approval"}',
                ).small.muted,
              ),
              const Icon(
                LucideIcons.chevronRight,
                size: 12,
              ).iconMutedForeground,
            ],
          ),
        ),
      );
    }
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
                  color: Theme.of(
                    context,
                  ).colorScheme.mutedForeground.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _buildBody(ChatChrome chrome, {required bool working}) {
    if (chrome.error != null && !chrome.hasMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                size: 40,
              ).iconMutedForeground,
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
    final visibleIds = ref.watch(visibleMessageIdsProvider(widget.sessionId));
    final visible = visibleIds.ids;

    if (!_initialScrollDone && !_scrollPositionRestored && visible.isNotEmpty) {
      _initialScrollDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startScrollRestore();
      });
    }

    final showEmptyHint =
        visible.isEmpty && (chrome.initialLoadDone || !chrome.loading);
    if (showEmptyHint) {
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
        chrome.loadingOlder || (chrome.hasMoreOlder && visible.isNotEmpty);
    final showAwaitingReply =
        chrome.awaitingReply && visible.isNotEmpty && !working;
    final itemCount =
        visible.length +
        (hasHeader ? 1 : 0) +
        (working ? 1 : 0) +
        (showAwaitingReply ? 1 : 0);
    Widget? header;
    if (chrome.loadingOlder) {
      header = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (chrome.hasMoreOlder && visible.isNotEmpty) {
      header = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: const Text('Scroll up to load earlier messages').muted.small,
        ),
      );
    }
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );
    final messages = controller.state.messages;
    // While the initial scroll restore is still pinning to the bottom, keep
    // the list laid out but invisible behind the skeleton: presenting even
    // one frame of the top of a half-loaded transcript reads as "opened at
    // the top". The reveal fades in once the pin settles on the full content.
    final revealed = _scrollPositionRestored;
    return Stack(
      children: [
        IgnorePointer(
          ignoring: !revealed,
          child: AnimatedOpacity(
            opacity: revealed ? 1.0 : 0.0,
            duration: Motion.base,
            curve: Motion.standard,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.sizeOf(context).width >= desktopBreakpoint
                      ? 960
                      : 760,
                ),
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 20,
                    bottom: 120,
                  ),
                  itemCount: itemCount,
                  separatorBuilder: (context, index) => const Gap(24),
                  itemBuilder: (context, index) {
                    if (hasHeader && index == 0) return header!;
                    final messageIndex = hasHeader ? index - 1 : index;
                    if (working && index == itemCount - 1) {
                      return _buildWorkingIndicator();
                    }
                    final awaitingIndex = itemCount - (working ? 2 : 1);
                    if (showAwaitingReply && index == awaitingIndex) {
                      return _buildAwaitingReplyDivider();
                    }
                    final msgId = visible[messageIndex];
                    final msg = messages.firstWhere(
                      (m) => m.info.id == msgId,
                      orElse: () => messages.last,
                    );
                    return RepaintBoundary(
                      child: MessageBubble(key: ValueKey(msgId), message: msg),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (!revealed) const Positioned.fill(child: ChatLoadingSkeleton()),
        if (_restoringScroll)
          Positioned(
            right: 16,
            bottom: 16,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.muted,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: _showScrollToBottom,
          builder: (context, show, _) {
            if (!show) return const SizedBox.shrink();
            return Positioned(
              right: 16,
              bottom: 110,
              child: GestureDetector(
                onTap: () => _scrollToBottom(),
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
            );
          },
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
    required this.errorType,
    required this.statusCode,
    required this.retryMessage,
    required this.retryAction,
    required this.retryNext,
    required this.attachments,
    required this.onPickFiles,
    required this.onTakePicture,
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
  final List<Attachment> attachments;
  final VoidCallback onPickFiles;
  final VoidCallback onTakePicture;
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
  bool _hasText = false;
  late final FocusNode _composerFocus;

  static bool get _desktopEnterToSend =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    _composerFocus = FocusNode(onKeyEvent: _handleComposerKey);
    _initSpeech();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _composerFocus.dispose();
    _speech.cancel();
    super.dispose();
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    if (!_desktopEnterToSend) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    widget.onSend();
    return KeyEventResult.handled;
  }

  void _onTextChanged() {
    final nowHasText = widget.controller.text.trim().isNotEmpty;
    if (nowHasText != _hasText) {
      setState(() => _hasText = nowHasText);
    }
  }

  Future<void> _initSpeech() async {
    // speech_to_text has no desktop implementation; skip the probe so the mic
    // never appears enabled on Windows/macOS/Linux.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      _speechAvailable = false;
      return;
    }
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (_) => _stopListening(),
      );
    } catch (_) {
      _speechAvailable = false;
    }
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
      listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            widget.onSend,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            widget.onSend,
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width >= desktopBreakpoint
                  ? 960
                  : 760,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!ref.watch(connectivityProvider)) ...[
                  const Gap(4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.wifiOff,
                          size: 12,
                          color: Colors.orange,
                        ),
                        const Gap(4),
                        Text('Offline — messages will be queued').xSmall,
                      ],
                    ),
                  ),
                ],
                if (widget.retryMessage != null) ...[
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                            const Icon(
                              LucideIcons.rotateCcw,
                              size: 14,
                              color: Colors.orange,
                            ),
                            const Gap(6),
                            Expanded(child: Text(widget.retryMessage!).xSmall),
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
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  LucideIcons.triangleAlert,
                                  size: 14,
                                  color: Colors.red,
                                ),
                                const Gap(6),
                                Expanded(child: Text(widget.error!).xSmall),
                              ],
                            ),
                            if (widget.errorType != null ||
                                widget.statusCode != null) ...[
                              const Gap(6),
                              Row(
                                children: [
                                  if (widget.errorType != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha(25),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(widget.errorType!).xSmall,
                                    ),
                                  if (widget.errorType != null &&
                                      widget.statusCode != null)
                                    const Gap(6),
                                  if (widget.statusCode != null)
                                    Text(
                                      'HTTP ${widget.statusCode}',
                                    ).xSmall.muted,
                                ],
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
                                TextButton(
                                  onPressed: () {
                                    final parts = [
                                      if (widget.errorType != null)
                                        widget.errorType!,
                                      if (widget.statusCode != null)
                                        'HTTP ${widget.statusCode}',
                                      widget.error!,
                                    ];
                                    Clipboard.setData(
                                      ClipboardData(text: parts.join(' — ')),
                                    );
                                    showAppToast(
                                      context,
                                      title: 'Error copied',
                                    );
                                  },
                                  child: const Text('Copy').xSmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: widget.controller,
                        focusNode: _composerFocus,
                        placeholder: Text(
                          widget.working
                              ? 'Queue a message...'
                              : 'Message SparkCode...',
                        ),
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
                            // The camera is a phone feature; on desktop, images
                            // arrive through the file picker instead.
                            if (defaultTargetPlatform ==
                                    TargetPlatform.android ||
                                defaultTargetPlatform == TargetPlatform.iOS)
                              IconButton.ghost(
                                icon: const Icon(LucideIcons.camera, size: 18),
                                size: ButtonSize.small,
                                onPressed: () {
                                  setState(() => _toolsExpanded = false);
                                  widget.onTakePicture();
                                },
                              ),
                            if (_speechAvailable)
                              IconButton.ghost(
                                icon: _isListening
                                    ? const Icon(
                                        LucideIcons.circleDot,
                                        size: 18,
                                        color: Colors.red,
                                      )
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
                            onTap: () =>
                                ref.read(rabbitHoleProvider.notifier).toggle(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ref.watch(rabbitHoleProvider)
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primary.withAlpha(30)
                                    : Theme.of(context)
                                          .colorScheme
                                          .mutedForeground
                                          .withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.brain,
                                    size: 14,
                                    color: ref.watch(rabbitHoleProvider)
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.mutedForeground,
                                  ),
                                  if (ref.watch(rabbitHoleProvider)) ...[
                                    const Gap(4),
                                    Text(
                                      'deep',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const Gap(4),
                          GestureDetector(
                            onTap: () => openModelPicker(
                              context: context,
                              ref: ref,
                              sessionId: widget.sessionId,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                            onTap: () =>
                                openAgentPicker(context: context, ref: ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                          if (_hasText || !widget.working)
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
                              size: ButtonSize.xSmall,
                              shape: ButtonShape.circle,
                              onPressed: widget.sending ? null : widget.onSend,
                            )
                          else
                            IconButton.primary(
                              icon: const Icon(LucideIcons.square),
                              size: ButtonSize.xSmall,
                              shape: ButtonShape.circle,
                              onPressed: widget.onAbort,
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
                      const Icon(
                        LucideIcons.circleDot,
                        size: 12,
                        color: Colors.red,
                      ),
                      const Gap(6),
                      Text('Listening...').xSmall.muted,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

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

String? transcriptIdForRow(List<String> ids, int row) {
  if (ids.isEmpty || row < 0 || row >= ids.length) return null;
  return ids[ids.length - 1 - row];
}
