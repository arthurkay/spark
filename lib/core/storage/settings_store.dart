import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _themeModeKey = 'opencode_theme_mode';
  static const _collapseFilePermissionsKey =
      'opencode_collapse_file_permissions';
  static const _lastRouteKey = 'opencode_last_route';
  static const _scrollPositionPrefix = 'opencode_scroll_';

  Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey) ?? 'system';
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
  }

  Future<bool> loadCollapseFilePermissions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_collapseFilePermissionsKey) ?? false;
  }

  Future<void> saveCollapseFilePermissions(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_collapseFilePermissionsKey, value);
  }

  Future<String?> loadLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRouteKey);
  }

  Future<void> saveLastRoute(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRouteKey, route);
  }

  Future<double?> loadScrollPosition(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_scrollPositionPrefix$key');
  }

  Future<void> saveScrollPosition(String key, double offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_scrollPositionPrefix$key', offset);
  }
}

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return SettingsStore();
});
