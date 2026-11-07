// Liking a review: another buyer taps the thumbs-up on a review card and
// the like is saved as likes.{uid}; the reviewer and farmers see the count
// only.
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/widgets/review_like_button.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  late FakeFirebaseFirestore db;

  Future<void> signIn(String uid, String role) async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({'role': role});
    await db.collection('productReviews').doc('r1').set({
      'buyerId': 'reviewer',
      'rating': 4,
      'likes': {'someone': true},
    });
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: '$uid@gmail.com'),
      ),
    );
  }

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(FirebaseRefs.reset);

  Future<void> show(WidgetTester tester) async {
    final review = (await db.collection('productReviews').doc('r1').get())
        .data()!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReviewLikeButton(reviewId: 'r1', review: review),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('only likes set to true count', () {
    expect(
      reviewLikers({
        'likes': {'a': true, 'b': false, 'c': true},
      }),
      {'a', 'c'},
    );
    expect(reviewLikers({}), isEmpty);
  });

  testWidgets('another buyer likes a review, and takes it back', (
    tester,
  ) async {
    await signIn('buyerA', 'buyer');
    await show(tester);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reviewLike_r1')));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up_alt_rounded), findsOneWidget);
    var saved = (await db.collection('productReviews').doc('r1').get()).data();
    expect(reviewLikers(saved!), {'someone', 'buyerA'});

    await tester.tap(find.byKey(const Key('reviewLike_r1')));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    saved = (await db.collection('productReviews').doc('r1').get()).data();
    expect(reviewLikers(saved!), {'someone'});
  });

  testWidgets('the reviewer sees the count but cannot like their own', (
    tester,
  ) async {
    await signIn('reviewer', 'buyer');
    await show(tester);
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const Key('reviewLike_r1')), findsNothing);
  });

  testWidgets('a farmer sees the count only', (tester) async {
    await signIn('farmerA', 'farmer');
    await show(tester);
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const Key('reviewLike_r1')), findsNothing);
  });
}
