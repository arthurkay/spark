import 'package:flutter/services.dart';

/// Thin semantic wrapper over [HapticFeedback].
///
/// Call sites should say what the interaction *means*, not which vibration
/// motor pattern they want — that keeps feedback consistent as the UI grows.
///
/// These all route through Android's `View.performHapticFeedback`, so no
/// `VIBRATE` permission is needed. Note that `shadcn_flutter`'s
/// `ThemeData.enableFeedback` is Flutter's click-sound/`Feedback.forTap` path
/// and does *not* produce haptics, so this has to be explicit.
abstract final class Haptics {
  /// Set to false to silence all haptics app-wide (e.g. from a user setting).
  static bool enabled = true;

  /// Moving through a set of options: list rows, filter chips, picker items,
  /// expand/collapse. The lightest tick available.
  static void selection() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  /// A discrete tap that did something: opening a sheet, toggling a control,
  /// dismissing. The default for ordinary buttons.
  static void tap() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  /// A committing action the user should feel land: sending a message,
  /// approving/denying a permission, confirming a delete.
  static void commit() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// A long-press that opened something.
  static void longPress() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// An action failed or was rejected.
  static void error() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }
}
