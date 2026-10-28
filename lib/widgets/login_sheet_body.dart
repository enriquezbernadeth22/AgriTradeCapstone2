import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What sits on the white sheet of the login screens (the app's front door,
/// RoleSelectionScreen, and LoginScreen): the title, the form and "Create
/// One." With the keyboard down it fits the sheet and does not scroll —
/// made a little smaller on a short screen — so the form looks the same on
/// every phone. With the keyboard up it scrolls, to reach every field.
class LoginSheetBody extends StatelessWidget {
  final bool keyboardOpen;
  final Widget child;

  /// The form's widest (on the web: not stretched across a wide window).
  final double maxWidth;

  const LoginSheetBody({
    super.key,
    required this.keyboardOpen,
    required this.child,
    this.maxWidth = double.infinity,
  });

  /// Around the form on the sheet.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(28, 36, 28, 24);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: padding,
        physics: keyboardOpen ? null : const NeverScrollableScrollPhysics(),
        // The same widgets with the keyboard up or down (only sizes
        // change), so the field being typed in keeps its focus.
        child: SizedBox(
          height: keyboardOpen
              ? null
              : math.max(0, box.maxHeight - padding.vertical),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: math.min(box.maxWidth - padding.horizontal, maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
