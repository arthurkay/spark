import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../core/storage/settings_store.dart';

class WindowBoundsListener extends WindowListener {
  Timer? _saveTimer;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    try {
      await SettingsStore().saveWindowBounds(await windowManager.getBounds());
    } catch (_) {}
  }

  @override
  void onWindowMove() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowClose() => _save();

  void dispose() => _saveTimer?.cancel();
}

Future<void> restoreWindowBounds() async {
  await windowManager.ensureInitialized();
  const minSize = Size(360, 520);
  await windowManager.setMinimumSize(minSize);
  final saved = await SettingsStore().loadWindowBounds();
  if (saved != null) {
    await windowManager.setBounds(
      Rect.fromLTWH(
        saved.left,
        saved.top,
        saved.width.clamp(minSize.width, 10000),
        saved.height.clamp(minSize.height, 10000),
      ),
      animate: false,
    );
  } else {
    await windowManager.setSize(const Size(1280, 800), animate: false);
    await windowManager.center(animate: false);
  }
  windowManager.addListener(WindowBoundsListener());
  await windowManager.waitUntilReadyToShow();
  await windowManager.show();
}
