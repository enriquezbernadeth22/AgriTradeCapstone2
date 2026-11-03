// A farmer taps a buyer's photo in Conversation Info and sees the buyer's
// profile: what the marketplace shares (name, kind of buyer, area, member
// since) and only the orders that buyer placed with this farmer.
import 'dart:async';

import 'package:agritrade/screen/buyer_public_profile_screen.dart';
import 'package:agritrade/services/order_format.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

OrderInfo _order(String id, String status, String product, DateTime date) =>
    OrderInfo(id, {
      'status': status,
      'productName': product,
      'buyerId': 'buyer1',
      'sellerId': 'farmer1',
      'createdAt': Timestamp.fromDate(date),
    });

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(
    WidgetTester tester, {
    Map<String, dynamic>? profile,
    List<OrderInfo> orders = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: BuyerPublicProfileScreen(
          buyerId: 'buyer1',
          fallbackName: 'Junior',
          profileStream: Stream.value(profile),
          ordersStream: Stream.value(orders),
        ),
      ),
    );
    // The orders section opens in smoothly.
    await tester.pumpAndSettle();
  }

  testWidgets('shows what the marketplace shares about the buyer', (
    tester,
  ) async {
    await open(
      tester,
      profile: {
        'name': 'Junior Pesigan',
        'buyerType': 'Market Vendor',
        'barangay': 'Poblacion',
        'municipality': 'Malvar',
        'province': 'Batangas',
        'memberSince': Timestamp.fromDate(DateTime(2026, 9, 14)),
        // Never shown, even if it were there.
        'email': 'junior@example.com',
      },
    );
    expect(find.text('Buyer Profile'), findsOneWidget);
    expect(find.text('Junior Pesigan'), findsOneWidget);
    expect(find.text('Buyer · Market Vendor'), findsOneWidget);
    expect(find.text('Poblacion, Malvar, Batangas'), findsOneWidget);
    expect(find.text('Member since September 2026'), findsOneWidget);
    expect(find.textContaining('junior@example.com'), findsNothing);
  });

  testWidgets('an older profile with no kind of buyer still reads well', (
    tester,
  ) async {
    await open(tester, profile: {'name': 'Ana'});
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.textContaining('Member since'), findsNothing);
    expect(find.text('Ana has not ordered from you yet.'), findsOneWidget);
  });

  testWidgets('counts and lists this buyer\'s orders with the farmer, '
      'newest first', (tester) async {
    await open(
      tester,
      profile: {'name': 'Junior'},
      orders: [
        _order('o1', 'completed', 'Corn', DateTime(2026, 10, 2)),
        _order('o2', 'completed', 'Eggplant', DateTime(2026, 10, 20)),
        _order('o3', 'pending', 'Chicken', DateTime(2026, 11, 1)),
        _order('o4', 'cancelled', 'Rice', DateTime(2026, 9, 5)),
      ],
    );

    String countOf(String label) => tester
        .widget<Text>(
          find
              .descendant(
                of: find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Column),
                    )
                    .first,
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;
    expect(countOf('Completed'), '2');
    expect(countOf('Active'), '1');
    expect(countOf('Cancelled'), '1');

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Chicken'), lessThan(top('Eggplant')));
    expect(top('Eggplant'), lessThan(top('Corn')));
    expect(top('Corn'), lessThan(top('Rice')));
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('the five latest are listed, and View all opens every one', (
    tester,
  ) async {
    await open(
      tester,
      profile: {'name': 'Junior'},
      orders: [
        for (var i = 1; i <= 7; i++)
          _order('o$i', 'completed', 'Product $i', DateTime(2026, 10, i)),
      ],
    );
    expect(find.text('Product 7'), findsOneWidget);
    expect(find.text('Product 3'), findsOneWidget);
    expect(find.text('Product 2'), findsNothing);
    expect(find.text('7'), findsOneWidget); // Completed count still 7.

    await tester.tap(find.text('View all orders (7)'));
    await tester.pumpAndSettle();
    expect(find.text('Orders from Junior'), findsOneWidget);
    for (var i = 1; i <= 7; i++) {
      expect(find.text('Product $i'), findsOneWidget);
    }
    // Who sees them is said at the top, before the list.
    expect(
      tester.getTopLeft(find.textContaining('Only you see')).dy,
      lessThan(tester.getTopLeft(find.text('Product 7')).dy),
    );
  });

  testWidgets('who sees the orders is said above them, not at the bottom', (
    tester,
  ) async {
    await open(
      tester,
      profile: {'name': 'Junior'},
      orders: [_order('o1', 'completed', 'Corn', DateTime(2026, 10, 2))],
    );
    expect(find.text('View all orders (1)'), findsNothing);
    expect(
      tester.getTopLeft(find.textContaining('Only you see')).dy,
      lessThan(tester.getTopLeft(find.text('Corn')).dy),
    );
  });

  testWidgets('no loading bar: the orders show once they are here, and '
      'follow later changes', (tester) async {
    final orders = StreamController<List<OrderInfo>>();
    addTearDown(orders.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BuyerPublicProfileScreen(
          buyerId: 'buyer1',
          fallbackName: 'Junior',
          profileStream: Stream.value({'name': 'Junior'}),
          ordersStream: orders.stream,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Orders with you'), findsNothing);

    orders.add([_order('o1', 'pending', 'Corn', DateTime(2026, 11, 2))]);
    await tester.pumpAndSettle();
    expect(find.text('Orders with you'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);

    // The farmer completes it: the profile follows by itself.
    orders.add([_order('o1', 'completed', 'Corn', DateTime(2026, 11, 2))]);
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Completed'), findsNWidgets(2)); // The count and chip.
  });
}
