import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/api/connectivity_provider.dart';
import '../../core/api/opencode_client.dart';
import '../../core/api/providers.dart';
import '../../core/api/sse_client.dart';
import '../../core/models/attachment.dart';
import '../../core/models/message.dart';
import '../../core/models/provider.dart';
import '../../core/storage/cache_service.dart';
import '../../core/storage/message_queue.dart';
import 'tts_provider.dart';

final sessionDirectoryProvider =
    FutureProvider.family<String?, String>((ref, sessionId) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return null;
  final session = await client.getSession(sessionId);
  return session?.directory;
});

class RetryAction {
  const RetryAction({
    required this.reason,
    required this.provider,
    required this.title,
    required this.message,
    required this.label,
    this.link,
  });

  final String reason;
  final String provider;
  final String title;
  final String message;
  final String label;
  final String? link;

  factory RetryAction.fromJson(Map<String, dynamic> json) {
    return RetryAction(
      reason: (json['reason'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      link: json['link'] as String?,
    );
  }
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loading = true,
    this.loadingOlder = false,
    this.hasMoreOlder = true,
    this.sending = false,
    this.working = false,
    this.aborting = false,
    this.error,
    this.errorType,
    this.statusCode,
    this.retryMessage,
    this.retryAction,
    this.retryNext,
  });

  final List<MessageWithParts> messages;
  final bool loading;
  final bool loadingOlder;
  final bool hasMoreOlder;
  final bool sending;
  final bool working;
  final bool aborting;
  final String? error;
  final String? errorType;
  final int? statusCode;
  final String? retryMessage;
  final RetryAction? retryAction;
  final int? retryNext;

  ChatState copyWith({
    List<MessageWithParts>? messages,
    bool? loading,
    bool? loadingOlder,
    bool? hasMoreOlder,
    bool? sending,
    bool? working,
    bool? aborting,
    String? error,
    bool clearError = false,
    String? errorType,
    int? statusCode,
    String? retryMessage,
    bool clearRetry = false,
    RetryAction? retryAction,
    int? retryNext,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      loading: loading ?? this.loading,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
      sending: sending ?? this.sending,
      working: working ?? this.working,
      aborting: aborting ?? this.aborting,
      error: clearError ? null : (error ?? this.error),
      errorType: clearError ? null : (errorType ?? this.errorType),
      statusCode: clearError ? null : (statusCode ?? this.statusCode),
      retryMessage: clearRetry ? null : (retryMessage ?? this.retryMessage),
      retryAction: clearRetry ? null : (retryAction ?? this.retryAction),
      retryNext: clearRetry ? null : (retryNext ?? this.retryNext),
    );
  }
}

/// Whether the tail of [messages] is a turn the model is still generating.
///
/// Busy only while the model is actively generating at the tail of the
/// conversation. Two things are deliberately *not* working:
///
/// * a stale incomplete assistant message that another message follows — e.g.
///   the server restarted mid-turn;
/// * an assistant message carrying an `error`. The server does not stamp
///   `time.completed` when a turn dies, so running out of output tokens
///   (`MessageOutputLengthError`) or overflowing the context
///   (`ContextOverflowError`) used to pin the session to "working" forever. The
///   live `session.error` event cleared it, but every later reload recomputed it
///   straight back to true.
bool isTailGenerating(List<MessageWithParts> messages) {
  if (messages.isEmpty) return false;
  final info = messages.last.info;
  if (info.role != 'assistant') return false;
  if (info.hasError) return false;
  return info.timeCompleted == null;
}

class ChatController extends ChangeNotifier {
  ChatController(this.ref, this.sessionId) {
    _init();
  }

  final Ref ref;
  final String sessionId;
  Timer? _reloadTimer;
  // Separate from _reloadTimer: a pending part-apply and a pending full
  // reload used to share one timer and cancel each other, dropping updates.
  Timer? _partApplyTimer;
  Timer? _pollTimer;
  Timer? _deltaThrottleTimer;
  Timer? _stuckTimer;
  Timer? _abortTimer;
  final List<Timer> _settlingTimers = [];
  Map<String, dynamic>? _pendingPartJson;
  bool _paused = false;
  bool _aborting = false;
  bool _optimisticBusy = false;
  bool _stuck = false;
  DateTime? _lastSseActivity;
  DateTime? _abortGraceUntil;

