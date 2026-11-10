// Market Change Analysis (the user's design, 2026-11-10): the chosen period
// against the one just before, position by position; Demand Trend from
// distinct completed orders, Local Supply from new listings, Market Price
// from the Current Market Average, and Net Change; a summary that says what
// changed, never why; the dashboard preview and the full page.
import 'package:agritrade/data/commodity_master_list.dart'
    show unitForCommodity;
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_market_change.dart';
import 'package:agritrade/services/market_change_service.dart';
import 'package:agritrade/services/market_price_helpers.dart';
import 'package:agritrade/services/monthly_demand_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _next = 0;

({String id, Map<String, dynamic> data}) order(
  String product,
  DateTime completed, {
  String status = 'completed',
  String? id,
}) => (
  id: id ?? 'o${_next++}',
  data: {
    'status': status,
    'commodity': product,
    'productName': product,
    'category': 'Vegetables',
    'quantity': 2,
    'unit': 'kg',
    'total': 160,
    'completedAt': Timestamp.fromDate(completed),
  },
);

Map<String, dynamic> listing(
  DateTime created, {
  String product = 'Ampalaya',
  num price = 80,
  num quantity = 10,
  bool archived = false,
  DateTime? archivedAt,
}) => {
  'commodity': product,
  'name': product,
  'category': 'Vegetables',
  'unit': unitForCommodity(product),
  'quantity': quantity,
  'retailPrice': price,
  'createdAt': Timestamp.fromDate(created),
  'isArchived': archived,
  if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt),
};

final now = DateTime(2026, 11, 10, 15);

// Current period (Oct 12 – Nov 10): 6 Ampalaya orders; previous (Sep 12 –
// Oct 11): 4. Plus one listed twice, a pending one, another product and
// one older than both periods.
List<DemandOrder> sampleOrders() => demandOrdersOf([
  order('Ampalaya', DateTime(2026, 10, 12, 9), id: 'first-day'),
  order('Ampalaya', DateTime(2026, 10, 12, 9), id: 'first-day'),
  order('Ampalaya', DateTime(2026, 10, 20)),
  order('Ampalaya', DateTime(2026, 11, 1)),
  order('Ampalaya', DateTime(2026, 11, 1)),
  order('Ampalaya', DateTime(2026, 11, 1)),
  order('Ampalaya', DateTime(2026, 11, 10, 8)),
  order('Ampalaya', DateTime(2026, 9, 12, 7)),
  order('Ampalaya', DateTime(2026, 9, 30)),
  order('Ampalaya', DateTime(2026, 10, 1)),
  order('Ampalaya', DateTime(2026, 10, 11, 23)),
  order('Ampalaya', DateTime(2026, 11, 5), status: 'pending'),
  order('Okra', DateTime(2026, 11, 5)),
  order('Ampalaya', DateTime(2026, 9, 1)),
]);

List<Map<String, dynamic>> sampleListings() => [
  listing(DateTime(2026, 10, 20), price: 100),
  listing(DateTime(2026, 11, 2), price: 100),
  listing(DateTime(2026, 9, 20), price: 80, quantity: 0),
  listing(DateTime(2026, 8, 1), price: 80),
  // Archived with no date: left out of the earlier market average.
  listing(DateTime(2026, 8, 1), price: 500, archived: true),
  listing(DateTime(2026, 11, 3), product: 'Okra', price: 40),
];

MarketChange analyze({ChangeRange range = ChangeRange.days30}) =>
    MarketChangeService.analyze(
      product: 'Ampalaya',
      range: range,
      orders: sampleOrders(),
      products: sampleListings(),
      now: now,
    );

Widget host(Widget child) => MaterialApp(
  home: AdminThemeScope(
    palette: AdminPalette.light,
    child: Scaffold(body: child),
  ),
);

