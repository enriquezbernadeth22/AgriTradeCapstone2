// Back on a registration form with something filled in asks first, so a
// slip of the thumb does not lose it; an empty form just goes back.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1000);
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
                MaterialPageRoute(
                  builder: (_) => const RegisterScreen(initialRole: 'buyer'),
                ),
              ),
              child: const Text('Choose role'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose role'));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pumpAndSettle();
  }

  testWidgets('an empty form just goes back', (tester) async {
    await openForm(tester);
    await back(tester);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('Leave registration?'), findsNothing);
  });

  testWidgets('with something filled in, Back asks first', (tester) async {
    await openForm(tester);
    await tester.enterText(find.byType(TextField).first, 'Juan');
    await tester.pump();

    await back(tester);
    expect(find.text('Leave registration?'), findsOneWidget);

    // Keep Editing stays, with the name still there.
    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Juan'), findsWidgets);

    // Leave goes back.
    await back(tester);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
  });
}
