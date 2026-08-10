import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Top-level so they can run in an isolate via compute().
String _encodeJson(Map<String, dynamic> value) => jsonEncode(value);

Map<String, dynamic>? _decodeJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

class CacheService {
  CacheService._();
  static final CacheService instance = CacheService._();

  Directory? _cacheDir;

  Future<Directory> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  Future<void> write(String key, Map<String, dynamic> data) async {
    final dir = await _dir;
    final file = File('${dir.path}/$key');
    await file.parent.create(recursive: true);
    final envelope = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    // Encode off the UI isolate: serialising a whole message list (including
    // every tool output blob) is easily a multi-frame stall on the main isolate,
    // and this runs while responses are streaming.
    final encoded = await compute(_encodeJson, envelope);
    await file.writeAsString(encoded);
  }

  Future<Map<String, dynamic>?> read(
    String key, {
    Duration maxAge = const Duration(hours: 24),
  }) async {
    try {
      final dir = await _dir;
      final file = File('${dir.path}/$key');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final envelope = await compute(_decodeJson, raw);
      if (envelope == null) return null;
      final ts = envelope['timestamp'] as int?;
      if (ts != null) {
        final age = DateTime.now().millisecondsSinceEpoch - ts;
        if (age > maxAge.inMilliseconds) return null;
      }
      return envelope['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String key) async {
    try {
      final dir = await _dir;
      final file = File('${dir.path}/$key');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final dir = await _dir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
