import 'package:flutter/widgets.dart';

class SheetKeyboardPadding extends StatelessWidget {
  final Widget child;

  const SheetKeyboardPadding({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: child,
    );
  }
}
