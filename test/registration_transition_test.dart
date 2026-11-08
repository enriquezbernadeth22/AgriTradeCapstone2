// Moving between the registration steps feels like one screen: the header
// and the steps (1, 2, 3) stay exactly where they are, and only the content
// under them slides in, from the right going on and from the left going
// back.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/choose_role_screen.dart';
import 'package:agritrade/screen/register_screen.dart';
import 'package:agritrade/widgets/agri_app_bar.dart';
import 'package:agritrade/widgets/registration_step_indicator.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> openChooseRole(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChooseRoleScreen()),
              ),
              child: const Text('Log-in page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Log-in page'));
    await tester.pumpAndSettle();
  }

  Rect header(WidgetTester tester) =>
      tester.getRect(find.byType(AgriAppBar).last);
  Rect steps(WidgetTester tester) =>
      tester.getRect(find.byType(RegistrationStepIndicator).last);
  Finder title(String text) => find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.data == text &&
        w.style?.fontSize == AppTheme.pageTitle().fontSize,
  );

  testWidgets(
    'choosing a role: the header and steps stay, the form slides in',
    (tester) async {
      await openChooseRole(tester);
      final headerBefore = header(tester);
      final stepsBefore = steps(tester);

      await tester.tap(find.text('I\'m a Buyer'));
      // Past the card's short "chosen" moment, until the form opens.
      for (var i = 0; i < 60; i++) {
        if (find.byType(RegisterScreen).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(header(tester), headerBefore);
      expect(steps(tester), stepsBefore);
      // The content is still on its way in, from the right.
      final moving = tester.getCenter(title('Your Information')).dx;
      expect(moving, greaterThan(600 / 2));

      await tester.pumpAndSettle();
      expect(tester.getCenter(title('Your Information')).dx, closeTo(300, 1));
      expect(steps(tester), stepsBefore);
    },
  );

  testWidgets('going back to Choose Role: the cards come in from the left', (
    tester,
  ) async {
    await openChooseRole(tester);
    final stepsBefore = steps(tester);
    await tester.tap(find.text('I\'m a Buyer'));
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(RegisterScreen), findsNothing);
    expect(steps(tester), stepsBefore);
    final moving = tester.getCenter(title('How will you use AgriTrade+?')).dx;
    expect(moving, lessThan(600 / 2));

    await tester.pumpAndSettle();
    expect(
      tester.getCenter(title('How will you use AgriTrade+?')).dx,
      closeTo(300, 1),
    );
  });

  testWidgets('step 2 to 3 and back: only the content moves', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RegisterScreen(
          initialRole: 'buyer',
          draft: RegistrationDraft(
            firstName: 'Maria',
            lastName: 'Reyes',
            buyerDescription: 'Individual Consumer',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final headerBefore = header(tester);
    final stepsBefore = steps(tester);

    final next = find.widgetWithText(ElevatedButton, 'Continue');
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(header(tester), headerBefore);
    expect(steps(tester), stepsBefore);
    expect(tester.getCenter(title('Account Setup')).dx, greaterThan(600 / 2));
    await tester.pumpAndSettle();

    // Back to Your Information: in from the left this time.
    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(header(tester), headerBefore);
    expect(steps(tester), stepsBefore);
    expect(tester.getCenter(title('Your Information')).dx, lessThan(600 / 2));
  });

  testWidgets('with animations off, the content simply appears', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openChooseRole(tester);

    await tester.tap(find.text('I\'m a Buyer'));
    await tester.pump();
    await tester.pump();

    expect(tester.getCenter(title('Your Information')).dx, closeTo(300, 1));
  });
}
