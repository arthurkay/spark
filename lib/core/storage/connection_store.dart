import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_connection.dart';

class StoredConnection {
  const StoredConnection({required this.connection, this.password});

  final ServerConnection connection;
  final String? password;
}

class ConnectionStore {
  ConnectionStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _connectionKey = 'opencode_connection';
  static const _passwordKey = 'opencode_password';

  final FlutterSecureStorage _secure;

  Future<StoredConnection?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_connectionKey);
    if (raw == null) return null;
    final connection = ServerConnection.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final password = await _secure.read(key: _passwordKey);
    return StoredConnection(connection: connection, password: password);
  }

  Future<void> save(ServerConnection connection, String? password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_connectionKey, jsonEncode(connection.toJson()));
    if (password != null && password.isNotEmpty) {
      await _secure.write(key: _passwordKey, value: password);
    } else {
      await _secure.delete(key: _passwordKey);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_connectionKey);
    await _secure.delete(key: _passwordKey);
  }
}
