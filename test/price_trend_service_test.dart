import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:agritrade/services/price_trend_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp _on(int year, int month, [int day = 10]) =>
    Timestamp.fromDate(DateTime(year, month, day));

Map<String, dynamic> _order(
  String product,
  int year,
  int month,
  num quantity, {
  String unit = 'kg',
}) => {
  'status': 'completed',
  'productName': product,
  'unit': unit,
  'quantity': quantity,
  'pricingType': 'retail',
  'pricePerUnit': 100,
  'completedAt': _on(year, month),
};

void main() {
  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
      {'name': 'Chicken', 'category': 'Livestock', 'unit': 'kg liveweight'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  test('the years start at the first completed order and run to this '
      'year; this year alone before there is one', () {
    Map<String, dynamic> completed(int year, {String status = 'completed'}) => {
      'status': status,
      'completedAt': Timestamp.fromDate(DateTime(year, 3, 10)),
    };
    final october2026 = DateTime(2026, 10);
    // No completed order yet: the current year, and nothing to compare.
    expect(PriceTrendService.yearsOnRecord(const [], october2026), [2026]);
    final only2026 = PriceTrendService.yearsOnRecord([
      completed(2026),
      // An order that never completed does not start the records.
      completed(2025, status: 'cancelled'),
    ], october2026);
    expect(only2026, [2026]);

    final to2028 = PriceTrendService.yearsOnRecord([
      completed(2026),
    ], DateTime(2028, 1));
    expect(to2028, [2026, 2027, 2028]);
  });

  group('Price Trend', () {
    test('every price on record for the commodity counts, from all four '
        'sources, in the month of its own date', () {
      final prices = PriceTrendService.collect(
        commodity: 'Tomato',
        products: [
          // A listing named after the commodity, last edited in March 2026.
          {
            'name': 'Fresh Native Tomato',
            'unit': 'kg',
            'retailPrice': 60,
            'createdAt': _on(2026, 1),
            'updatedAt': _on(2026, 3),
          },
          // Another commodity: not counted.
          {'name': 'Eggplant', 'retailPrice': 40, 'createdAt': _on(2026, 3)},
        ],
        completedOrders: [
          {
            'productName': 'Tomato',
            'unit': 'kg',
            'pricingType': 'retail',
            'pricePerUnit': 80,
            'completedAt': _on(2026, 3),
          },
          // Wholesale is a bulk discount, not the market price.
          {
            'productName': 'Tomato',
            'unit': 'kg',
            'pricingType': 'wholesale',
            'pricePerUnit': 30,
            'completedAt': _on(2026, 3),
          },
          // Another unit never mixes in.
          {
            'productName': 'Tomato',
            'unit': 'crate',
            'pricingType': 'retail',
            'pricePerUnit': 900,
            'completedAt': _on(2026, 3),
          },
        ],
        referenceHistory: [
          {'price': 50, 'unit': 'kg', 'effectiveDate': _on(2025, 3)},
        ],
        historical: const [
          HistoricalDemandRecord(
            year: 2025,
            month: 3,
            commodity: 'Tomato',
            category: 'Vegetables',
            quantity: 100,
            unit: 'kg',
            averagePrice: 70,
          ),
        ],
      );

      expect(prices.unit, 'kg');
      expect(prices.points.map((p) => p.source).toSet(), {
        PriceTrendSource.farmerListing,
        PriceTrendSource.farmerSale,
        PriceTrendSource.adminReference,
        PriceTrendSource.adminImport,
      });
      expect(prices.points, hasLength(4));

      final y2025 = PriceTrendService.monthlyAverages(prices.points, 2025);
      final y2026 = PriceTrendService.monthlyAverages(prices.points, 2026);
      // March: (50 + 70) / 2 in 2025, (60 + 80) / 2 in 2026.
      expect(y2025[2], 60);
      expect(y2026[2], 70);
      // The listing counts when it was last edited, not when first posted.
      expect(y2026[0], isNull);
    });

    test('the unit is the one the records use, even when the commodity list '
        'words it differently', () {
      // Chicken is "kg liveweight" on the list; its listings say "kg".
      final prices = PriceTrendService.collect(
        commodity: 'Chicken',
        products: [
          {
            'name': 'Chicken',
            'unit': 'kg',
            'retailPrice': 190,
            'createdAt': _on(2026, 10),
          },
        ],
        completedOrders: [_order('Chicken', 2026, 10, 10)],
        referenceHistory: const [],
        historical: const [],
      );
      expect(prices.unit, 'kg');
      expect(prices.points, hasLength(2));
    });

    test('a month with no price is a gap, never a zero', () {
      final points = [
        PriceTrendPoint(DateTime(2026, 1, 5), 100, PriceTrendSource.farmerSale),
        PriceTrendPoint(DateTime(2026, 4, 5), 120, PriceTrendSource.farmerSale),
      ];
      final monthly = PriceTrendService.monthlyAverages(points, 2026);
      expect(monthly[0], 100);
      expect(monthly[1], isNull);
      expect(monthly[3], 120);
      expect(PriceTrendService.yearAverage(monthly), 110);
      expect(
        PriceTrendService.yearAverage(
          PriceTrendService.monthlyAverages(points, 2025),
        ),
        isNull,
      );
    });
  });

  group('Market Trend (seasonal best sellers)', () {
    HistoricalDemandRecord record(
      String commodity,
      int year,
      int month,
      double quantity,
      String unit,
    ) => HistoricalDemandRecord(
      year: year,
      month: month,
      commodity: commodity,
      category: '',
      quantity: quantity,
      unit: unit,
    );

    final now = DateTime(2026, 10, 25);
    final historical = [
      // Corn: a little in January, a lot every November.
      record('Corn', 2024, 1, 100, 'kg'),
      record('Corn', 2024, 11, 300, 'kg'),
      record('Corn', 2025, 11, 300, 'kg'),
      // Coconut: far more pieces than Corn's kilos, peaking in June.
      record('Coconut', 2024, 6, 2000, 'piece'),
      record('Coconut', 2024, 11, 1000, 'piece'),
    ];

    test('each month lists the products that usually sell above their own '
        'usual month, most above first', () {
      final result = SeasonalSalesService.bestSellers(
        commodities: ['Corn', 'Coconut', 'Tomato'],
        completedOrders: const [],
        historical: historical,
        now: now,
      );
      expect(result.years, [2024, 2025]);
      // November: Corn is ten times its usual month; Coconut four times —
      // though Coconut sold far more, in pieces.
      final november = result.months[10];
      expect(november.map((s) => s.product), ['Corn', 'Coconut']);
      expect(november.first.ratio, closeTo(300 / (350 / 12), 0.01));
      // June: Coconut's peak.
      expect(result.months[5].single.product, 'Coconut');
      // March: nothing sells above its usual.
      expect(result.months[2], isEmpty);
    });

    test('completed orders count in the months since the marketplace '
        'opened, in the unit the orders use', () {
      final result = SeasonalSalesService.bestSellers(
        // Chicken is "kg liveweight" on the list; its orders say "kg".
        commodities: ['Chicken'],
        completedOrders: [
          _order('Chicken', 2026, 9, 5),
          _order('Chicken', 2026, 10, 10),
        ],
        historical: const [],
        now: now,
      );
      expect(result.years, [2026]);
      expect(result.months[9].single.product, 'Chicken');
      // Before the first order, and after this month, nothing is known.
      expect(result.months[0], isEmpty);
      expect(result.months[11], isEmpty);
    });

    test('nothing on record: every month is empty', () {
      final result = SeasonalSalesService.bestSellers(
        commodities: ['Corn'],
        completedOrders: const [],
        historical: const [],
        now: now,
      );
      expect(result.months.every((m) => m.isEmpty), isTrue);
      expect(result.years, isEmpty);
    });
  });
}