  static const Duration _stuckThreshold = Duration(seconds: 60);
  static const Duration _stuckCheckInterval = Duration(seconds: 10);

  static const int initialLimit = 40;
  static const int olderChunkSize = 40;
  int _tailWindow = initialLimit;
  bool _loadingOlder = false;

  ChatState _state = const ChatState();
  ChatState get state => _state;
  set state(ChatState value) {
    _state = value;
    notifyListeners();
  }

  OpencodeClient? get _client => ref.read(opencodeClientProvider);

  String get _cacheKey => 'messages/$sessionId.json';

  final MessageQueue _messageQueue = MessageQueue();

  Future<void> _init() async {
    _paused = ref.read(appPausedProvider);
    ref.listen<bool>(appPausedProvider, (prev, next) {
      setPaused(next);
    });
    await load();
    _subscribeEvents();
    _startPolling();
    _startStuckTimer();
  }

  void _startStuckTimer() {
    _stuckTimer?.cancel();
    _stuckTimer = Timer.periodic(_stuckCheckInterval, (_) => _checkStuck());
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // A safety net for a silent event stream, not a refresh loop: while SSE is
    // delivering, a full reload every 8s re-parses every message and rewrites
    // the cache for nothing — during streaming that competes with the frames
    // we're trying to keep smooth.
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_paused) return;
      final last = _lastSseActivity;
      final sseIsQuiet = last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 8);
      if (sseIsQuiet) load();
    });
  }

  void _checkStuck() {
    if (_stuck || !state.working || _aborting) return;
    final last = _lastSseActivity;
    final since = last == null
        ? const Duration(days: 365)
        : DateTime.now().difference(last);
    if (since >= _stuckThreshold) {
      _stuck = true;
      _optimisticBusy = false;
      _clearAbort();
      state = state.copyWith(
        working: false,
        aborting: false,
        error: 'Session appears unresponsive. You can dismiss this.',
      );
    }
  }

  void dismissStuck() {
    if (!_stuck && state.error == null) return;
    _stuck = false;
    _lastSseActivity = DateTime.now();
    _abortGraceUntil = null;
    state = state.copyWith(
      working: false,
      clearError: true,
      clearRetry: true,
    );
  }

  Future<void> load() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(loading: false, error: 'Not connected');
      return;
    }
    try {
      final window = _tailWindow;
      final fetched = await client.listMessages(sessionId, limit: window);
      final merged = _mergeTail(fetched);
      // If the tail message shows the session is idle, any optimistic "busy"
      // flag from send() is stale (no idle event arrived) — clear it.
      if (_optimisticBusy && !_deriveWorking(merged)) {
        _optimisticBusy = false;
      }
      final working = _computeWorking(merged);
      if (!working) _stuck = false;
      ref.read(sessionActivityProvider.notifier).setBusy(sessionId, working);
      final tailError = _tailErrorInfo(merged);
      state = state.copyWith(
        messages: merged,
        loading: false,
        clearError: tailError == null,
        error: tailError?.errorMessage,
        errorType: tailError?.errorName,
        working: working,
      );
      await CacheService.instance.write(_cacheKey, {
        'items': merged.map((m) => m.toJson()).toList(),
      });
    } on OpencodeApiException catch (e) {
      final cached = await CacheService.instance
          .read(_cacheKey, maxAge: const Duration(days: 30));
      if (cached != null && state.messages.isEmpty) {
        final items = cached['items'] as List<dynamic>? ?? [];
        final messages = items
            .whereType<Map<String, dynamic>>()
            .map(MessageWithParts.fromJson)
            .toList();
        state = state.copyWith(
          messages: messages,
          loading: false,
          error: 'Offline — showing cached messages',
          working: false,
        );
      } else {
        state =
            state.copyWith(loading: false, error: e.message, working: false);
      }
    }
  }

  Future<void> loadOlder() async {
    if (_loadingOlder || !state.hasMoreOlder || state.loading) return;
    final client = _client;
    if (client == null) return;
    _loadingOlder = true;
    state = state.copyWith(loadingOlder: true);
    try {
      final oldestId =
          state.messages.isNotEmpty ? state.messages.first.info.id : null;
      final fetched = await client.listMessages(
        sessionId,
        limit: olderChunkSize,
        before: oldestId,
      );
      final existingIds = {for (final m in state.messages) m.info.id};
      final newOnes =
          fetched.where((m) => !existingIds.contains(m.info.id)).toList();
      if (newOnes.isEmpty) {
        state = state.copyWith(loadingOlder: false, hasMoreOlder: false);
        return;
      }
      _tailWindow += newOnes.length;
      final merged = [...newOnes, ...state.messages];
      if (_optimisticBusy && !_deriveWorking(merged)) {
        _optimisticBusy = false;
      }
      final working = _computeWorking(merged);
      ref.read(sessionActivityProvider.notifier).setBusy(sessionId, working);
      state = state.copyWith(
        messages: merged,
        loadingOlder: false,
        hasMoreOlder: newOnes.length >= olderChunkSize,
        working: working,
      );
    } on OpencodeApiException catch (e) {
      _loadingOlder = false;
      if (e.statusCode == 400) {
        state = state.copyWith(loadingOlder: false, hasMoreOlder: false);
      } else {
        state = state.copyWith(loadingOlder: false, error: e.message);
      }
    } finally {
      _loadingOlder = false;
    }
  }

  List<MessageWithParts> _mergeTail(List<MessageWithParts> incoming) {
    final prev = state.messages;
    if (prev.isEmpty) {
      _tailWindow =
          incoming.length > initialLimit ? incoming.length : initialLimit;
      return incoming;
    }
    final byId = {for (final m in prev) m.info.id: m};
    final keptOlder = prev
        .where((m) => !incoming.any((i) => i.info.id == m.info.id))
        .toList();
    final merged = <MessageWithParts>[];
    for (final m in incoming) {
      final old = byId[m.info.id];
      if (old != null && _sameMessages(old, m)) {
        merged.add(old);
      } else {
        merged.add(m);
      }
    }
    final result = [...keptOlder, ...merged];
    return result;
  }

  void setPaused(bool paused) {
    _paused = paused;
    if (!paused) load();
  }

  bool _sameMessages(MessageWithParts a, MessageWithParts b) {
    if (a.parts.length != b.parts.length) return false;
    for (var i = 0; i < a.parts.length; i++) {
      if (a.parts[i].text != b.parts[i].text ||
          a.parts[i].type != b.parts[i].type ||
          a.parts[i].state != b.parts[i].state) {
        return false;
      }
    }
    return true;
  }

  void _applyPartUpdate(Map<String, dynamic> props, {required bool immediate}) {
    final partJson = props['part'];
    if (partJson is! Map<String, dynamic>) {
      _debouncedReload();
      return;
    }
    final messageID = partJson['messageID'] as String?;
    final partID = (partJson['id'] ?? partJson['partID'] ?? '').toString();
    if (messageID == null || partID.isEmpty) {
      _debouncedReload();
      return;
    }
    final apply = () {
      final targetJson = _pendingPartJson ?? partJson;
      _pendingPartJson = null;
      final messages = state.messages;
      final index = messages.indexWhere((m) => m.info.id == messageID);
      if (index == -1) {
        load();
        return;
      }
      final target = messages[index];
      final partIndex = target.parts.indexWhere((p) => p.id == partID);
      if (partIndex == -1) {
        load();
        return;
      }
      final updatedPart = MessagePart.fromJson(targetJson);
      final updatedParts = List<MessagePart>.from(target.parts);
      updatedParts[partIndex] = updatedPart;
      final updatedMessage = MessageWithParts(
        info: target.info,
        parts: updatedParts,
      );
      final newMessages = List<MessageWithParts>.from(messages);
      newMessages[index] = updatedMessage;
      state = state.copyWith(messages: newMessages);
    };
    if (immediate) {
      _pendingPartJson = partJson;
      if (_deltaThrottleTimer != null && _deltaThrottleTimer!.isActive) {
        return;
      }
      _deltaThrottleTimer = Timer(const Duration(milliseconds: 60), apply);
    } else {
      _partApplyTimer?.cancel();
      _partApplyTimer = Timer(const Duration(milliseconds: 200), apply);
    }
  }

  void _subscribeEvents() {
    ref.listen<AsyncValue<OpencodeEvent>>(eventStreamProvider, (prev, next) {
      final event = next.value;
      if (event != null) _onEvent(event);
    });
  }

  void _onEvent(OpencodeEvent event) {
    final props = event.properties;
    final sid = _sessionIdFromProps(props);
    final forThisSession = sid == sessionId;
    if (forThisSession || sid == null) {
      _lastSseActivity = DateTime.now();
    }
    final activity = ref.read(sessionActivityProvider.notifier);
    switch (event.type) {
      case 'message.part.delta':
        if (forThisSession) _applyPartUpdate(props, immediate: true);
        break;
      case 'message.part.updated':
        if (forThisSession) _applyPartUpdate(props, immediate: false);
        break;
      case 'message.updated':
      case 'message.created':
      case 'message.removed':
      case 'session.updated':
      case 'session.diff':
        if (forThisSession) _debouncedReload();
        break;
      case 'session.status':
        final status = props['status'];
        final statusMap = status is Map<String, dynamic> ? status : null;
        final statusType = statusMap?['type']?.toString() ?? status?.toString();
        final isBusy = statusType == 'busy';
        final isIdle = statusType == 'idle';
        final isRetry = statusType == 'retry';
        if (sid != null) {
          activity.setBusy(sid, (isBusy || isRetry) && !isIdle && !_aborting);
        }
        if (forThisSession || sid == null) {
          if (isIdle) {
            _clearAbort();
            _optimisticBusy = false;
            state = state.copyWith(
              working: false,
              aborting: false,
              clearRetry: true,
            );
            if (forThisSession) load();
          } else if (isRetry) {
            if (!_aborting) {
              _optimisticBusy = true;
              final retryMsg = statusMap?['message'] as String?;
              final retryActionJson = statusMap?['action'];
              final retryNextVal = statusMap?['next'];
              state = state.copyWith(
                working: true,
                retryMessage: retryMsg,
                retryAction: retryActionJson is Map<String, dynamic>
                    ? RetryAction.fromJson(retryActionJson)
                    : null,
                retryNext: retryNextVal is int ? retryNextVal : null,
              );
            }
          } else if (isBusy) {
            if (!_aborting) {
              _optimisticBusy = true;
              state = state.copyWith(working: true, clearRetry: true);
            }
          }
        }
        break;
      case 'session.idle':
        if (sid != null) activity.setBusy(sid, false);
        if (forThisSession || sid == null) {
          _clearAbort();
          _optimisticBusy = false;
          state = state.copyWith(working: false, aborting: false);
          if (forThisSession) load();
        }
        break;
      case 'step-start':
      case 'busy':
        if (forThisSession || sid == null) {
          if (!_aborting) state = state.copyWith(working: true);
        }
        break;
      case 'step-finish':
      case 'idle':
        if (forThisSession || sid == null) {
          if (_aborting) {
            _optimisticBusy = false;
            _clearAbort();
            state = state.copyWith(working: false, aborting: false);
          } else {
            _optimisticBusy = false;
            state = state.copyWith(working: false);
          }
          if (forThisSession) load();
        }
        break;
      case 'server.reconnected':
        _verifySessionStatus();
        break;
      case 'session.error':
        if (forThisSession || sid == null) {
          _clearAbort();
          _optimisticBusy = false;
          final errorObj = props['error'];
          String? errorMessage;
          String? errorType;
          int? statusCode;
          if (errorObj is Map<String, dynamic>) {
            errorType = errorObj['name'] as String?;
            final data = errorObj['data'];
            if (data is Map<String, dynamic>) {
              errorMessage = data['message'] as String?;
              statusCode = data['statusCode'] as int?;
            }
            errorMessage ??= errorObj['name']?.toString();
          }
          state = state.copyWith(
            working: false,
            aborting: false,
            clearRetry: true,
            error: errorMessage,
            errorType: errorType,
            statusCode: statusCode,
          );
        }
        break;
      case 'session.compacted':
        if (forThisSession) {
          _tailWindow = initialLimit;
          load();
        }
        break;
    }
  }

  bool _deriveWorking(List<MessageWithParts> messages) {
    if (messages.isEmpty) return false;
    if (_abortGraceUntil != null &&
        DateTime.now().isBefore(_abortGraceUntil!)) {
      return false;
    }
    return isTailGenerating(messages);
  }

  /// The tail message's error, for the banner — so a turn that died explains
  /// itself instead of just going quiet. A user-initiated abort is terminal but
  /// not an error worth reporting.
  MessageInfo? _tailErrorInfo(List<MessageWithParts> messages) {
    if (messages.isEmpty) return null;
    final info = messages.last.info;
    if (info.role != 'assistant' || !info.hasError || info.wasAborted) {
      return null;
    }
    return info;
  }

  bool _computeWorking(List<MessageWithParts> messages) {
    if (_aborting) return false;
    if (_optimisticBusy) return true;
    return _deriveWorking(messages);
  }

  String? _sessionIdFromProps(Map<String, dynamic> props) {
    if (props['sessionID'] is String) return props['sessionID'] as String;
    final info = props['info'];
    if (info is Map && info['sessionID'] is String) {
      return info['sessionID'] as String;
    }
    final part = props['part'];
    if (part is Map && part['sessionID'] is String) {
      return part['sessionID'] as String;
    }
    return null;
  }

  Future<void> _verifySessionStatus() async {
    _stuck = false;
    _optimisticBusy = false;
    _lastSseActivity = null;
    final messages = state.messages;
    if (messages.isNotEmpty) {
      final last = messages.last;
      if (last.info.role == 'assistant' && last.info.timeCompleted == null) {
        state = state.copyWith(working: false, aborting: false);
        final client = _client;
        if (client != null) {
          try {
            await client.abort(sessionId);
          } catch (_) {}
        }
      }
    }
    load();
  }

  void _debouncedReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 200), load);
  }

  Future<void> send(
    String text, {
    ModelSelection? model,
    String? agent,
    List<Attachment> attachments = const [],
  }) async {
    final client = _client;
    if (client == null || text.trim().isEmpty) return;
    ref.read(ttsStateProvider.notifier).stop();
    final connected = ref.read(connectivityProvider);
    if (!connected) {
      final attachmentData = attachments
          .map((a) => {
                'name': a.name,
                'path': a.path,
                'mime': a.mime,
                'bytes': base64Encode(a.bytes),
              })
          .toList();
      await _messageQueue.enqueue(QueuedMessage(
        sessionId: sessionId,
        text: text.trim(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        model: model,
        agent: agent,
        attachmentData: attachmentData.isNotEmpty ? attachmentData : null,
      ));
      state = state.copyWith(
        error: 'Offline — message queued for later',
      );
      return;
    }
    _aborting = false;
    _optimisticBusy = true;
    ref.read(sessionActivityProvider.notifier).setBusy(sessionId, true);
    state = state.copyWith(
      sending: true,
      working: true,
      aborting: false,
      clearError: true,
      clearRetry: true,
    );
    try {
      await client.sendPromptAsync(
        sessionId: sessionId,
        text: text.trim(),
        model: model,
        agent: agent,
        attachments: attachments,
      );
      await load();
      _scheduleSettlingReloads();
    } catch (e) {
      final message = e is OpencodeApiException ? e.message : e.toString();
      _optimisticBusy = false;
      state = state.copyWith(error: message, working: false);
    } finally {
      state = state.copyWith(sending: false);
    }
  }

  void _scheduleSettlingReloads() {
    for (final delay in const [400, 1200, 2500, 4500]) {
      _settlingTimers.add(Timer(Duration(milliseconds: delay), () {
        if (!_aborting) load();
      }));
    }
  }

  void _clearAbort() {
    _abortTimer?.cancel();
    _abortTimer = null;
    _aborting = false;
  }

  Future<void> abort() async {
    final client = _client;
    if (client == null) return;
    _aborting = true;
    _optimisticBusy = false;
    _stuck = false;
    _abortGraceUntil = DateTime.now().add(const Duration(seconds: 5));
    state = state.copyWith(working: false, aborting: true, clearError: true);
    try {
      await client.abort(sessionId);
    } catch (_) {}
    _abortTimer?.cancel();
    _abortTimer = Timer(const Duration(seconds: 15), () {
      if (_aborting) {
        _clearAbort();
        state = state.copyWith(working: false, aborting: false);
      }
    });
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _partApplyTimer?.cancel();
    _deltaThrottleTimer?.cancel();
    _pollTimer?.cancel();
    _stuckTimer?.cancel();
    _abortTimer?.cancel();
    for (final t in _settlingTimers) {
      t.cancel();
    }
    _settlingTimers.clear();
    super.dispose();
  }
}

