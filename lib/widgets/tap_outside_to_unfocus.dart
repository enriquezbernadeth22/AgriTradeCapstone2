import 'package:flutter/widgets.dart';

/// Tapping anywhere that is not itself something to tap — the page, a
/// card, the space between fields — takes the focus out of the text field
/// being typed in, and the phone's keyboard goes away. Buttons, other
/// fields and list rows keep their own taps (they win the gesture), so
/// tapping Send or another field still does what it should.
class TapOutsideToUnfocus extends StatelessWidget {
  final Widget child;

  const TapOutsideToUnfocus({super.key, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () {
      final focus = FocusManager.instance.primaryFocus;
      // Only a text field's focus: a key handler or a dialog keeps its own.
      final context = focus?.context;
      if (context == null) return;
      if (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null) {
        focus!.unfocus();
      }
    },
    child: child,
  );
}
