// A farmer's own listings on Profile, on stand-in Firebase (FirebaseRefs):
// a listing the AgriTrade+ team took off the marketplace (its product was
// removed or archived in Price Management) is not with the Active ones; it
// is with the archived ones, marked UNAVAILABLE and saying why.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/farmer_profile_tab.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
    final db = FakeFirebaseFirestore();
    Map<String, dynamic> listing(String name, [Map<String, dynamic>? more]) => {
      'name': name,
      'farmerId': 'f1',
      'price': 60,
      'unit': 'kg',
      'quantity': 10,
      ...?more,
    };
    await db.collection('products').doc('corn').set(listing('Corn'));
    await db
        .collection('products')
        .doc('ube')
        .set(
          listing('Ube', {
            'isSuspended': true,
            'moderationStatus': 'commodity_archived',
            'moderationReason': '',
          }),
        );
    await db
        .collection('products')
        .doc('okra')
        .set(listing('Okra', {'isArchived': true}));
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'f1', email: 'juan@gmail.com'),
      ),
    );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ProfileTab()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a listing whose product was removed is not Active', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Corn'), findsOneWidget);
    expect(find.text('Ube'), findsNothing);
    expect(find.text('Okra'), findsNothing);
  });

  testWidgets('it is with the archived ones, marked and explained', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Archived').first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ube'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    expect(
      find.textContaining('Ube is no longer sold on AgriTrade+'),
      findsOneWidget,
    );
    // The farmer's own archived listing, as before.
    expect(find.text('Okra'), findsOneWidget);
    expect(find.text('ARCHIVED'), findsOneWidget);
    expect(find.text('Corn'), findsNothing);
  });
}
