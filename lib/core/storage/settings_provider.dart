import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'settings_store.dart';

ThemeMode themeModeFromString(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

String themeModeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, String>((
  ref,
) {
  return ThemeModeNotifier(ref);
});

class ThemeModeNotifier extends StateNotifier<String> {
  ThemeModeNotifier(this.ref) : super('system') {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final stored = await ref.read(settingsStoreProvider).loadThemeMode();
    if (mounted) state = stored;
  }

  Future<void> setMode(String mode) async {
    state = mode;
    await ref.read(settingsStoreProvider).saveThemeMode(mode);
  }
}

final collapseFilePermissionsProvider =
    StateNotifierProvider<CollapseFilePermissionsNotifier, bool>((ref) {
  return CollapseFilePermissionsNotifier(ref);
});

class CollapseFilePermissionsNotifier extends StateNotifier<bool> {
  CollapseFilePermissionsNotifier(this.ref) : super(false) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final stored =
        await ref.read(settingsStoreProvider).loadCollapseFilePermissions();
    if (mounted) state = stored;
  }

  Future<void> toggle() async {
    state = !state;
    await ref.read(settingsStoreProvider).saveCollapseFilePermissions(state);
  }
}
