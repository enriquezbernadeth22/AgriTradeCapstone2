// Market Demand and Full Product Demand (the user's design, 2026-11-10):
// completed orders by month, each order once; four greens by demand level
// with the ranges in the legend; hover for a month's figures, click to
// hold it; the details panel; and the full ranking with search, category,
// sorting and pages.
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_full_product_demand.dart';
import 'package:agritrade/screen/admin_market_demand.dart';
import 'package:agritrade/services/monthly_demand_service.dart';
import 'package:agritrade/services/pdf_report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _next = 0;

({String id, Map<String, dynamic> data}) order(
  String product,
  int month, {
  int day = 5,
  String status = 'completed',
  String category = 'Vegetables',
  String? id,
  num quantity = 3,
  String unit = 'kg',
  num total = 150,
}) => (
  id: id ?? 'o${_next++}',
  data: {
    'status': status,
    'commodity': product,
    'productName': product,
    'category': category,
    'quantity': quantity,
    'unit': unit,
    'total': total,
    'completedAt': Timestamp.fromDate(DateTime(2026, month, day)),
  },
);

// Aug 4, Sep 2, Oct 8, Nov 2 completed orders (and one still pending).
List<({String id, Map<String, dynamic> data})> sample() => [
  for (var i = 0; i < 3; i++) order('Okra', 8),
  order('Corn', 8, category: 'Grains'),
  order('Okra', 9),
  order('Squash', 9),
  for (var i = 0; i < 5; i++) order('Squash', 10),
  for (var i = 0; i < 2; i++) order('Okra', 10),
  order('Corn', 10, category: 'Grains'),
  order('Corn', 11, category: 'Grains'),
  order('Ginger', 11, category: 'Spices'),
  order('Okra', 11, status: 'pending'),
];

final now = DateTime(2026, 11, 10);

