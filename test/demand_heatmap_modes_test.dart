// The Demand Heatmap's final revision (2026-11-09): Buyer Demand counts
// unique buyers per location, Product Demand counts unique buyers or
// completed orders per category and location, completed orders only and
// never buyer searches, and the report shows the same numbers.
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_demand_widgets.dart';
import 'package:agritrade/services/demand_heatmap_service.dart';
import 'package:agritrade/services/pdf_report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

var _next = 0;

({String id, Map<String, dynamic> data}) order(
  String buyer,
  String category, {
  String barangay = 'Poblacion',
  String town = 'Malvar',
  String status = 'completed',
  int day = 5,
  int month = 11,
  String? id,
}) => (
  id: id ?? 'o${_next++}',
  data: {
    'status': status,
    'buyerId': buyer,
    'category': category,
    'productName': category == 'Grains' ? 'Corn' : 'Okra',
    'buyerBarangay': barangay,
    'buyerMunicipality': town,
    'total': 100,
    'completedAt': Timestamp.fromDate(DateTime(2026, month, day)),
  },
);

final users = <String, Map<String, dynamic>>{
  for (final id in ['a', 'b', 'c', 'd', 'nowhere']) id: {'role': 'buyer'},
};

List<DemandRecord> records(
  List<({String id, Map<String, dynamic> data})> orders,
) => demandRecords(
  orders: orders,
  usersByUid: users,
  start: DateTime(2026, 11, 1),
  end: DateTime(2026, 12, 1),
);

