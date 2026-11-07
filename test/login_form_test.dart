// The Log In form itself, on stand-in Firebase (FirebaseRefs): its fields,
// the rounded-rectangle Log In button and the pill "Continue with Google".
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/widgets/login_form_fields.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    FirebaseRefs.useForTests(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(),
    );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: LoginFormFields(role: 'buyer')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('"Continue with Google" is a pill, Log In is not', (
    tester,
  ) async {
    await open(tester);
    final google = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Continue with Google'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(google.style!.shape!.resolve({}), isA<StadiumBorder>());
    final logIn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(logIn.style!.shape!.resolve({}), isNot(isA<StadiumBorder>()));
  });

  testWidgets('it fits a small phone', (tester) async {
    await open(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
