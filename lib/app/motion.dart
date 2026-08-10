import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Central motion tokens.
///
/// Durations and curves live here so motion reads as one system instead of a
/// per-widget guess. Prefer these over inline `Duration(milliseconds: ...)` /
/// `Curves.*` literals.
///
/// Scale rationale: a transition should be just long enough to be read as
/// movement and no longer. Anything the user triggers and waits on stays under
/// ~200ms; only full-page changes go longer.
abstract final class Motion {
  /// State changes on a control the finger is still on — press, toggle,
  /// hover, colour shifts. Matches shadcn's internal `kDefaultDuration`.
  static const fast = Duration(milliseconds: 150);

  /// The default for anything that changes layout or visibility in place:
  /// expand/collapse, banner in/out, cross-fades.
  static const base = Duration(milliseconds: 220);

  /// Larger in-place changes that move a lot of pixels and need a beat longer
  /// to stay legible.
  static const slow = Duration(milliseconds: 320);

  /// Looping ambient animations (typing dots, shimmer sweep).
  static const ambient = Duration(milliseconds: 1200);

  /// Shimmer sweep — deliberately slower than [ambient] so it reads as a
  /// background texture rather than an active indicator.
  static const shimmer = Duration(milliseconds: 1500);

  /// Entry animation for a newly arrived list item.
  static const entry = Duration(milliseconds: 260);

  /// Standard easing: fast out of the gate, settling gently. Correct for
  /// almost everything that enters or moves toward a resting state.
  static const standard = Curves.easeOutCubic;

  /// For elements leaving the screen — accelerating away needs no settle.
  static const exit = Curves.easeInCubic;

  /// Symmetric easing, for things that both grow and shrink (expand/collapse).
  static const inOut = Curves.easeInOutCubic;

  /// Slight overshoot, for elements that should feel physical on entry.
  /// Use sparingly — one or two places, not everywhere.
  static const emphasized = Curves.easeOutBack;
}
