// Order Details: a small dark green outline icon before each of its
// section titles (the user's design, 2026-11-08), the titles unchanged.
import 'package:agritrade/screen/order_details_screen.dart';
import 'package:agritrade/services/firebase_refs.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:agritrade/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'tips_off': true});
  });
  tearDown(FirebaseRefs.reset);

  for (final status in ['pending', 'completed']) {
    testWidgets('$status: each section title has its icon, 18 dark green', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      FirebaseRefs.useForTests(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'buyer1'),
        ),
      );
      final placed = Timestamp.fromDate(DateTime(2026, 11, 6, 4, 35));
      final data = {
        'buyerId': 'buyer1',
        'sellerId': 'farmer1',
        'sellerName': 'Sander Calda',
        'buyerName': 'Maria',
        'productId': 'p1',
        'productName': 'Chicken',
        'quantity': 1,
        'unit': 'kg',
        'pricePerUnit': 190,
        'total': 190,
        'fulfillmentMethod': 'pickup',
        'status': status,
        'createdAt': placed,
        'updatedAt': placed,
        if (status == 'completed') 'completedAt': placed,
      };
      await db.collection('orders').doc('o1').set(data);
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: OrderDetailsScreen(
            orderId: 'o1',
            role: OrderRole.buyer,
            initial: OrderInfo('o1', data),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final sections = {
        'PRODUCT SUMMARY': Icons.inventory_2_outlined,
        'FARMER': Icons.person_outline_rounded,
        // Shown only while the number is shared (not on a completed order).
        if (status == 'pending') 'CONTACT NUMBER': Icons.phone_outlined,
        'FULFILLMENT SUMMARY': Icons.location_on_outlined,
        'PAYMENT SUMMARY': Icons.account_balance_wallet_outlined,
      };
      sections.forEach((title, icon) {
        final heading = find.text(title);
        expect(heading, findsOneWidget, reason: title);
        final row = find.ancestor(of: heading, matching: find.byType(Row));
        final mark = find.descendant(
          of: row.first,
          matching: find.byIcon(icon),
        );
        expect(mark, findsOneWidget, reason: title);
        final widget = tester.widget<Icon>(mark);
        expect(widget.size, 18);
        expect(widget.color, const Color(0xFF0B4225));
        // Before the title, 8 apart, on its line.
        final iconRect = tester.getRect(mark);
        final textRect = tester.getRect(heading);
        expect(textRect.left - iconRect.right, moreOrLessEquals(8));
        expect(
          iconRect.center.dy,
          moreOrLessEquals(textRect.center.dy, epsilon: 1.5),
        );
        // The title itself as it was: 11, bold, its own colour.
        final text = tester.widget<Text>(heading);
        expect(text.style!.fontSize, 11);
        expect(text.style!.fontWeight, FontWeight.w700);
        expect(text.style!.color, AppColors.brand);
      });
    });
  }

  testWidgets('completed: Review outlined with a dark green star, View '
      'Receipt filled with a gold receipt; 46 high, the same width', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    FirebaseRefs.useForTests(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'buyer1')),
    );
    final placed = Timestamp.fromDate(DateTime(2026, 11, 6, 4, 35));
    final data = {
      'buyerId': 'buyer1',
      'sellerId': 'farmer1',
      'sellerName': 'Sander Calda',
      'productId': 'p1',
      'productName': 'Chicken',
      'quantity': 1,
      'unit': 'kg',
      'pricePerUnit': 190,
      'total': 190,
      'status': 'completed',
      'createdAt': placed,
      'updatedAt': placed,
      'completedAt': placed,
    };
    await db.collection('orders').doc('o1').set(data);
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailsScreen(
          orderId: 'o1',
          role: OrderRole.buyer,
          initial: OrderInfo('o1', data),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final bar = find.byType(OrderActionBar);
    Finder button(String label) => find.ancestor(
      of: find.descendant(of: bar, matching: find.text(label)),
      matching: find.byType(TextButton),
    );
    final review = button('Review');
    final receipt = button('View Receipt');
    expect(tester.getSize(review).height, 46);
    expect(tester.getSize(receipt).height, 46);
    expect(
      tester.getSize(review).width,
      moreOrLessEquals(tester.getSize(receipt).width),
    );
    expect(
      tester.getTopLeft(receipt).dx - tester.getTopRight(review).dx,
      moreOrLessEquals(10),
    );

    Icon iconIn(Finder b) => tester.widget<Icon>(
      find.descendant(of: b, matching: find.byType(Icon)),
    );
    expect(iconIn(review).icon, Icons.star_outline_rounded);
    expect(iconIn(review).color, const Color(0xFF0B4225));
    expect(iconIn(review).size, 18);
    expect(iconIn(receipt).icon, Icons.receipt_long_outlined);
    expect(iconIn(receipt).color, const Color(0xFFF5BB24));

    final reviewStyle = tester.widget<TextButton>(review).style!;
    final receiptStyle = tester.widget<TextButton>(receipt).style!;
    expect(reviewStyle.backgroundColor!.resolve({}), AppColors.surface);
    expect(reviewStyle.side!.resolve({})!.color, const Color(0xFF0B4225));
    expect(receiptStyle.backgroundColor!.resolve({}), const Color(0xFF0B4225));
    expect(receiptStyle.foregroundColor!.resolve({}), Colors.white);
    expect(reviewStyle.textStyle!.resolve({})!.fontSize, 13);
  });
}