void main() {
  group('the periods', () {
    test('the last 30 days and the 30 days before, as whole days', () {
      final w = ChangeWindow.of(ChangeRange.days30, now);
      expect(w.currentStart, DateTime(2026, 10, 12));
      expect(w.currentEnd, DateTime(2026, 11, 11));
      expect(w.previousStart, DateTime(2026, 9, 12));
      expect(w.currentLabel, 'Oct 12 – Nov 10, 2026');
      expect(w.previousLabel, 'Sep 12 – Oct 11, 2026');
    });

    test('both lines have the same days, Day 1 to Day 30', () {
      final d = analyze();
      expect(d.trend, hasLength(30));
      expect(d.trend.first.label, 'Day 1');
      expect(d.trend.first.currentFrom, DateTime(2026, 10, 12));
      expect(d.trend.first.previousFrom, DateTime(2026, 9, 12));
      expect(d.trend.last.currentFrom, DateTime(2026, 11, 10));
      expect(d.trend.last.previousFrom, DateTime(2026, 10, 11));
      // Day 1: the order listed twice counts once; Day 1 before: Sep 12.
      expect(d.trend.first.current, 1);
      expect(d.trend.first.previous, 1);
      expect(d.trend.last.current, 1);
      expect(d.trend.last.previous, 1);
    });

    test('90 days go week by week, the same weeks in both periods', () {
      final d = analyze(range: ChangeRange.days90);
      expect(d.trend, hasLength(13));
      expect(d.trend.first.label, 'Week 1');
      final last = d.trend.last;
      expect(last.currentTo.difference(last.currentFrom).inDays, 6);
      expect(last.previousTo.difference(last.previousFrom).inDays, 6);
    });
  });

  group('the measures', () {
    test('demand: distinct completed orders containing the product', () {
      final d = analyze();
      expect(d.currentOrders, 6);
      expect(d.previousOrders, 4);
      expect(d.demand.status, ChangeStatus.increased);
      expect(d.demand.percentLabel, '+50%');
      expect(d.netChange, 2);
    });

    test('local supply: new listings posted in each period', () {
      final d = analyze();
      expect(d.currentListings, 2);
      expect(d.previousListings, 1);
      expect(d.supply.status, ChangeStatus.increased);
      expect(d.supply.percentLabel, '+100%');
      // Today's stock, never compared: three listings in stock (the
      // archived one and the sold-out one are not).
      expect(d.activeListings, 3);
      expect(d.availableStock, 30);
    });

    test('market price: the Current Market Average, today and then', () {
      final d = analyze();
      // Today: exactly the mobile app's figure.
      expect(
        d.price.current,
        liveAverageOfListings(sampleListings(), 'Ampalaya'),
      );
      expect(d.price.current, closeTo(93.33, 0.01));
      // At the end of the previous period: the Aug 1 and Sep 20 listings
      // (sold out since, still on sale then); not the ones posted later
      // or the one archived on an unknown date.
      expect(d.price.previous, 80);
      expect(d.price.status, ChangeStatus.increased);
      expect(d.price.percentLabel, '+17%');
    });

    test('nothing to compare is Insufficient Data, never a guess', () {
      final d = MarketChangeService.analyze(
        product: 'Ampalaya',
        range: ChangeRange.days7,
        orders: const [],
        products: const [],
        now: now,
      );
      expect(d.demand.status, ChangeStatus.insufficient);
      expect(d.supply.status, ChangeStatus.insufficient);
      expect(d.price.status, ChangeStatus.insufficient);
      expect(d.isEmpty, isTrue);
    });

    test('steady within the threshold; new when there was none before', () {
      expect(
        MetricChange.compare(105, 100, threshold: 0.10).status,
        ChangeStatus.steady,
      );
      expect(
        MetricChange.compare(80, 100, threshold: 0.10).percentLabel,
        '−20%',
      );
      final fresh = MetricChange.compare(3, 0, threshold: 0.10);
      expect(fresh.status, ChangeStatus.increased);
      expect(fresh.percent, isNull);
    });

    test('the default product is the most ordered of the last 30 days', () {
      expect(
        MarketChangeService.productOrDefault(
          const ['Okra', 'Ampalaya'],
          null,
          sampleOrders(),
          now,
        ),
        'Ampalaya',
      );
      expect(
        MarketChangeService.productOrDefault(
          const ['Okra', 'Ampalaya'],
          'Okra',
          sampleOrders(),
          now,
        ),
        'Okra',
      );
    });

    test('the summary says what changed, never why', () {
      final lines = analyze().summary;
      final text = lines.join(' ').toLowerCase();
      expect(text, contains('6 completed orders'));
      expect(text, contains('2 new listings'));
      for (final cause in [
        'because',
        'due to',
        'weather',
        'season',
        'shortage',
        'prefer',
      ]) {
        expect(text, isNot(contains(cause)), reason: cause);
      }
      expect(lines.last, contains('do not by themselves show what caused'));
    });
  });

  group('on screen', () {
    testWidgets('the dashboard preview: three changes and View Detailed '
        'Analysis', (tester) async {
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = false;
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.all(24),
            child: AdminMarketChangePreview(
              products: const ['Ampalaya', 'Okra'],
              orders: sampleOrders(),
              listings: sampleListings(),
              choice: (product: null, range: ChangeRange.days30),
              onProductChanged: (_) {},
              onViewDetails: () => opened = true,
              now: now,
            ),
          ),
        ),
      );
      expect(find.text('Market Change Analysis'), findsOneWidget);
      expect(
        find.textContaining('Last 30 Days · Oct 12 – Nov 10, 2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('marketChange-demand')), findsOneWidget);
      expect(find.byKey(const Key('marketChange-supply')), findsOneWidget);
      expect(find.byKey(const Key('marketChange-price')), findsOneWidget);
      // No chart on the dashboard.
      expect(find.text('Completed Orders Trend'), findsNothing);
      final card = tester.getSize(find.byType(AdminMarketChangePreview));
      expect(card.height, lessThanOrEqualTo(300));
      await tester.tap(find.byKey(const Key('marketChangeViewDetails')));
      expect(opened, isTrue);
    });

    testWidgets('the full page: chart, four insights, summary and Back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var back = false;
      ChangeRange? range;
      await tester.pumpWidget(
        host(
          AdminMarketChangeAnalysis(
            products: const ['Ampalaya', 'Okra'],
            orders: sampleOrders(),
            listings: sampleListings(),
            choice: (product: 'Ampalaya', range: ChangeRange.days30),
            onProductChanged: (_) {},
            onRangeChanged: (r) => range = r,
            onBack: () => back = true,
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Completed Orders Trend'), findsOneWidget);
      expect(
        find.text('Track recent marketplace changes for the selected product.'),
        findsOneWidget,
      );
      for (final kind in ['demand', 'supply', 'price', 'net']) {
        expect(find.byKey(Key('marketChange-$kind')), findsOneWidget);
      }
      expect(find.text('+2 orders (+50%)'), findsOneWidget);
      expect(find.byKey(const Key('marketChangeSummary')), findsOneWidget);
      // The chart beside the insights.
      final chart = tester.getRect(find.text('Completed Orders Trend'));
      final net = tester.getRect(find.byKey(const Key('marketChange-net')));
      expect(net.left, greaterThan(chart.right));

      await tester.tap(find.byKey(const Key('marketChangeRange')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 7 Days').last);
      await tester.pumpAndSettle();
      expect(range, ChangeRange.days7);

      await tester.tap(find.byKey(const Key('marketChangeBack')));
      expect(back, isTrue);
    });
  });
}
