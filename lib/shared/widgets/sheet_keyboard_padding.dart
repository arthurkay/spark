import 'package:flutter/widgets.dart';

import '../../app/motion.dart';

/// Lifts a sheet clear of the on-screen keyboard.
///
/// Uses [AnimatedPadding] so the sheet rides the keyboard instead of snapping
/// to its final position the instant the inset changes. The duration is
/// deliberately short — this is chasing a system animation that is already in
/// progress, not starting one.
class SheetKeyboardPadding extends StatelessWidget {
  final Widget child;

  const SheetKeyboardPadding({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.standard,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: child,
    );
  }
}
