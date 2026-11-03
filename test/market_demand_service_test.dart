import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/market_demand_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(
  String product,
  DateTime date, {
  String area = 'Tanauan City',
  String? pricing = 'retail',
  String status = 'completed',
  num quantity = 1,
  String unit = 'kg',
}) => {
  'productName': product,
  'status': status,
  'unit': unit,
  'quantity': quantity,
  'buyerArea': area,
  'pricingType': ?pricing,
  'completedAt': Timestamp.fromDate(date),
};

void main() {
  final october = DateTime(2026, 10);
  final now = DateTime(2026, 10, 20);
  DateTime oct(int day) => DateTime(2026, 10, day);
  DateTime sep(int day) => DateTime(2026, 9, day);

  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      // Added by the Admin — not in the app's default set.
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  test('demand leaders rank by completed orders in the selected month', () {
    final sales = [
      for (var i = 0; i < 6; i++) _sale('Fresh Tomato', oct(i + 1)),
      for (var i = 0; i < 3; i++)
        _sale('Eggplant', oct(i + 1), area: 'Laurel', pricing: 'wholesale'),
      _sale('Banana', oct(2), area: 'Talisay', quantity: 500),
      // Not counted: another month, and an order that never completed.
      _sale('Squash', sep(5)),
      _sale('Okra', oct(3), status: 'pending'),
    ];

    final ranked = MarketDemandService.demandLeaders(
      sales: sales,
      month: october,
      now: now,
    );

    expect(ranked.map((b) => b.commodity), ['Tomato', 'Eggplant', 'Banana']);
    // The Admin-added commodity is eligible, with its category.
    expect(ranked[0].category, 'Vegetables');
    expect(ranked[0].mostlyWholesale, isFalse);
    expect(ranked[0].topBuyerArea, 'Tanauan City');
    expect(ranked[0].unit, 'kg');
    expect(ranked[1].mostlyWholesale, isTrue);
    expect(ranked[1].topBuyerArea, 'Laurel');
    // Relative to the top commodity's 6 orders: 6 → High, 3 → Moderate,
    // 1 → Low.
    expect(ranked.map((b) => b.demand), [
      DemandLevel.high,
      DemandLevel.moderate,
      DemandLevel.low,
    ]);
  });

  test('best sellers rank by quantity sold, not by orders', () {
    final sales = [
      for (var i = 0; i < 6; i++) _sale('Tomato', oct(i + 1), quantity: 2),
      _sale('Eggplant', oct(1), quantity: 40),
      _sale('Squash', sep(5), quantity: 900),
      _sale('Okra', oct(3), status: 'pending', quantity: 900),
    ];

    final ranked = MarketDemandService.bestSellers(
      sales: sales,
      month: october,
      now: now,
    );

    expect(ranked.map((b) => b.commodity), ['Eggplant', 'Tomato']);
    expect(ranked.map((b) => b.quantity), [40, 12]);
    // Demand stays counted in orders: Tomato's 6 orders against Eggplant's 1.
    expect(ranked.map((b) => b.demand), [DemandLevel.low, DemandLevel.high]);
  });

  test('best sellers never add unlike units together', () {
    final ranked = MarketDemandService.bestSellers(
      sales: [
        _sale('Tomato', oct(1), quantity: 2, unit: 'crate'),
        _sale('Tomato', oct(2), quantity: 5, unit: 'kg'),
        _sale('Tomato', oct(3), quantity: 10, unit: 'kg'),
      ],
      month: october,
      now: now,
    );

    expect(
      [for (final b in ranked) (b.quantity, b.unit)],
      [(15, 'kg'), (2, 'crate')],
    );
  });

  test('the months on record run from the first sale to the current month', () {
    final months = MarketDemandService.monthsOnRecord(
      sales: [
        _sale('Tomato', sep(5)),
        _sale('Okra', DateTime(2026, 6, 1), status: 'pending'),
      ],
      month: october,
      now: now,
    );
    expect(months, [october, DateTime(2026, 9)]);

    expect(
      MarketDemandService.monthsOnRecord(
        sales: const [],
        month: october,
        now: now,
      ),
      [october],
    );
  });

  test('never more than five best sellers', () {
    final sales = [for (var i = 0; i < 14; i++) _sale('Product $i', oct(1))];
    expect(
      MarketDemandService.bestSellers(sales: sales, month: october, now: now),
      hasLength(5),
    );
  });

  test('the Buyer\'s demand badge still covers the top ten', () {
    final sales = [for (var i = 0; i < 14; i++) _sale('Product $i', oct(1))];
    expect(
      MarketDemandService.demandLeaders(sales: sales, month: october, now: now),
      hasLength(10),
    );
  });

  test('trend compares with the same stretch of the previous month', () {
    final sales = [
      // Tomato: 4 now vs 2 by Sep 20 → Rising. (The late-September orders
      // fall outside the comparable stretch of an unfinished month.)
      for (var i = 0; i < 4; i++) _sale('Tomato', oct(i + 1)),
      _sale('Tomato', sep(3)),
      _sale('Tomato', sep(10)),
      for (var i = 0; i < 5; i++) _sale('Tomato', sep(25)),
      // Eggplant: 2 vs 2 → Stable.
      _sale('Eggplant', oct(4)),
      _sale('Eggplant', oct(9)),
      _sale('Eggplant', sep(4)),
      _sale('Eggplant', sep(9)),
      // Banana: 1 vs 3 → Declining.
      _sale('Banana', oct(5)),
      for (var i = 0; i < 3; i++) _sale('Banana', sep(i + 1)),
    ];

    final trends = {
      for (final b in MarketDemandService.bestSellers(
        sales: sales,
        month: october,
        now: now,
      ))
        b.commodity: b.trend,
    };

    expect(trends, {
      'Tomato': DemandTrend.rising,
      'Eggplant': DemandTrend.stable,
      'Banana': DemandTrend.declining,
    });
  });

  test('order type is left unknown for sales recorded without it', () {
    final ranked = MarketDemandService.bestSellers(
      sales: [_sale('Tomato', oct(1), pricing: null, area: '')],
      month: october,
      now: now,
    );
    expect(ranked.single.mostlyWholesale, isNull);
    expect(ranked.single.topBuyerArea, isEmpty);
  });

  test('top buyer locations: relative demand and most purchased', () {
    final sales = [
      for (var i = 0; i < 4; i++) _sale('Tomato', oct(i + 1)),
      _sale('Eggplant', oct(6)),
      _sale('Eggplant', oct(7), area: 'Laurel'),
      _sale('Eggplant', oct(8), area: 'Laurel'),
      _sale('Tomato', oct(9), area: 'Laurel'),
      // No buyer area on record: left out, not guessed.
      _sale('Banana', oct(2), area: ''),
      _sale('Banana', sep(2), area: 'Talisay'),
    ];

    final locations = MarketDemandService.topBuyerLocations(
      sales: sales,
      month: october,
    );

    expect(locations.map((l) => l.area), ['Tanauan City', 'Laurel']);
    expect(locations[0].mostPurchased, 'Tomato');
    expect(locations[0].relativeDemand, 1);
    expect(locations[0].demand, DemandLevel.high);
    expect(locations[1].mostPurchased, 'Eggplant');
    expect(locations[1].relativeDemand, closeTo(0.6, 0.001));
    expect(locations[1].demand, DemandLevel.moderate);
  });

  test('what buyers in one area ordered: most orders first, that area and '
      'month only', () {
    final sales = [
      for (var i = 0; i < 3; i++) _sale('Tomato', oct(i + 1), area: 'Laurel'),
      _sale('Eggplant', oct(4), area: 'Laurel'),
      _sale('Corn', oct(5), area: 'Laurel'),
      // Another area, another month, and an order not completed.
      for (var i = 0; i < 5; i++) _sale('Banana', oct(6), area: 'Talisay'),
      _sale('Eggplant', DateTime(2026, 9, 9), area: 'Laurel'),
      _sale('Corn', oct(7), area: 'Laurel', status: 'cancelled'),
    ];
    final products = MarketDemandService.productsBoughtIn(
      sales: sales,
      month: october,
      area: 'Laurel',
    );
    expect(products.map((p) => (p.commodity, p.orders)), [
      ('Tomato', 3),
      ('Corn', 1),
      ('Eggplant', 1),
    ]);
  });
}
