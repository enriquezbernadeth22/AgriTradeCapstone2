// Product Details on stand-in Firebase (FirebaseRefs): Recommended Products
// lists other listings of the same product with stock; the row of tabs
// (Overview, Description, Reviews, Recommended) under the farmer chooses
// what shows below it, scrolls with the page, and never moves it.
import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/product_detail_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/widgets/section_tabs.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> listing(
  String name, {
  String farmer = 'f2',
  num quantity = 10,
  bool archived = false,
}) => {
  'name': name,
  'farmerId': farmer,
  'farmerName': 'Farmer $farmer',
  'category': 'Grains',
  'retailPrice': 60,
  'unit': 'kg',
  'quantity': quantity,
  'isArchived': archived,
  // Long enough that the page can bring each section up to the tabs.
  'description': List.filled(30, 'Fresh $name from the farm.').join(' '),
};

void main() {
  late FakeFirebaseFirestore db;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
    db = FakeFirebaseFirestore();
    await db
        .collection('products')
        .doc('p1')
        .set(listing('Corn', farmer: 'f1'));
    await db.collection('products').doc('p2').set(listing('Corn'));
    await db
        .collection('products')
        .doc('p3')
        .set(listing('Corn', farmer: 'f3', archived: true));
    await db
        .collection('products')
        .doc('p4')
        .set(listing('Corn', farmer: 'f4', quantity: 0));
    await db.collection('products').doc('p5').set(listing('Tomato'));
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'buyer1', email: 'maria@gmail.com'),
      ),
    );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProductDetailScreen(
          productId: 'p1',
          data: listing('Corn', farmer: 'f1'),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -6000),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Recommended Products: other Corn listings with stock only', (
    tester,
  ) async {
    await open(tester);
    await scrollToEnd(tester);
    expect(find.text('Recommended Products'), findsOneWidget);
    final list = find.byKey(const Key('recommendedProducts'));
    expect(list, findsOneWidget);
    // p2 only: not this listing, not the archived one, not the sold-out
    // one, not another product.
    expect(
      find.descendant(of: list, matching: find.textContaining('Corn')),
      findsOneWidget,
    );
    expect(find.textContaining('Tomato'), findsNothing);
  });

  testWidgets('the tabs stay in the page: no bar comes down at the top', (
    tester,
  ) async {
    await open(tester);
    await scrollToEnd(tester);
    expect(find.byType(SectionTabs), findsOneWidget);
    expect(find.byKey(const Key('sectionTabsBack')), findsNothing);
    // Back is over the photo.
    expect(find.byKey(const Key('productBack')), findsOneWidget);
  });

  testWidgets('a tab shows its section and does not move the page', (
    tester,
  ) async {
    await open(tester);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    // Overview: every section.
    for (final key in [
      'descriptionSection',
      'reviewsSection',
      'recommendedSection',
    ]) {
      expect(find.byKey(Key(key), skipOffstage: false), findsOneWidget);
    }
    scroll.jumpTo(60);
    await tester.pump();

    await tester.tap(find.byKey(const Key('sectionTab1')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, 60);
    expect(tester.widget<SectionTabs>(find.byType(SectionTabs)).active, 1);
    expect(
      find.byKey(const Key('descriptionSection'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reviewsSection'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const Key('recommendedSection'), skipOffstage: false),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('sectionTab3')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, 60);
    expect(
      find.byKey(const Key('recommendedSection'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('descriptionSection'), skipOffstage: false),
      findsNothing,
    );
  });
}
