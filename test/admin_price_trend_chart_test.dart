import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/screen/admin_analytics_widgets.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:agritrade/screen/admin_price_trend_chart.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sale(
  String product,
  int year,
  int month,
  num quantity,
  num price,
) => {
  'status': 'completed',
  'productName': product,
  'unit': 'kg',
  'quantity': quantity,
  'pricingType': 'retail',
  'pricePerUnit': price,
  'completedAt': Timestamp.fromDate(DateTime(year, month, 10)),
};

Future<void> _show(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  final now = DateTime.now();
  final year = now.year;

  setUp(
    () => CommodityRegistry.instance.applyAdminRecords([
      {'name': 'Tomato', 'category': 'Vegetables', 'unit': 'kg'},
      {'name': 'Cassava', 'category': 'Root Crops', 'unit': 'kg'},
    ]),
  );
  tearDown(() => CommodityRegistry.instance.applyAdminRecords(const []));

  // October 2026: last year is 2025, and November and December of 2026
  // have not come yet.
  final october = DateTime(2026, 10, 15);

  // [n] completed orders of [product] in [month] of [inYear].
  List<Map<String, dynamic>> orders(
    String product,
    int inYear,
    int month,
    int n,
  ) => [for (var i = 0; i < n; i++) _sale(product, inYear, month, 1, 50)];

  List<Map<String, dynamic>> history() => [
    ...orders('Tomato', 2025, 3, 3),
    ...orders('Tomato', 2025, 7, 2),
    ...orders('Tomato', 2026, 3, 5),
    ...orders('Tomato', 2026, 10, 1),
    ...orders('Cassava', 2026, 1, 1),
    // Not completed: never counted.
    {..._sale('Tomato', 2026, 3, 1, 50), 'status': 'pending'},
  ];

  // Types [query] in the search and picks [name] from the suggestions.
  Future<void> search(WidgetTester tester, String query, String name) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  // The [index]th year calendar (0: earlier, 1: later) set to [year].
  Future<void> pickYear(WidgetTester tester, int index, int year) async {
    await tester.tap(find.byType(AdminYearPill).at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$year').last);
    await tester.pumpAndSettle();
  }

  List<BarChartGroupData> bars(WidgetTester tester) =>
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;

  group('Market Demand metric', () {
    // A completed order of [product] completing at [at].
    Map<String, dynamic> done(String product, DateTime at, {num qty = 1}) => {
      ..._sale(product, at.year, at.month, qty, 50),
      'completedAt': Timestamp.fromDate(at),
    };

    test('counts completed orders only, one per order whatever its '
        'quantity or unit', () {
      final march = DateTime(2026, 3, 10);
      final monthly = DashboardAnalyticsService.monthlyCompletedOrders(
        [
          done('Tomato', march),
          // 40 kg is still one order.
          done('Tomato', march, qty: 40),
          {...done('Tomato', march), 'unit': 'piece'},
          for (final status in ['pending', 'cancelled', 'rejected', 'accepted'])
            {...done('Tomato', march), 'status': status},
          done('Cassava', march),
        ],
        'Tomato',
        2026,
      );
      expect(monthly[2], 3);
      expect(monthly.fold<int>(0, (s, n) => s + n), 3);
    });

    test('a listing counts under its commodity, matched without regard to '
        'case', () {
      final monthly = DashboardAnalyticsService.monthlyCompletedOrders(
        [
          {
            ...done('Cherry Tomato', DateTime(2026, 5, 2)),
            'commodity': 'Tomato',
          },
          done('tomato', DateTime(2026, 5, 3)),
        ],
        'tomato',
        2026,
      );
      expect(monthly[4], 2);
    });

    test('dated by when the order completed, at the edges of a year', () {
      final orders = [
        // Placed in December 2025, completed in January 2026.
        {
          ...done('Tomato', DateTime(2026, 1, 1, 0, 5)),
          'createdAt': Timestamp.fromDate(DateTime(2025, 12, 30)),
        },
        done('Tomato', DateTime(2025, 12, 31, 23, 59)),
        // An older order with no completedAt: its last status write.
        {
          ..._sale('Tomato', 2026, 2, 1, 50)..remove('completedAt'),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 2, 14)),
        },
      ];
      final y2025 = DashboardAnalyticsService.monthlyCompletedOrders(
        orders,
        'Tomato',
        2025,
      );
      final y2026 = DashboardAnalyticsService.monthlyCompletedOrders(
        orders,
        'Tomato',
        2026,
      );
      expect(y2025[11], 1);
      expect(y2025.fold<int>(0, (s, n) => s + n), 1);
      expect(y2026[0], 1);
      expect(y2026[1], 1);
    });
  });

  testWidgets('Market Demand asks for a product before showing anything', (
    tester,
  ) async {
    await _show(
      tester,
      AdminMarketDemandCard(now: october, completedOrders: history()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Market Demand'), findsOneWidget);
    expect(
      find.text('Compare monthly product demand across selected years.'),
      findsOneWidget,
    );
    // Nothing is picked for the Admin.
    expect(find.byType(BarChart), findsNothing);
    expect(find.textContaining('Search for a product'), findsOneWidget);
    // The controls are there, one height, level with each other.
    final pills = find.byType(AdminYearPill);
    expect(pills, findsNWidgets(2));
    final field = find.byType(AdminCommoditySearchField);
    final info = find.byIcon(Icons.info_outline);
    for (final control in [pills.first, pills.last, field]) {
      expect(tester.getSize(control).height, kAdminControlHeight);
      expect(
        tester.getCenter(control).dy,
        closeTo(tester.getCenter(pills.first).dy, 0.5),
      );
    }
    expect(
      tester.getCenter(info).dy,
      closeTo(tester.getCenter(pills.first).dy, 0.5),
    );
    // This year against the one before.
    expect(tester.widget<AdminYearPill>(pills.first).year, 2025);
    expect(tester.widget<AdminYearPill>(pills.last).year, 2026);
  });

  testWidgets('Market Demand: each month January to December, the earlier '
      'year light green beside the later dark green', (tester) async {
    await _show(
      tester,
      AdminMarketDemandCard(now: october, completedOrders: history()),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    expect(tester.takeException(), isNull);

    final groups = bars(tester);
    expect(groups, hasLength(12));
    for (final group in groups) {
      expect(group.barRods, hasLength(2));
    }
    final march = groups[2].barRods;
    expect(march[0].toY, 3); // 2025
    expect(march[1].toY, 5); // 2026 — the pending order is not counted
    expect(march[0].color, const Color(0xFFA5D6A7));
    expect(march[1].color, const Color(0xFF2E7D32));
    expect(groups[6].barRods[0].toY, 2); // July 2025
    expect(groups[6].barRods[1].toY, 0); // July 2026: none
    // November 2026 has not come: no bar.
    expect(groups[10].barRods[1].color, Colors.transparent);

    // The tooltip: the product, the month and both years' figures.
    final data = tester.widget<BarChart>(find.byType(BarChart)).data;
    final tip = data.barTouchData.touchTooltipData.getTooltipItem(
      groups[2],
      2,
      march[1],
      1,
    )!;
    expect(tip.text, 'Tomato · March\n');
    expect(
      tip.children!.single.toPlainText(),
      '2025: 3 orders\n2026: 5 orders',
    );
    final november = data.barTouchData.touchTooltipData.getTooltipItem(
      groups[10],
      10,
      groups[10].barRods[1],
      1,
    )!;
    expect(november.children!.single.toPlainText(), endsWith('2026: not yet'));
    expect(find.text('Completed Orders'), findsOneWidget);
    expect(
      find.text('Based on AgriTrade+ completed orders only.'),
      findsOneWidget,
    );

    // The summary starts closed; opened, it is under the chart.
    expect(find.textContaining('2025  5 orders'), findsNothing);
    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2025  5 orders'), findsOneWidget);
    expect(find.textContaining('2026  6 orders so far'), findsOneWidget);
    // January to October of both years: 5 then 6.
    expect(find.textContaining('Change, Jan–Oct  +20%'), findsOneWidget);
    expect(
      find.textContaining('Busiest month · 2025  Mar · 3 orders'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Busiest month · 2026  Mar · 5 orders'),
      findsOneWidget,
    );
    // How demand is counted: only on a click of ⓘ, in a popup.
    expect(find.text('How Market Demand is counted'), findsNothing);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('How Market Demand is counted'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('How Market Demand is counted'), findsNothing);

    // The summary is under the chart, and closes again.
    expect(
      tester.getTopLeft(find.textContaining('2025  5 orders')).dy,
      greaterThan(tester.getBottomLeft(find.byType(BarChart)).dy),
    );
    await tester.tap(find.text('Hide summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2025  5 orders'), findsNothing);

    // Another product: the chart follows.
    await search(tester, 'cas', 'Cassava');
    expect(bars(tester)[0].barRods[0].toY, 0);
    expect(bars(tester)[0].barRods[1].toY, 1);
  });

  testWidgets('Market Demand: the earlier year is light green whichever '
      'calendar picked it', (tester) async {
    await _show(
      tester,
      AdminMarketDemandCard(
        now: october,
        completedOrders: [...history(), ...orders('Tomato', 2024, 3, 4)],
      ),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    List<int?> pickedYears() => [
      for (final pill in tester.widgetList<AdminYearPill>(
        find.byType(AdminYearPill),
      ))
        pill.year,
    ];

    // 2024 against 2026.
    await pickYear(tester, 0, 2024);
    expect(pickedYears(), [2024, 2026]);
    expect(bars(tester)[2].barRods.map((r) => r.toY), [4, 5]);

    // The later calendar set to 2025: 2024 against 2025.
    await pickYear(tester, 1, 2025);
    expect(pickedYears(), [2024, 2025]);
    expect(bars(tester)[2].barRods.map((r) => r.toY), [4, 3]);

    // The first calendar set past the second: they are put in order.
    await pickYear(tester, 0, 2026);
    expect(pickedYears(), [2025, 2026]);
    final march = bars(tester)[2].barRods;
    expect(march.map((r) => r.toY), [3, 5]);
    expect(march[0].color, AdminMarketDemandCard.earlierColor);
    expect(march[1].color, AdminMarketDemandCard.laterColor);
  });

  testWidgets('Market Demand offers no year before the first completed '
      'order: one year alone, one bar a month', (tester) async {
    await _show(
      tester,
      AdminMarketDemandCard(
        now: october,
        completedOrders: [
          ...orders('Tomato', 2026, 3, 5),
          ...orders('Tomato', 2026, 10, 1),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('2025'), findsNothing);
    expect(find.text('vs'), findsNothing);
    expect(find.byType(AdminYearPill), findsOneWidget);
    final groups = bars(tester);
    expect(groups, hasLength(12));
    expect(groups[2].barRods.single.toY, 5);
    expect(groups[2].barRods.single.color, AdminMarketDemandCard.laterColor);
    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026  6 orders so far'), findsOneWidget);
    expect(find.textContaining('Change,'), findsNothing);

    // The year calendar: 2026 to pick, no year before it.
    await tester.tap(find.byType(AdminYearPill));
    await tester.pumpAndSettle();
    expect(find.text('2026 – 2037'), findsOneWidget);
    expect(find.text('2025'), findsNothing);
  });

  testWidgets('Market Demand says when no product matches the search', (
    tester,
  ) async {
    await _show(
      tester,
      AdminMarketDemandCard(now: october, completedOrders: history()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('No product matches “zzz”'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);

    // Revised, it finds one.
    await search(tester, 'cas', 'Cassava');
    expect(find.textContaining('No product matches'), findsNothing);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('Market Demand with no completed orders says so', (tester) async {
    await _show(
      tester,
      AdminMarketDemandCard(now: october, completedOrders: const []),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsNothing);
    expect(
      find.textContaining('No completed orders of Tomato in 2026 yet'),
      findsOneWidget,
    );
    expect(find.textContaining('2025'), findsNothing);
  });

  testWidgets('Market Demand on a phone-width card: the controls wrap and '
      'all twelve months still fit', (tester) async {
    tester.view.physicalSize = const Size(380, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Scaffold(
            body: SingleChildScrollView(
              child: AdminMarketDemandCard(
                now: october,
                completedOrders: history(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    expect(tester.takeException(), isNull);
    expect(bars(tester), hasLength(12));
    // The search went onto a row of its own, under the years.
    expect(
      tester.getTopLeft(find.byType(AdminCommoditySearchField)).dy,
      greaterThan(tester.getBottomLeft(find.byType(AdminYearPill).first).dy),
    );
  });

  testWidgets('Market Demand: orders that failed to load, and a retry', (
    tester,
  ) async {
    var retries = 0;
    await _show(
      tester,
      AdminMarketDemandCard(
        now: october,
        completedOrders: history(),
        error: 'permission-denied',
        onRetry: () => retries++,
      ),
    );
    await tester.pumpAndSettle();
    await search(tester, 'tom', 'Tomato');
    expect(find.byType(BarChart), findsNothing);
    expect(
      find.textContaining('Could not load completed orders'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Price Trend: two lines of average price, and the change', (
    tester,
  ) async {
    await _show(
      tester,
      AdminPriceTrendSection(
        commodity: 'Tomato',
        products: const [],
        completedOrders: [
          _sale('Tomato', year - 1, 2, 10, 50),
          _sale('Tomato', year - 1, 6, 20, 55),
          _sale('Tomato', year, 2, 15, 60),
        ],
        historical: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Price Trend'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    // The same year calendars as Market Demand: last year vs this year.
    final pills = tester.widgetList<AdminYearPill>(find.byType(AdminYearPill));
    expect([for (final p in pills) p.year], [year - 1, year]);
    expect(find.text('vs'), findsOneWidget);
    // (50 + 55) / 2 = 52.50 against 60.00.
    expect(find.text('up 14.3%'), findsOneWidget);
    expect(
      find.textContaining(
        'Based on 0 farmer listings, 3 completed sales, 0 Admin reference '
        'prices and 0 imported records',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Price Trend: any two years on record, picked on the year '
      'calendars', (tester) async {
    await _show(
      tester,
      AdminPriceTrendSection(
        commodity: 'Tomato',
        products: const [],
        completedOrders: [
          _sale('Tomato', 2024, 2, 10, 40),
          _sale('Tomato', 2025, 2, 10, 50),
          _sale('Tomato', 2026, 2, 10, 60),
        ],
        historical: const [],
        now: october,
      ),
    );
    await tester.pumpAndSettle();
    // 2025 vs 2026 to start; the earlier calendar set to 2024.
    await pickYear(tester, 0, 2024);
    expect(find.textContaining('2024 · avg ₱40.00/kg'), findsOneWidget);
    expect(find.textContaining('2026 · avg ₱60.00/kg'), findsOneWidget);
    expect(find.text('up 50.0%'), findsOneWidget);
  });

  testWidgets('Price Trend offers no year before the first completed order: '
      'one year, one line', (tester) async {
    await _show(
      tester,
      AdminPriceTrendSection(
        commodity: 'Tomato',
        products: const [],
        completedOrders: [
          _sale('Tomato', 2026, 2, 15, 60),
          _sale('Tomato', 2026, 5, 10, 64),
        ],
        // An imported 2025 price is on record, but 2025 is not offered.
        historical: [
          HistoricalDemandRecord(
            year: 2025,
            month: 3,
            commodity: 'Tomato',
            category: 'Vegetables',
            quantity: 100,
            unit: 'kg',
            averagePrice: 40,
            location: 'Laurel',
            source: 'MAO',
          ),
        ],
        now: october,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(1));
    expect(
      chart.data.lineBarsData.single.color,
      AdminYearComparisonChart.currentColor(AdminPalette.light),
    );
    expect(find.textContaining('2025'), findsNothing);
    // One year calendar, as on Market Demand, set to 2026.
    expect(tester.widget<AdminYearPill>(find.byType(AdminYearPill)).year, 2026);
    expect(find.text('vs'), findsNothing);
    expect(find.textContaining('2026 · avg ₱62.00/kg'), findsOneWidget);
    expect(find.textContaining('up '), findsNothing);
    expect(find.textContaining('0 imported records'), findsOneWidget);
  });
}
