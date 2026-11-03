// Forgot Password slides in on the first tap, and only then puts the cursor in
// the email field. Focusing at once opened the keyboard during the slide, and
// on the first open in an app run the page showed up with no slide at all.
import 'package:agritrade/screen/forgot_password_screen.dart';
import 'package:agritrade/screen/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> tapForgotPassword(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                slideRoute(const ForgotPasswordScreen()),
              ),
              child: const Text('Forgot password?'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
  }

  bool emailFocused(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('no keyboard while the page slides in', (tester) async {
    await tapForgotPassword(tester);
    await tester.pump(const Duration(milliseconds: 150));

    // Part way in, from the right.
    final left = tester.getTopLeft(find.text('Reset your password')).dx;
    expect(left, greaterThan(24));
    expect(emailFocused(tester), isFalse);
  });

  testWidgets('the email field is ready to type in once it is in', (
    tester,
  ) async {
    await tapForgotPassword(tester);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Reset your password')).dx, 24);
    expect(emailFocused(tester), isTrue);
  });

  testWidgets('leaving during the slide does not fail', (tester) async {
    await tapForgotPassword(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
