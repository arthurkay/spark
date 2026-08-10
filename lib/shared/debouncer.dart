import 'dart:async';

/// Collapses a burst of calls into one, [delay] after the last.
///
/// Used for search fields whose result rebuilds a large list: reacting to every
/// keystroke means re-filtering and re-laying out the whole list faster than the
/// user can type, which shows up as input lag.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 180)});

  final Duration delay;
  Timer? _timer;
  void Function()? _pendingAction;

  void run(void Function() action) {
    _timer?.cancel();
    _pendingAction = action;
    _timer = Timer(delay, () {
      _pendingAction = null;
      action();
    });
  }

  /// Runs any pending action immediately.
  void flush() {
    final timer = _timer;
    final action = _pendingAction;
    if (timer != null && timer.isActive && action != null) {
      timer.cancel();
      _timer = null;
      _pendingAction = null;
      action();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pendingAction = null;
  }
}
