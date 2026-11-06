// The registration progress shows each step's name under its circle, ticks
// off the steps already done, and cannot be tapped.
import 'package:agritrade/widgets/registration_step_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> show(WidgetTester tester, int step) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: RegistrationStepIndicator(step: step),
        ),
      ),
    ),
  );

  testWidgets('every step is named under its circle', (tester) async {
    await show(tester, 1);
    for (final label in ['Choose Role', 'Your Information', 'Account Setup']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('steps already done show a tick, the rest their number', (
    tester,
  ) async {
    await show(tester, 3);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await show(tester, 1);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the active step\'s name stands out', (tester) async {
    await show(tester, 2);
    FontWeight? weight(String label) =>
        tester.widget<Text>(find.text(label)).style?.fontWeight;
    expect(weight('Your Information'), FontWeight.w700);
    expect(weight('Choose Role'), isNot(FontWeight.w700));
    expect(weight('Account Setup'), isNot(FontWeight.w700));
  });

  testWidgets('the circles are display-only', (tester) async {
    await show(tester, 2);
    final indicator = find.byType(RegistrationStepIndicator);
    expect(
      find.descendant(of: indicator, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(
      find.descendant(of: indicator, matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('a 320-wide phone fits it without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final step in [1, 2, 3]) {
      await show(tester, step);
      expect(tester.takeException(), isNull);
    }
  });
}
