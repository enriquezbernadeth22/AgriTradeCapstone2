// What a buyer buys most comes first (Explore, Recommended Products); a
// pick-up order shows where to pick it up once confirmed; and an area in
// Top Buyer Locations explains its numbers.
import 'package:agritrade/services/bought_first.dart';
import 'package:agritrade/services/market_demand_service.dart';
import 'package:agritrade/services/order_contact_service.dart';
import 'package:agritrade/services/personal_recommendations.dart';
import 'package:agritrade/widgets/market_demand_cards.dart'
    show LocationOrdersSheet;
import 'package:agritrade/widgets/pickup_place_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('what the buyer buys most comes first', () {
    final orders = [
      {'commodity': 'Eggplant', 'status': 'completed'},
      {'commodity': 'Eggplant', 'status': 'confirmed'},
      {'productName': 'Corn', 'status': 'pending'},
      {'commodity': 'Rice', 'status': 'cancelled'},
      {'commodity': 'Mango', 'status': 'rejected'},
    ];

    test('counts purchases, not cancelled or rejected orders', () {
      expect(boughtCounts(orders), {'eggplant': 2, 'corn': 1});
    });

    test('the feed: most-bought first, the rest keep their order', () {
      final feed = [
        {'name': 'Rice'},
        {'name': 'Corn'},
        {'name': 'Tomato'},
        {'commodity': 'Eggplant', 'name': 'Native Eggplant'},
      ];
      final sorted = boughtFirst(feed, boughtCounts(orders), (p) => p);
      expect(sorted.map((p) => p['name']), [
        'Native Eggplant',
        'Corn',
        'Rice',
        'Tomato',
      ]);
    });

    test('no purchases: the feed is unchanged', () {
      final feed = [
        {'name': 'B'},
        {'name': 'A'},
      ];
      expect(boughtFirst(feed, const {}, (p) => p), same(feed));
    });

    test('Recommended Products: the same product they buy first', () {
      Map<String, dynamic> product(String name, String category, int day) => {
        'name': name,
        'commodity': name,
        'category': category,
        'quantity': 10,
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, day)),
      };
      final result = PersonalRecommendations.recommend(
        products: {
          'tomato': product('Tomato', 'Vegetables', 5),
          'okra': product('Okra', 'Vegetables', 6),
          'rice': product('Rice', 'Grains', 1),
        },
        // Many vegetable orders, but rice is what they bought once.
        orders: [
          {
            'category': 'Vegetables',
            'commodity': 'Cabbage',
            'status': 'completed',
          },
          {
            'category': 'Vegetables',
            'commodity': 'Squash',
            'status': 'completed',
          },
          {'category': 'Grains', 'commodity': 'Rice', 'status': 'completed'},
        ],
      );
      expect(result.ids.first, 'rice');
    });
  });

  group('pick-up place', () {
    test('the farm address: the full one, else the area', () {
      expect(
        OrderContactService.pickupAddressOf({
          'location': 'Purok 3, Brgy. Bugaan East, Laurel, Batangas',
          'barangay': 'Bugaan East',
        }),
        'Purok 3, Brgy. Bugaan East, Laurel, Batangas',
      );
      expect(
        OrderContactService.pickupAddressOf({
          'barangay': 'Bugaan East',
          'municipality': 'Laurel',
          'province': 'Batangas',
        }),
        'Bugaan East, Laurel, Batangas',
      );
    });

    test('directions go to the pin, else to the address', () {
      final pinned = const PickupPlace(
        address: 'Laurel',
        latitude: 14.05,
        longitude: 120.9,
      );
      expect(
        pinned.directionsUri.queryParameters['destination'],
        '14.05,120.9',
      );
      final addressOnly = const PickupPlace(address: 'Bugaan East, Laurel');
      expect(
        addressOnly.directionsUri.queryParameters['destination'],
        'Bugaan East, Laurel',
      );
    });

    Future<void> pump(WidgetTester tester, PickupPlace? place) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PickupPlaceCard(
                orderId: 'o1',
                area: 'Bugaan East, Laurel',
                load: (_) async => place,
              ),
            ),
          ),
        );

    testWidgets('confirmed: the address and Get Directions', (tester) async {
      await pump(
        tester,
        const PickupPlace(address: 'Purok 3, Bugaan East, Laurel'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pick-up address'), findsOneWidget);
      expect(find.text('Purok 3, Bugaan East, Laurel'), findsOneWidget);
      expect(find.byKey(const Key('pickupDirections')), findsOneWidget);
    });

    testWidgets('nothing shared: the area, and to agree in Messages', (
      tester,
    ) async {
      await pump(tester, null);
      await tester.pumpAndSettle();
      expect(find.text('Bugaan East, Laurel'), findsOneWidget);
      expect(find.textContaining('in Messages'), findsOneWidget);
      expect(find.byKey(const Key('pickupDirections')), findsNothing);
    });
  });

  testWidgets('an area in Top Buyer Locations explains its numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationOrdersSheet(
              location: const BuyerLocation(
                area: 'Bugaan East',
                relativeDemand: 0.5,
                mostPurchased: 'Eggplant',
                demand: DemandLevel.moderate,
                orders: 4,
                sharePercent: 40,
              ),
              products: const [
                (commodity: 'Eggplant', orders: 3),
                (commodity: 'Corn', orders: 1),
              ],
              total: 4,
              month: DateTime(2026, 11),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('40%'), findsOneWidget); // of all buyer orders
    expect(find.text('of all buyer orders this month'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // orders from here
    expect(find.text('75%'), findsOneWidget); // eggplant: 3 of 4
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('3 orders'), findsOneWidget);
  });
}
