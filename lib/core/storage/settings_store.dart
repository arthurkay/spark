import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _themeModeKey = 'opencode_theme_mode';
  static const _collapseFilePermissionsKey =
      'opencode_collapse_file_permissions';
  static const _lastRouteKey = 'opencode_last_route';
  static const _scrollPositionPrefix = 'opencode_scroll_';
  static const _ttsVoiceNameKey = 'opencode_tts_voice_name';
  static const _ttsVoiceLocaleKey = 'opencode_tts_voice_locale';

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

  /// The narration voice, or null for the engine default.
  Future<({String name, String locale})?> loadTtsVoice() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_ttsVoiceNameKey);
    final locale = prefs.getString(_ttsVoiceLocaleKey);
    if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
      return null;
    }
    return (name: name, locale: locale);
  }

  Future<void> saveTtsVoice(String name, String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ttsVoiceNameKey, name);
    await prefs.setString(_ttsVoiceLocaleKey, locale);
  }

  Future<void> clearTtsVoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ttsVoiceNameKey);
    await prefs.remove(_ttsVoiceLocaleKey);
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
