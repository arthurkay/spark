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

final sessionDirectoryProvider =
    FutureProvider.family<String?, String>((ref, sessionId) async {
  final client = ref.watch(opencodeClientProvider);
  if (client == null) return null;
  final session = await client.getSession(sessionId);
  return session?.directory;
});

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
  });

  final List<MessageWithParts> messages;
  final bool loading;
  final bool loadingOlder;
  final bool hasMoreOlder;
  final bool sending;
  final bool working;
  final bool aborting;
  final String? error;

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
    );
  }
}

class ChatController extends ChangeNotifier {
  ChatController(this.ref, this.sessionId) {
    _init();
  }

  final Ref ref;
  final String sessionId;
  Timer? _reloadTimer;
  Timer? _pollTimer;
  Timer? _deltaThrottleTimer;
  Timer? _stuckTimer;
  Map<String, dynamic>? _pendingPartJson;
  bool _paused = false;
  bool _aborting = false;
  bool _optimisticBusy = false;
  bool _stuck = false;
  DateTime? _lastSseActivity;

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
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_paused) load();
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
    state = state.copyWith(working: false, clearError: true);
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
      state = state.copyWith(
        messages: merged,
        loading: false,
        clearError: true,
        working: working,
      );
      await CacheService.instance.write(_cacheKey, {
        'items': merged.map((m) => m.toJson()).toList(),
      });
    } on OpencodeApiException catch (e) {
      final cached = await CacheService.instance.read(_cacheKey);
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
      _reloadTimer?.cancel();
      _reloadTimer = Timer(const Duration(milliseconds: 200), apply);
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
        final statusType =
            status is Map ? status['type']?.toString() : status?.toString();
        final isBusy = statusType == 'busy';
        final isIdle = statusType == 'idle';
        if (sid != null) {
          activity.setBusy(sid, isBusy && !isIdle && !_aborting);
        }
        if (forThisSession || sid == null) {
          if (isIdle) {
            _clearAbort();
            _optimisticBusy = false;
            state = state.copyWith(working: false, aborting: false);
            if (forThisSession) load();
          } else if (isBusy) {
            _optimisticBusy = true;
            if (!_aborting) state = state.copyWith(working: true);
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
          state = state.copyWith(working: false, aborting: false);
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
    final last = messages.last;
    // Busy only while the model is actively generating at the tail of the
    // conversation. A stale, incomplete assistant message that another
    // message follows (e.g. after the server was restarted mid-turn) must
    // NOT keep the session flagged as working.
    if (last.info.role != 'assistant') return false;
    return last.info.timeCompleted == null;
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
      Timer(Duration(milliseconds: delay), () {
        if (!_aborting) load();
      });
    }
  }

  void _clearAbort() {
    _aborting = false;
  }

  Future<void> abort() async {
    final client = _client;
    if (client == null) return;
    _aborting = true;
    _optimisticBusy = false;
    _stuck = false;
    state = state.copyWith(working: false, aborting: true, clearError: true);
    try {
      await client.abort(sessionId);
    } catch (_) {}
    _clearAbort();
    state = state.copyWith(aborting: false);
    _scheduleSettlingReloads();
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    _deltaThrottleTimer?.cancel();
    _pollTimer?.cancel();
    _stuckTimer?.cancel();
    super.dispose();
  }
}

final chatControllerProvider =
    ChangeNotifierProvider.family<ChatController, String>((ref, sessionId) {
  return ChatController(ref, sessionId);
});