final chatControllerProvider = ChangeNotifierProvider.family
    .autoDispose<ChatController, String>((ref, sessionId) {
  return ChatController(ref, sessionId);
});

/// Whether a message renders anything at all. Messages with no visible parts
/// are hidden from the transcript.
bool messageHasVisibleContent(MessageWithParts m) {
  return m.parts.any(
    (p) =>
        (p.type == 'text' && (p.text?.trim().isNotEmpty ?? false)) ||
        p.type == 'tool' ||
        p.type == 'reasoning' ||
        p.type == 'file',
  );
}

/// The ordered ids of messages that currently render something.
///
/// This exists so the chat screen can depend on the *shape* of the transcript
/// (which rows exist, in what order) without depending on message content. A
/// streamed token grows the tail message's text but leaves this list identical,
/// so the screen — and therefore every other bubble — does not rebuild.
class VisibleMessageIds {
  const VisibleMessageIds(this.ids);

  final List<String> ids;

  int get length => ids.length;

  @override
  bool operator ==(Object other) {
    if (other is! VisibleMessageIds) return false;
    if (other.ids.length != ids.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (other.ids[i] != ids[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(ids);
}

final visibleMessageIdsProvider =
    Provider.family.autoDispose<VisibleMessageIds, String>((ref, sessionId) {
  final controller = ref.watch(chatControllerProvider(sessionId));
  return VisibleMessageIds([
    for (final m in controller.state.messages)
      if (messageHasVisibleContent(m)) m.info.id,
  ]);
});

/// A single message by id.
///
/// [MessageWithParts] has no `==`, so it compares by identity — and the
/// controller preserves the identity of every message it did not touch when
/// applying a delta. That makes this provider notify exactly one bubble: the
/// one whose content actually changed.
final chatMessageProvider =
    Provider.family.autoDispose<MessageWithParts?, ChatMessageRef>((ref, key) {
  final controller = ref.watch(chatControllerProvider(key.sessionId));
  for (final m in controller.state.messages) {
    if (m.info.id == key.messageId) return m;
  }
  return null;
});

/// Family key for [chatMessageProvider].
class ChatMessageRef {
  const ChatMessageRef(this.sessionId, this.messageId);

  final String sessionId;
  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageRef &&
      other.sessionId == sessionId &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(sessionId, messageId);
}

/// The coarse chat state the screen chrome depends on: loading/error/retry
/// flags plus the transcript shape. Deliberately excludes message content.
///
/// Records have structural equality, so watching this via `select` means a
/// streamed token — which changes none of these fields — does not rebuild the
/// screen, the app bar, or the composer.
typedef ChatChrome = ({
  bool loading,
  bool loadingOlder,
  bool hasMoreOlder,
  bool sending,
  bool working,
  bool aborting,
  bool hasMessages,
  String? error,
  String? errorType,
  int? statusCode,
  String? retryMessage,
  RetryAction? retryAction,
  int? retryNext,
});

ChatChrome chatChromeOf(ChatState s) => (
      loading: s.loading,
      loadingOlder: s.loadingOlder,
      hasMoreOlder: s.hasMoreOlder,
      sending: s.sending,
      working: s.working,
      aborting: s.aborting,
      hasMessages: s.messages.isNotEmpty,
      error: s.error,
      errorType: s.errorType,
      statusCode: s.statusCode,
      retryMessage: s.retryMessage,
      retryAction: s.retryAction,
      retryNext: s.retryNext,
    );
