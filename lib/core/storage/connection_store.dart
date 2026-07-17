import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

class StoredConnection {
  const StoredConnection({required this.config, this.password});

  final ServerConfig config;
  final String? password;
}

class ConnectionStore {
  ConnectionStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _configsKey = 'opencode_servers';
  static const _activeIdKey = 'opencode_active_server';
  static const _passwordPrefix = 'opencode_password_';

  final FlutterSecureStorage _secure;

  Future<List<ServerConfig>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(ServerConfig.fromJson)
        .toList();
  }

  Future<String?> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdKey);
  }

  Future<StoredConnection?> loadActive() async {
    final configs = await loadAll();
    if (configs.isEmpty) return null;
    final activeId = await loadActiveId();
    final config = activeId != null
        ? configs.where((c) => c.id == activeId).firstOrNull
        : configs.first;
    if (config == null) return null;
    final password = await _secure.read(key: '$_passwordPrefix${config.id}');
    return StoredConnection(config: config, password: password);
  }

  Future<String?> loadPassword(String serverId) async {
    return _secure.read(key: '$_passwordPrefix$serverId');
  }

  Future<void> saveAll(List<ServerConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _configsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  Future<void> setActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
  }

  Future<void> savePassword(String serverId, String? password) async {
    final key = '$_passwordPrefix$serverId';
    if (password != null && password.isNotEmpty) {
      await _secure.write(key: key, value: password);
    } else {
      await _secure.delete(key: key);
    }
  }

  Future<void> removePassword(String serverId) async {
    await _secure.delete(key: '$_passwordPrefix$serverId');
  }

  Future<void> addServer(ServerConfig config, String? password) async {
    final configs = await loadAll();
    configs.add(config);
    await saveAll(configs);
    await savePassword(config.id, password);
    await setActiveId(config.id);
  }

  Future<void> updateServer(ServerConfig config, String? password) async {
    final configs = await loadAll();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index == -1) return;
    configs[index] = config;
    await saveAll(configs);
    await savePassword(config.id, password);
  }

  Future<void> removeServer(String serverId) async {
    final configs = await loadAll();
    configs.removeWhere((c) => c.id == serverId);
    await saveAll(configs);
    await removePassword(serverId);
    final activeId = await loadActiveId();
    if (activeId == serverId && configs.isNotEmpty) {
      await setActiveId(configs.first.id);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final configs = await loadAll();
    await prefs.remove(_configsKey);
    await prefs.remove(_activeIdKey);
    for (final config in configs) {
      await removePassword(config.id);
    }
  }
}