void main() {
  group('the numbers', () {
    test('an order counts under the commodity frozen on it, never a '
        'look-alike name (Palay is not Ampalaya)', () {
      final orders = demandOrdersOf([order('Palay', 8, category: 'Grains')]);
      expect(orders.single.product, 'Palay');
      expect(orders.single.category, 'Grains');
    });

    test('each completed order once, by the month it was completed', () {
      final orders = demandOrdersOf([
        ...sample(),
        order('Okra', 8, id: 'twice'),
        order('Okra', 8, id: 'twice'),
      ]);
      final months = reportingMonths(orders, 2026, now: now);
      // Months before the records begin are left out.
      expect(months.first, DateTime(2026, 8));
      expect(months.last, DateTime(2026, 11));
      expect(monthlyOrders(orders, months).values, [5, 2, 8, 2]);
      expect(monthlyOrders(orders, months, product: 'okra').values, [
        4,
        1,
        2,
        0,
      ]);
    });

    test('the current month shows as zero until its first order', () {
      final orders = demandOrdersOf([order('Okra', 8)]);
      expect(reportingMonths(orders, 2026, now: now), [
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
        DateTime(2026, 11),
      ]);
    });

    test('the levels sit around the average: the busiest is High only '
        'when it is well above the rest; equal counts share a level', () {
      // Average 82.5: Very Low under 42, Low under 83, Moderate under 124.
      final scale = DemandScale.of([40, 111, 128, 51]);
      expect(scale.tierOf(40), DemandTier.veryLow);
      expect(scale.tierOf(51), DemandTier.low);
      expect(scale.tierOf(111), DemandTier.moderate);
      expect(scale.tierOf(128), DemandTier.high);
      expect(scale.tierOf(0), DemandTier.none);
      expect(scale.rangeOf(DemandTier.veryLow), '1–41');
      expect(scale.rangeOf(DemandTier.high), '124+');
      // Even months: nothing is High.
      final even = DemandScale.of([10, 10, 10]);
      expect(
        {
          for (final n in [10, 10, 10]) even.tierOf(n),
        },
        {DemandTier.moderate},
      );
    });

    test('Full Product Demand: ranks share ties; shares are of the '
        'month\'s distinct orders', () {
      final full = FullProductDemand.of(
        demandOrdersOf(sample()),
        DateTime(2026, 10),
      );
      expect(full.totalOrders, 8);
      expect(
        [for (final r in full.ranked) (r.rank, r.row.product)],
        [(1, 'Squash'), (2, 'Okra'), (3, 'Corn')],
      );
      expect(full.ranked.first.row.share, 62.5);
      expect(full.categories, ['Grains', 'Vegetables']);
      expect(full.filtered(category: 'Grains').single.row.product, 'Corn');
      final tie = FullProductDemand.of(
        demandOrdersOf(sample()),
        DateTime(2026, 11),
      );
      expect([for (final r in tie.ranked) r.rank], [1, 1]);
    });
  });

  group('the section', () {
    Future<FullDemandRequest?> pump(WidgetTester tester) async {
      FullDemandRequest? opened;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminThemeScope(
            palette: AdminPalette.light,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: AdminMarketDemandSection(
                  orders: demandOrdersOf(sample()),
                  now: now,
                  onViewFull: (r) => opened = r,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    Color barColor(WidgetTester tester, String month) {
      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byKey(Key('marketDemandBar_$month')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('opens on All Products with the months on record, '
        'coloured by level', (tester) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('marketDemandBar_2026-07')), findsNothing);
      expect(find.byKey(const Key('marketDemandBar_2026-08')), findsOneWidget);
      expect(find.byKey(const Key('marketDemandBar_2026-11')), findsOneWidget);
      // Aug 4, Sep 2, Oct 8, Nov 2 (average 4): 8 is High, 4 Moderate, 2 Low.
      expect(barColor(tester, '2026-10'), DemandTier.high.color);
      expect(barColor(tester, '2026-09'), DemandTier.low.color);
      expect(barColor(tester, '2026-08'), DemandTier.moderate.color);
      expect(find.textContaining('High (6+)'), findsOneWidget);
      // The overall panel: the period and its top products, no images.
      expect(find.text('Aug – Nov 2026'), findsOneWidget);
      expect(find.byKey(const Key('marketDemandTotal')), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      // View Full Product Demand is always there.
      expect(find.byKey(const Key('marketDemandViewFull')), findsOneWidget);
    });

    testWidgets('hover shows the month; it goes when the pointer leaves', (
      tester,
    ) async {
      await pump(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('marketDemandBar_2026-10'))),
      );
      await tester.pump();
      final tip = find.byKey(const Key('marketDemandTooltip'));
      expect(tip, findsOneWidget);
      String tipText() => tester
          .widgetList<Text>(
            find.descendant(of: tip, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .join(' | ');
      expect(
        tipText(),
        'October 2026 | All Products | 8 Completed Orders | High Demand | '
        'Most In-Demand Products: | 1. Squash — 5 orders | 2. Okra — 2 orders | '
        '3. Corn — 1 order',
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(tip, findsNothing);
    });

    testWidgets('click holds a month: the gold outline, the panel, and View '
        'Full Product Demand; again or × lets it go', (tester) async {
      FullDemandRequest? opened;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminThemeScope(
            palette: AdminPalette.light,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: AdminMarketDemandSection(
                  orders: demandOrdersOf(sample()),
                  now: now,
                  onViewFull: (r) => opened = r,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Without a held month it opens the latest month with orders.
      await tester.tap(find.byKey(const Key('marketDemandViewFull')));
      expect(opened?.month, DateTime(2026, 11));
      await tester.tap(find.byKey(const Key('marketDemandBar_2026-10')));
      await tester.pumpAndSettle();
      final bar = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byKey(const Key('marketDemandBar_2026-10')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final border = (bar.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, kDemandGold);
      // Its own level colour is kept.
      expect((bar.decoration! as BoxDecoration).color, DemandTier.high.color);
      expect(find.text('SELECTED MONTH'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('marketDemandViewFull')));
      expect(opened?.month, DateTime(2026, 10));
      expect(opened?.product, kAllProducts);

      await tester.tap(find.byKey(const Key('marketDemandClear')));
      await tester.pumpAndSettle();
      expect(find.text('OVERALL MARKET DEMAND'), findsOneWidget);
    });
  });

  testWidgets('Full Product Demand: the ranking, search, category, sorting '
      'and pages', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var back = false;
    final orders = demandOrdersOf([
      ...sample(),
      // Twelve more products in October, so there is a second page.
      for (var i = 0; i < 12; i++) order('Product ${i + 10}', 10),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Scaffold(
            body: AdminFullProductDemand(
              orders: orders,
              month: DateTime(2026, 10),
              onBack: () => back = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Full Product Demand'), findsOneWidget);
    expect(
      find.text('Detailed product demand for October 2026.'),
      findsOneWidget,
    );
    expect(find.text('Showing 1–10 of 15 products'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    // Squash in 5 of the month's 20 orders.
    expect(find.text('25.0%'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('fullDemandNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fullDemandNext')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11–15 of 15 products'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('fullDemandSearch')), 'okr');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1–1 of 1 product'), findsOneWidget);
    expect(find.byKey(const Key('fullDemandRow_Okra')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('fullDemandSearch')), '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('fullDemandSortOrders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fullDemandSortOrders')));
    await tester.pumpAndSettle();
    // Fewest first now: Squash is not on the first page.
    expect(find.byKey(const Key('fullDemandRow_Squash')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('fullDemandBack')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fullDemandBack')));
    expect(back, isTrue);
  });

  test('By Quantity Sold: by product and unit, never kilos with heads', () {
    final orders = demandOrdersOf([
      order('Okra', 10, quantity: 4, total: 200),
      order('Okra', 10, quantity: 6, total: 300),
      order('Squash', 10, quantity: 12, total: 360),
      order('Cattle', 10, quantity: 2, unit: 'head', total: 96000),
      order('Cattle', 10, quantity: 1, unit: 'head', total: 48000),
    ]);
    final rows = productQuantities(orders, [DateTime(2026, 10)]);
    expect(quantityUnits(rows), ['kg', 'head']);
    final kg = rankQuantities(rows, 'kg');
    expect(
      [for (final r in kg) (r.rank, r.row.product, r.row.quantity)],
      [(1, 'Squash', 12), (2, 'Okra', 10)],
    );
    // Okra: 10 kg in 2 orders, ₱500; Cattle only under head.
    expect(kg[1].row.orders, 2);
    expect(kg[1].row.sales, 500);
    final head = rankQuantities(rows, 'head').single.row;
    expect((head.product, head.quantity, head.sales), ('Cattle', 3, 144000));
  });

  testWidgets('Full Product Demand: the By Quantity Sold tab and its unit '
      'filter', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Scaffold(
            body: AdminFullProductDemand(
              orders: demandOrdersOf([
                ...sample(),
                order('Cattle', 10, quantity: 2, unit: 'head', total: 96000),
              ]),
              month: DateTime(2026, 10),
              onBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fullDemandUnit')), findsNothing);
    await tester.tap(find.byKey(const Key('fullDemandTab_quantity')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Per kg first: Squash 15 kg, Okra 6, Corn 3. No Cattle here.
    expect(find.byKey(const Key('fullDemandUnit')), findsOneWidget);
    expect(find.byKey(const Key('fullDemandQtyRow_Squash')), findsOneWidget);
    expect(find.byKey(const Key('fullDemandQtyRow_Cattle')), findsNothing);
    expect(find.text('Showing 1–3 of 3 products'), findsOneWidget);
    expect(find.text('₱750.00'), findsOneWidget);
  });

  test('the report builds from the table on screen', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await PdfReportService.buildFullProductDemandReport(
      FullDemandExport(
        month: DateTime(2026, 10),
        analysis: 'By Quantity Sold',
        filters: const [('Category', 'All Categories'), ('Unit', 'kg')],
        summary: const [
          ['Distinct completed orders', '8'],
        ],
        headers: const ['Rank', 'Product', 'Quantity Sold'],
        rows: const [
          ['1', 'Squash', '15'],
        ],
        weights: const [0.5, 2, 1],
        notes: const ['Per kg.'],
      ),
    );
    expect(bytes.length, greaterThan(1000));
  });
}
