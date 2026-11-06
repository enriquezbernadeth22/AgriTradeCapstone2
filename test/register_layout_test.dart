// How the registration form is laid out over its two steps after Choose
// Role: Your Information ends with Continue, in the form; Account Setup has
// the Register button, which floats while the end of the form is off screen
// and rests under the terms and the review reminder once it is not.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const reminder =
    'Please review the information you entered before registering. '
    'Make sure your name, email and mobile number are correct.';

Finder get registerButton => find.widgetWithText(ElevatedButton, 'Register');
Finder get continueButton => find.widgetWithText(ElevatedButton, 'Continue');
Finder get terms => find.textContaining('I agree to the', findRichText: true);

/// A step's page title; the step names under the progress circles are
/// small, so this finds the title alone.
Finder pageTitle(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data == text && w.style?.fontSize == 24,
);

/// What a person has filled in on Your Information, so Continue goes on.
RegistrationDraft filledIn(String role) => role == 'farmer'
    ? const RegistrationDraft(
        firstName: 'Juan',
        lastName: 'Santos',
        rsbaNumber: '041012000123456',
        barangay: 'Balakilong',
        farmerDescription: 'Crop Farmer',
      )
    : const RegistrationDraft(
        firstName: 'Maria',
        lastName: 'Reyes',
        buyerDescription: 'Individual Consumer',
      );

Future<void> pumpForm(
  WidgetTester tester, {
  String role = 'farmer',
  double width = 600,
  bool filled = false,
}) async {
  // Wide, because the test font is much wider than Montserrat.
  tester.view.physicalSize = Size(width, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RegisterScreen(
        initialRole: role,
        draft: filled ? filledIn(role) : null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the form at Account Setup, the step with Register.
Future<void> pumpAccountSetup(
  WidgetTester tester, {
  String role = 'farmer',
  double width = 600,
}) async {
  await pumpForm(tester, role: role, width: width, filled: true);
  await tester.ensureVisible(continueButton);
  await tester.pumpAndSettle();
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
  expect(pageTitle('Account Setup'), findsOneWidget);
}

Future<void> scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -5000));
  await tester.pumpAndSettle();
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Your Information ends with Continue, and has no Register', (
    tester,
  ) async {
    await pumpForm(tester);
    expect(pageTitle('Your Information'), findsOneWidget);
    expect(registerButton, findsNothing);
    await scrollToEnd(tester);
    expect(tester.getRect(continueButton).bottom, lessThanOrEqualTo(720));
  });

  testWidgets('at the top of Account Setup, only the Register button shows', (
    tester,
  ) async {
    await pumpAccountSetup(tester);
    expect(tester.getRect(registerButton).bottom, closeTo(720 - 6, 1));
    // The terms and the reminder are further down the form.
    expect(tester.getRect(find.text(reminder)).top, greaterThan(720));
  });

  testWidgets('at the end, the button rests under the terms and reminder', (
    tester,
  ) async {
    await pumpAccountSetup(tester);
    await scrollToEnd(tester);

    final button = tester.getRect(registerButton);
    expect(tester.getRect(terms).bottom, lessThanOrEqualTo(button.top));
    expect(
      tester.getRect(find.text(reminder)).bottom,
      lessThanOrEqualTo(button.top),
    );
    expect(button.bottom, lessThanOrEqualTo(720));
  });

  testWidgets('at the end, no big empty space is left under the button', (
    tester,
  ) async {
    await pumpAccountSetup(tester);
    await scrollToEnd(tester);
    expect(720 - tester.getRect(registerButton).bottom, lessThanOrEqualTo(32));
  });

  testWidgets('it still fits at large text sizes', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Wider still: the test font at this size is wider than any phone.
    await pumpAccountSetup(tester, width: 900);
    await scrollToEnd(tester);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(registerButton);
    expect(
      tester.getRect(find.text(reminder)).bottom,
      lessThanOrEqualTo(button.top),
    );
    expect(button.bottom, lessThanOrEqualTo(720));
  });

  testWidgets('scrolling back up floats the button again', (tester) async {
    await pumpAccountSetup(tester);
    await scrollToEnd(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(registerButton).bottom, closeTo(720 - 6, 1));
  });

  testWidgets('the buyer form ends the same way', (tester) async {
    await pumpAccountSetup(tester, role: 'buyer');
    await scrollToEnd(tester);
    final button = tester.getRect(registerButton);
    expect(
      tester.getRect(find.text(reminder)).bottom,
      lessThanOrEqualTo(button.top),
    );
    expect(button.bottom, lessThanOrEqualTo(720));
  });

  testWidgets('each step\'s title and "Registering as" are centred', (
    tester,
  ) async {
    await pumpForm(tester, filled: true);
    expect(
      tester.getCenter(pageTitle('Your Information')).dx,
      closeTo(600 / 2, 1),
    );
    for (final text in ['Registering as Farmer']) {
      expect(tester.getCenter(find.text(text)).dx, closeTo(600 / 2, 1));
    }
    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(pageTitle('Account Setup')).dx,
      closeTo(600 / 2, 1),
    );
    for (final text in ['Registering as Farmer']) {
      expect(tester.getCenter(find.text(text)).dx, closeTo(600 / 2, 1));
    }
  });

  testWidgets('the farmer form is in the agreed order', (tester) async {
    double top(Finder finder) => tester.getRect(finder).top;

    await pumpForm(tester, filled: true);
    final information = [
      top(find.text('First Name')),
      top(find.text('Last Name')),
      top(find.text('RSBSA No.')),
      top(find.text('Only farmers from Laurel, Batangas may register.')),
      top(find.text('Barangay (Laurel)')),
    ];
    expect(information, orderedEquals([...information]..sort()));

    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    final account = [
      top(find.text('Email Address')),
      top(find.text('Mobile Number')),
      top(find.text('Password')),
      top(find.text('Confirm Password')),
      top(find.textContaining('Supported Products', findRichText: true)),
      top(terms),
      top(find.text(reminder)),
    ];
    expect(account, orderedEquals([...account]..sort()));
  });

  testWidgets('a buyer sees none of the farmer-only parts', (tester) async {
    await pumpForm(tester, role: 'buyer', filled: true);
    expect(find.text('RSBSA No.'), findsNothing);
    expect(find.textContaining('Only farmers from Laurel'), findsNothing);
    expect(find.text('Barangay (Laurel)'), findsNothing);

    await tester.ensureVisible(continueButton);
    await tester.pumpAndSettle();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Supported Products', findRichText: true),
      findsNothing,
    );
    // Required for buyers too, so no "(optional)".
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Mobile Number (optional)'), findsNothing);
  });
}
