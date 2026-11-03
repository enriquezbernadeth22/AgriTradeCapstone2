// On the mobile app text fields are pills, but a dropdown is a rounded
// rectangle.
import 'package:agritrade/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rounded = BorderRadius.circular(AppTheme.dropdownRadius);

  test('the registration dropdowns are rounded rectangles, not pills', () {
    for (final focused in [false, true]) {
      final border = AppTheme.registrationDropdownBorder(focused: focused);
      expect(border, isNot(isA<PillInputBorder>()));
      expect(border.borderRadius, rounded);
    }
  });

  testWidgets('a dropdown takes rounded corners even from the pill theme', (
    tester,
  ) async {
    late InputDecoration decoration;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          inputDecorationTheme: const InputDecorationTheme(
            enabledBorder: PillInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
          ),
        ),
        home: Builder(
          builder: (context) {
            decoration = AppTheme.dropdownDecoration(context);
            return const SizedBox();
          },
        ),
      ),
    );

    final enabled = decoration.enabledBorder! as OutlineInputBorder;
    expect(enabled, isNot(isA<PillInputBorder>()));
    expect(enabled.borderRadius, rounded);
    expect(enabled.borderSide.color, Colors.red);
  });
}
