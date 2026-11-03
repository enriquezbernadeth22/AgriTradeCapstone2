// A buyer's feed puts the listings that deliver to their area first — the
// buyer's area is the marketplace's priority — without hiding the rest, and
// their cards say "Delivers to you".
import 'package:agritrade/services/buyer_area_watcher.dart';
import 'package:agritrade/services/delivery_coverage.dart';
import 'package:agritrade/widgets/explore_product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _listing(
  String name, {
  bool delivery = true,
  String type = 'municipality',
  List<String> areas = const [],
}) => {
  'name': name,
  'category': 'Vegetables',
  'farmerName': 'Juan',
  'retailPrice': 50,
  'quantity': 10,
  'unit': 'kg',
  'deliveryAvailable': delivery,
  'deliveryCoverage': {
    'type': type,
    'feeType': 'arranged',
    'originMunicipality': 'Laurel',
    'originProvince': 'Batangas',
    if (areas.isNotEmpty)
      'areas': [
        for (final a in areas) {'name': a, 'province': 'Batangas'},
      ],
  },
};

void main() {
  const talisay = BuyerArea(
    barangay: 'Poblacion',
    city: 'Talisay',
    province: 'Batangas',
  );

  final feed = [
    _listing('Within Laurel'), // Laurel only.
    _listing('Pick-up only', delivery: false),
    _listing('Nearby towns', type: 'nearby'), // Laurel + Talisay…
    _listing('Custom: Tanauan', type: 'custom', areas: ['Tanauan']),
    _listing('Custom: Talisay', type: 'custom', areas: ['Talisay']),
  ];
  List<String> names(List<Map<String, dynamic>> items) => [
    for (final p in items) p['name'] as String,
  ];

  test('listings that deliver to the buyer come first, the rest after, '
      'each group in its own order', () {
    expect(names(deliveringFirst(feed, talisay, (p) => p)), [
      'Nearby towns',
      'Custom: Talisay',
      'Within Laurel',
      'Pick-up only',
      'Custom: Tanauan',
    ]);
  });

  test('nothing is hidden, and nothing moves without a buyer location', () {
    expect(deliveringFirst(feed, talisay, (p) => p), hasLength(feed.length));
    expect(names(deliveringFirst(feed, const BuyerArea(), (p) => p)), [
      for (final p in feed) p['name'] as String,
    ]);
  });

  test('pick-up only never counts as delivering', () {
    const laurel = BuyerArea(city: 'Laurel', province: 'Batangas');
    expect(deliversTo(_listing('A', delivery: false), laurel), isFalse);
    expect(deliversTo(_listing('B'), laurel), isTrue);
  });

  test('the area is the buyer\'s saved one; other accounts have none', () {
    final area = BuyerAreaWatcher.areaOf({
      'role': 'buyer',
      'barangay': 'Poblacion',
      'municipality': 'Talisay',
      'province': 'Batangas',
    });
    expect(area.city, 'Talisay');
    expect(area.isKnown, isTrue);
    expect(
      BuyerAreaWatcher.areaOf({
        'role': 'farmer',
        'municipality': 'Laurel',
      }).isKnown,
      isFalse,
    );
  });

  testWidgets('a card says "Delivers to you" only when it does', (
    tester,
  ) async {
    BuyerAreaWatcher.instance.debugSet(talisay);
    addTearDown(() => BuyerAreaWatcher.instance.debugSet(const BuyerArea()));

    Future<void> card(Map<String, dynamic> data) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 320,
            child: ExploreProductCard(data: data),
          ),
        ),
      ),
    );

    await card(_listing('Nearby towns', type: 'nearby'));
    expect(find.text('Delivers to you'), findsOneWidget);

    await card(_listing('Within Laurel'));
    expect(find.text('Delivers to you'), findsNothing);

    // Without a location the card says nothing about delivery.
    BuyerAreaWatcher.instance.debugSet(const BuyerArea());
    await card(_listing('Nearby towns', type: 'nearby'));
    expect(find.text('Delivers to you'), findsNothing);
  });
}
