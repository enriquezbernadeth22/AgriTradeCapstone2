// The mobile app's text fields are pills on one line and keep rounded
// corners once they are several lines tall (PillInputBorder).
import 'package:agritrade/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  const border = PillInputBorder(borderSide: BorderSide(color: Colors.grey));

  test('a one-line field is a pill: its corner is cut by a half-circle', () {
    final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 200, 48));
    // Inside the box but outside the 24px round end.
    expect(path.contains(const Offset(4, 4)), isFalse);
    expect(path.contains(const Offset(24, 24)), isTrue);
  });

  test('a several-line field keeps small rounded corners, not round ends', () {
    final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 200, 120));
    // Inside a 16px corner; a pill's 60px round end would leave it out.
    expect(path.contains(const Offset(8, 8)), isTrue);
    expect(path.contains(const Offset(1, 1)), isFalse);
  });

  test('focus colours and animations keep the pill shape', () {
    final focused = border.copyWith(
      borderSide: const BorderSide(color: Colors.green, width: 1.4),
    );
    expect(focused, isA<PillInputBorder>());
    expect(focused.borderSide.color, Colors.green);
    expect(border.lerpTo(focused, 0.5), isA<PillInputBorder>());
    expect(focused.lerpFrom(border, 0.5), isA<PillInputBorder>());
    expect(border.scale(2), isA<PillInputBorder>());
  });

  testWidgets('every text field in the app uses the pill outline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: const Scaffold(body: TextField()),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(TextField)));
    final inputs = theme.inputDecorationTheme;
    expect(inputs.border, isA<PillInputBorder>());
    expect(inputs.enabledBorder, isA<PillInputBorder>());
    expect(inputs.focusedBorder, isA<PillInputBorder>());
  });
}
