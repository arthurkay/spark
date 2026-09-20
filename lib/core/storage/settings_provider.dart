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

final collapseToolWidgetsProvider =
    StateNotifierProvider<CollapseToolWidgetsNotifier, bool>((ref) {
      return CollapseToolWidgetsNotifier(ref);
    });

class CollapseToolWidgetsNotifier extends StateNotifier<bool> {
  CollapseToolWidgetsNotifier(this.ref) : super(true) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final stored = await ref
        .read(settingsStoreProvider)
        .loadCollapseToolWidgets();
    if (mounted) state = stored;
  }

  Future<void> toggle() async {
    state = !state;
    await ref.read(settingsStoreProvider).saveCollapseToolWidgets(state);
  }
}

final autoApprovePermissionsProvider =
    StateNotifierProvider<AutoApprovePermissionsNotifier, bool>((ref) {
      return AutoApprovePermissionsNotifier(ref);
    });

class AutoApprovePermissionsNotifier extends StateNotifier<bool> {
  AutoApprovePermissionsNotifier(this.ref) : super(false) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final stored = await ref
        .read(settingsStoreProvider)
        .loadAutoApprovePermissions();
    if (mounted) state = stored;
  }

  Future<void> toggle() async {
    state = !state;
    await ref.read(settingsStoreProvider).saveAutoApprovePermissions(state);
  }

  Future<void> setValue(bool value) async {
    state = value;
    await ref.read(settingsStoreProvider).saveAutoApprovePermissions(state);
  }
}