void main() {
  group('Buyer Demand', () {
    test('counts unique buyers per location (the panel\'s example)', () {
      final r = records([
        for (var i = 0; i < 5; i++) order('a', 'Vegetables'),
        for (var i = 0; i < 3; i++) order('b', 'Grains'),
        for (var i = 0; i < 2; i++)
          order('c', 'Grains', barangay: 'San Gabriel', town: 'Laurel'),
      ]);
      final areas = areaDemand(r);
      expect(
        [for (final a in areas) (a.area, a.count)],
        [('Poblacion, Malvar', 2), ('San Gabriel, Laurel', 1)],
      );
      expect(demandTotal(r), 3);
    });

    test('only completed orders in the month, by registered buyers, once '
        'each', () {
      final r = records([
        order('a', 'Grains', id: 'same'),
        order('a', 'Grains', id: 'same'), // the same order listed twice
        order('b', 'Grains', status: 'pending'),
        order('c', 'Grains', month: 10), // the month before
        order('stranger', 'Grains'), // no such account
      ]);
      expect(r.length, 1);
      expect(demandTotal(r, counting: DemandCounting.completedOrders), 1);
    });

    test('a buyer in two places counts in each, and once in the total', () {
      final r = records([
        order('a', 'Grains'),
        order('a', 'Grains', barangay: 'San Gabriel', town: 'Laurel'),
      ]);
      expect(areaDemand(r).map((a) => a.count), [1, 1]);
      expect(demandTotal(r), 1);
    });

    test('a buyer with no known location counts in the total only', () {
      final r = records([
        order('a', 'Grains'),
        order('nowhere', 'Grains', barangay: '', town: ''),
      ]);
      expect(demandTotal(r), 2);
      expect(areaDemand(r).single.count, 1);
    });
  });

  group('Product Demand', () {
    final r = records([
      order('a', 'Grains'),
      order('a', 'Grains'),
      order('a', 'Vegetables'),
      order('b', 'Grains'),
      order('c', 'Livestock', barangay: 'San Gabriel', town: 'Laurel'),
    ]);

    test('unique buyers per category: a buyer once in each category', () {
      final summary = categoryDemand(r, counting: DemandCounting.uniqueBuyers);
      final grains = summary.rows.firstWhere((c) => c.category == 'Grains');
      expect(grains.count, 2);
      expect(summary.denominator, 3);
      expect(grains.percent, closeTo(66.7, 0.1));
      // Shares of buyers can add up to more than 100%.
      final sum = summary.rows.fold<double>(0, (s, c) => s + (c.percent ?? 0));
      expect(sum, greaterThan(100));
      // Categories with no demand are still listed, after the rest.
      expect(summary.rows.last.count, 0);
    });

    test('completed orders per category: each order once', () {
      final summary = categoryDemand(
        r,
        counting: DemandCounting.completedOrders,
      );
      expect(summary.rows.firstWhere((c) => c.category == 'Grains').count, 3);
      expect(summary.denominator, 5);
    });

    test('the areas follow the category and the counting method', () {
      expect(
        areaDemand(
          r,
          counting: DemandCounting.completedOrders,
          category: 'Grains',
        ).single.count,
        3,
      );
      expect(
        areaDemand(
          r,
          counting: DemandCounting.uniqueBuyers,
          category: 'Grains',
        ).single.count,
        2,
      );
      // All categories: buyer "a" (Grains and Vegetables) still counts once.
      expect(
        areaDemand(r).firstWhere((a) => a.area == 'Poblacion, Malvar').count,
        2,
      );
    });
  });

  test('the levels and the legend share one scale', () {
    expect(demandThresholds(2), (lowMax: 1, mediumMax: 3));
    expect(demandThresholds(12), (lowMax: 4, mediumMax: 8));
    expect(demandLevel(1, 12), 'Low');
    expect(demandLevel(6, 12), 'Medium');
    expect(demandLevel(12, 12), 'High');
  });

  group('the report', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final r = records([
      order('a', 'Grains'),
      order('b', 'Vegetables'),
      order('c', 'Grains', barangay: 'San Gabriel', town: 'Laurel'),
    ]);

    test('Buyer Demand has no product figures', () {
      final data = demandReportData(
        r,
        mode: DemandMode.buyer,
        periodLabel: 'November 2026',
        counting: DemandCounting.completedOrders,
        category: 'Grains',
      );
      expect(data.counting, DemandCounting.uniqueBuyers);
      expect(data.category, isNull);
      expect(data.categories, isEmpty);
      expect(data.uniqueBuyers, 3);
      expect(data.areas.first.count, 2);
    });

    test('Product Demand follows the category and counting method', () {
      final data = demandReportData(
        r,
        mode: DemandMode.product,
        periodLabel: 'November 2026',
        counting: DemandCounting.completedOrders,
        category: 'Grains',
      );
      expect(data.total, 2);
      expect([for (final a in data.areas) a.count], [1, 1]);
      expect(data.categories, isNotEmpty);
    });

    for (final mode in DemandMode.values) {
      test('the ${mode.label} PDF builds, with data and without', () async {
        for (final input in [r, <DemandRecord>[]]) {
          final bytes = await PdfReportService.buildDemandHeatmapReport(
            demandReportData(input, mode: mode, periodLabel: 'November 2026'),
            generatedAt: DateTime(2026, 11, 9, 22),
          );
          expect(bytes.length, greaterThan(1000));
        }
      });
    }
  });

  group('the panels', () {
    Future<void> pump(WidgetTester tester, Widget child) {
      tester.view.physicalSize = const Size(900, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          home: AdminThemeScope(
            palette: AdminPalette.light,
            child: Scaffold(
              body: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      );
    }

    testWidgets('the legend shows the numbers of each level', (tester) async {
      await pump(
        tester,
        const Align(
          child: AdminHeatLegend(
            thresholds: (lowMax: 1, mediumMax: 3),
            unitPlural: 'buyers',
          ),
        ),
      );
      expect(find.text('Green = Low Demand (1 buyer)'), findsOneWidget);
      expect(
        find.text('Yellow/Orange = Medium Demand (2–3 buyers)'),
        findsOneWidget,
      );
      expect(find.text('Red = High Demand (4+ buyers)'), findsOneWidget);
    });

    testWidgets('Product Demand Summary: names, counts and bars, no icons; '
        'its radio buttons switch the counting', (tester) async {
      DemandCounting? chosen;
      String? category;
      final summary = categoryDemand(
        records([order('a', 'Grains'), order('b', 'Vegetables')]),
        counting: DemandCounting.uniqueBuyers,
      );
      await pump(
        tester,
        SizedBox(
          height: 520,
          child: AdminProductDemandSummary(
            rows: summary.rows,
            counting: DemandCounting.uniqueBuyers,
            onCountingChanged: (value) => chosen = value,
            selectedCategory: null,
            onSelectCategory: (value) => category = value,
            emptyText: 'None',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Grains'), findsOneWidget);
      expect(find.text('1 buyer'), findsNWidgets(2));
      expect(find.text('50.0% of buyers'), findsNWidgets(2));
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      // No icon inside a category row.
      expect(
        find.descendant(
          of: find.byKey(const Key('categoryRow_Grains')),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('counting_completedOrders')));
      expect(chosen, DemandCounting.completedOrders);
      await tester.tap(find.byKey(const Key('categoryRow_Grains')));
      expect(category, 'Grains');
    });
  });
}
