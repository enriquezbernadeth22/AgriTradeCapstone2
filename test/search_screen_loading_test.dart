// The Search screen opens without its sections jumping: until Trending,
// Recent and the last "Clear" have answered, Trending and Recent hold their
// places with placeholder pills and Recommended Products waits; then the
// three show in their order — Trending, Recent, Recommended.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/buyer_search_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/services/search_trends.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    final today = trendDayKey(DateTime.now());
    for (final term in ['mani', 'sander']) {
      await db.collection('searchTrends').doc(term).set({
        'term': term,
        'days': {today: 5},
        'updatedAt': Timestamp.now(),
      });
    }
    await db.collection('searchEvents').add({
      'userId': 'b1',
      'query': 'balinghoy',
      'createdAt': Timestamp.now(),
    });
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'b1', email: 'b@gmail.com'),
      ),
    );
  });
  tearDown(FirebaseRefs.reset);

  testWidgets('placeholders first, then Trending, Recent, Recommended', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BuyerSearchScreen(),
      ),
    );
    // The very first frame: places held, Recommended not yet there.
    expect(find.byKey(const Key('searchHistoryLoading')), findsOneWidget);
    expect(find.text('Recommended Products'), findsNothing);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('searchHistoryLoading')), findsNothing);
    expect(find.text('mani'), findsOneWidget);
    expect(find.text('balinghoy'), findsOneWidget);
    final trending = tester.getTopLeft(find.text('Trending Searches')).dy;
    final recent = tester.getTopLeft(find.text('Recent Searches')).dy;
    final recommended = tester.getTopLeft(find.text('Recommended Products')).dy;
    expect(trending, lessThan(recent));
    expect(recent, lessThan(recommended));
  });
}
