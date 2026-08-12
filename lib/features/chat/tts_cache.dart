import '../../core/storage/cache_service.dart';

/// How many narrations to keep. Oldest-played are evicted first.
const _maxEntries = 50;

/// Narrations never go stale — the message they came from is immutable — so the
/// envelope's age check must not throw them away.
const _neverExpires = Duration(days: 3650);

const _cacheKey = 'tts/narrations.json';

/// What is currently stored, for the Settings screen.
class NarrationCacheStats {
  const NarrationCacheStats({required this.count, required this.bytes});

  final int count;
  final int bytes;

  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Stores the LLM-rewritten narration for a message so replaying it costs
/// nothing.
///
/// Preprocessing a message for speech is a full model round-trip that takes
/// seconds and shows a blocking overlay. The result only depends on the message
/// text, and an assistant message never changes once complete, so generating it
/// more than once is pure waste.
///
/// Entries are keyed by message id *and* a hash of the source text: if TTS was
/// started while the message was still streaming, the shorter text must not be
/// served for the finished message.
class NarrationCache {
  NarrationCache._();
  static final NarrationCache instance = NarrationCache._();

  /// Whole cache in one file: a few dozen short strings, so the rewrite cost per
  /// new narration is trivial and eviction needs no separate index.
  Map<String, dynamic>? _entries;
  List<String>? _order;
  bool _loaded = false;

  static String keyFor(String messageId, String sourceText) =>
      '$messageId:${_stableHash(sourceText)}';

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await CacheService.instance.read(
      _cacheKey,
      maxAge: _neverExpires,
    );
    final entries = raw?['entries'];
    final order = raw?['order'];
    _entries = entries is Map<String, dynamic> ? {...entries} : {};
    _order = order is List
        ? order.whereType<String>().toList()
        : <String>[..._entries!.keys];
  }

  Future<String?> read(String messageId, String sourceText) async {
    await _load();
    final key = keyFor(messageId, sourceText);
    final value = _entries![key];
    if (value is! String || value.isEmpty) return null;
    // Touch: most recently played is evicted last.
    _order!
      ..remove(key)
      ..add(key);
    // Fire and forget — losing an LRU touch costs nothing.
    _persist();
    return value;
  }

  Future<void> write(
    String messageId,
    String sourceText,
    String narration,
  ) async {
    if (narration.isEmpty) return;
    await _load();
    final key = keyFor(messageId, sourceText);
    _entries![key] = narration;
    _order!
      ..remove(key)
      ..add(key);
    while (_order!.length > _maxEntries) {
      _entries!.remove(_order!.removeAt(0));
    }
    await _persist();
  }

  Future<NarrationCacheStats> stats() async {
    await _load();
    var bytes = 0;
    for (final value in _entries!.values) {
      if (value is String) bytes += value.length;
    }
    return NarrationCacheStats(count: _entries!.length, bytes: bytes);
  }

  Future<void> clear() async {
    _entries = {};
    _order = [];
    _loaded = true;
    await CacheService.instance.delete(_cacheKey);
  }

  Future<void> _persist() async {
    await CacheService.instance.write(_cacheKey, {
      'entries': _entries,
      'order': _order,
    });
  }
}

/// FNV-1a. `String.hashCode` is not guaranteed stable across runs, and this key
/// has to survive a restart.
String _stableHash(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}
