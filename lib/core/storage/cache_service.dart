import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    await file.writeAsString(jsonEncode(envelope));
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
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
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
