// The app's Forgot Password screen has the logo and name in its header, beside
// Back. The Admin Portal's form, on the same screen file, has no such header.
import 'package:agritrade/screen/forgot_password_screen.dart';
import 'package:agritrade/widgets/agri_app_bar.dart';
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Back, the logo and the name are in the header', (tester) async {
    await open(tester);

    final logo = find.descendant(
      of: find.byType(AgriAppBar),
      matching: find.byType(AgriTradeLogoMark),
    );
    final name = find.descendant(
      of: find.byType(AgriAppBar),
      matching: find.byType(AgriTradeText),
    );
    final back = find.descendant(
      of: find.byType(AgriAppBar),
      matching: find.byType(IconButton),
    );
    expect(logo, findsOneWidget);
    expect(name, findsOneWidget);
    expect(back, findsOneWidget);
    expect(tester.getTopLeft(back).dx, lessThan(tester.getTopLeft(logo).dx));
    expect(tester.getTopLeft(logo).dx, lessThan(tester.getTopLeft(name).dx));
    expect((tester.getCenter(logo).dy - tester.getCenter(back).dy).abs(), 0);
  });

  testWidgets('the logo appears only once, with no big one on the page', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(AgriTradeText), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.height == 100),
      findsNothing,
    );
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
  });

  testWidgets('Back leaves the screen', (tester) async {
    await open(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AgriAppBar),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
