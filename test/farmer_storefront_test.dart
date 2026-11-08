import 'package:agritrade/screen/farmer_storefront_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<FakeFirebaseFirestore> _farmerWithOneReview() async {
  final db = FakeFirebaseFirestore();
  await db.collection('publicProfiles').doc('f1').set({
    'name': 'Juan Dela Cruz',
    'barangay': 'Bugaan East',
    'municipality': 'Laurel',
    'approvalStatus': 'approved',
  });
  await db.collection('productReviews').doc('r1').set({
    'sellerId': 'f1',
    'buyerId': 'b1',
    'buyerName': 'Maria Santos',
    'rating': 4,
    'comment': 'Fresh and well packed.',
    'productName': 'Eggplant',
    'createdAt': Timestamp.fromDate(DateTime(2026, 11, 2)),
  });
  await db.collection('products').doc('p1').set({
    'farmerId': 'f1',
    'name': 'Eggplant',
    'category': 'Vegetables',
    'price': 60,
    'unit': 'kg',
    'stock': 20,
  });
  return db;
}

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: FarmerStorefrontScreen(farmerId: 'f1')),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(FirebaseRefs.reset);

  testWidgets('the farmer photo has a full gold ring and a verified badge', (
    tester,
  ) async {
    FirebaseRefs.useForTests(
      firestore: await _farmerWithOneReview(),
      auth: MockFirebaseAuth(),
    );
    await _open(tester);

    final ring = tester.widget<Container>(
      find.byKey(const Key('storefrontGoldRing')),
    );
    final border = (ring.decoration! as BoxDecoration).border! as Border;
    // The same gold all the way round: a full circle, not an arc.
    expect(border.isUniform, isTrue);
    expect(border.top.color, const Color(0xFFF5BB24));
    expect(find.byKey(const Key('storefrontVerifiedBadge')), findsOneWidget);
  });

  testWidgets('a line follows the header and reviews show their rating', (
    tester,
  ) async {
    FirebaseRefs.useForTests(
      firestore: await _farmerWithOneReview(),
      auth: MockFirebaseAuth(),
    );
    await _open(tester);

    expect(find.byKey(const Key('storefrontDivider')), findsOneWidget);
    expect(find.byKey(const Key('storefrontStats')), findsNothing);
    expect(find.text('Reviews (1)'), findsOneWidget);
    final summary = find.byKey(const Key('storefrontRatingSummary'));
    expect(
      find.descendant(of: summary, matching: find.text('4.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('(1 review)')),
      findsOneWidget,
    );
    expect(find.text('Products (1)'), findsOneWidget);
  });

  testWidgets('See all is plain text, not a pill button', (tester) async {
    FirebaseRefs.useForTests(
      firestore: await _farmerWithOneReview(),
      auth: MockFirebaseAuth(),
    );
    await _open(tester);

    final seeAll = find.byKey(const Key('storefrontSeeAllReviews'));
    expect(
      find.descendant(of: seeAll, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: seeAll, matching: find.text('See all')),
      findsOneWidget,
    );
  });
}
