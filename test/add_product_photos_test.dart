// Add Product's photos (the user's design, 2026-11-08): "Add Photos (up to
// 5)" over one row of five equal squares — the photos with a × at the
// corner, the dashed "+ Add Photo" while there is room, dashed empty
// places for the rest.
import 'dart:io';

import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/screen/add_product_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    FirebaseRefs.useForTests(
      firestore: FakeFirebaseFirestore(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'f1')),
    );
  });
  tearDown(FirebaseRefs.reset);

  Future<void> open(WidgetTester tester, {Map<String, dynamic>? data}) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddProductScreen(
          productId: data == null ? null : 'p1',
          existingData: data,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Network photos cannot load in a test; that is not what is checked.
    tester.takeException();
  }

  Size sizeOf(WidgetTester tester, Finder f) => tester.getSize(f);

  testWidgets('a new listing: the heading, then Add Photo and four empty '
      'places, all the same size', (tester) async {
    await open(tester);
    expect(find.text('Add Photos'), findsOneWidget);
    expect(find.text('(up to 5)'), findsOneWidget);
    final row = find.byKey(const Key('photoRow'));
    expect(row, findsOneWidget);
    final add = find.byKey(const Key('addPhoto'));
    expect(add, findsOneWidget);
    expect(find.text('Add Photo'), findsOneWidget);
    // Five squares across the row.
    final squares = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width != null &&
            w.width!.isFinite &&
            w.width! > 30 &&
            w.width == w.height,
      ),
    );
    expect(squares, findsNWidgets(5));
    final first = sizeOf(tester, squares.first);
    expect(first.width, first.height);
    expect(find.byKey(const Key('mainPhoto')), findsNothing);
  });

  testWidgets('with two photos: both with a ×, then Add Photo, then two '
      'empty places', (tester) async {
    await open(
      tester,
      data: {
        'farmerId': 'f1',
        'name': 'Eggplant',
        'category': 'Vegetables',
        'price': 60,
        'unit': 'kg',
        'quantity': 10,
        'imageUrls': ['https://x.test/a.jpg', 'https://x.test/b.jpg'],
      },
    );
    expect(find.byKey(const Key('mainPhoto')), findsOneWidget);
    expect(find.byKey(const Key('removePhoto0')), findsOneWidget);
    expect(find.byKey(const Key('removePhoto1')), findsOneWidget);
    expect(find.byKey(const Key('addPhoto')), findsOneWidget);
    // The × sits at the photo's top right corner.
    final photo = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const Key('mainPhoto')),
            matching: find.byType(Stack),
          )
          .first,
    );
    final x = tester.getRect(find.byKey(const Key('removePhoto0')));
    expect(x.right, lessThanOrEqualTo(photo.right));
    expect(x.top, greaterThanOrEqualTo(photo.top));
    expect(x.center.dx, greaterThan(photo.center.dx));
    expect(x.center.dy, lessThan(photo.center.dy));

    // Taking the second one out leaves the main photo.
    await tester.tap(find.byKey(const Key('removePhoto1')));
    await tester.pump();
    tester.takeException();
    expect(find.byKey(const Key('removePhoto1')), findsNothing);
    expect(find.byKey(const Key('mainPhoto')), findsOneWidget);
  });
}
