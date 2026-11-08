// An order placed from a chat (the user's request, 2026-11-08): its card
// tells the farmer what the buyer chose, and the farmer answers it there.
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/widgets/order_placed_message_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(FirebaseRefs.reset);

  Future<void> show(
    WidgetTester tester, {
    required String viewer,
    String status = 'pending',
  }) async {
    final db = FakeFirebaseFirestore();
    await db.collection('orders').doc('o1').set({
      'buyerId': 'buyer1',
      'sellerId': 'farmer1',
      'buyerName': 'Ana',
      'productId': 'p1',
      'productName': 'Cassava',
      'quantity': 20,
      'unit': 'kg',
      'pricingType': 'wholesale',
      'pricePerUnit': 30,
      'subtotal': 600,
      'total': 600,
      'deliveryMethod': 'pickup',
      'status': status,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, 8, 9)),
    });
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: viewer)),
    );
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderPlacedMessageCard(
            data: const {
              'type': 'orderPlaced',
              'orderId': 'o1',
              'senderId': 'buyer1',
              'productName': 'Cassava',
            },
            isMe: viewer == 'buyer1',
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the farmer sees what was chosen, with Confirm and Reject', (
    tester,
  ) async {
    await show(tester, viewer: 'farmer1');
    expect(find.text('Order placed'), findsOneWidget);
    expect(find.text('Cassava'), findsOneWidget);
    expect(find.text('WHOLESALE'), findsOneWidget);
    expect(find.textContaining('20 kg'), findsWidgets);
    expect(find.textContaining('600'), findsWidgets);
    expect(find.byKey(const Key('orderPlacedConfirm')), findsOneWidget);
    expect(find.byKey(const Key('orderPlacedReject')), findsOneWidget);
    expect(find.byKey(const Key('orderPlacedDetails')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('orderPlacedConfirm'))).height,
      38,
    );
  });

  testWidgets('Confirm Order asks first, like Accept in Orders', (
    tester,
  ) async {
    await show(tester, viewer: 'farmer1');
    await tester.tap(find.byKey(const Key('orderPlacedConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Accept this order?'), findsOneWidget);
  });

  testWidgets('Reject asks first, like Reject in Orders', (tester) async {
    await show(tester, viewer: 'farmer1');
    await tester.tap(find.byKey(const Key('orderPlacedReject')));
    await tester.pumpAndSettle();
    expect(find.text('Reject this order?'), findsOneWidget);
  });

  testWidgets('the buyer waits for the farmer: no Confirm or Reject', (
    tester,
  ) async {
    await show(tester, viewer: 'buyer1');
    expect(find.text('You placed an order'), findsOneWidget);
    expect(find.text('Waiting for the farmer to confirm.'), findsOneWidget);
    expect(find.byKey(const Key('orderPlacedConfirm')), findsNothing);
    expect(find.byKey(const Key('orderPlacedReject')), findsNothing);
    expect(find.byKey(const Key('orderPlacedDetails')), findsOneWidget);
  });

  testWidgets('once confirmed, the card shows it and the buttons go', (
    tester,
  ) async {
    await show(tester, viewer: 'farmer1', status: 'confirmed');
    expect(find.text('CONFIRMED'), findsOneWidget);
    expect(find.byKey(const Key('orderPlacedConfirm')), findsNothing);
    expect(find.byKey(const Key('orderPlacedDetails')), findsOneWidget);
  });
}
