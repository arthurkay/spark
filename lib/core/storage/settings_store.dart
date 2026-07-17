import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _themeModeKey = 'opencode_theme_mode';
  static const _collapseFilePermissionsKey =
      'opencode_collapse_file_permissions';

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
}

final settingsStoreProvider = Provider<SettingsStore>((ref) {
  return SettingsStore();
});
