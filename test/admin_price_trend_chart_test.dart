import 'package:agritrade/data/commodity_master_list.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart';
import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:agritrade/screen/admin_price_trend_chart.dart';
import 'package:agritrade/services/dashboard_analytics_service.dart';
import 'package:agritrade/services/historical_demand_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  // The [index]th year calendar (0: earlier, 1: later) set to [year].
  Future<void> pickYear(WidgetTester tester, int index, int year) async {
    await tester.tap(find.byType(AdminYearPill).at(index));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$year').last);
    await tester.pumpAndSettle();
  }

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

  testWidgets('the year calendars show the whole year, in the real font', (
    tester,
  ) async {
    // "2026" showed as "20" on Market Demand (2026-11-10): the pill was
    // too narrow for the year in Inter beside its icon and arrow.
    final loader = FontLoader(kAdminFontFamily)
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
    await loader.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminThemeScope(
          palette: AdminPalette.light,
          child: Scaffold(
            body: Center(
              child: AdminYearPill(
                year: 2026,
                firstYear: 2025,
                lastYear: 2026,
                width: AdminYearCompare.yearWidth,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final text = tester.renderObject<RenderParagraph>(find.text('2026'));
    expect(
      text.size.width,
      greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity)),
    );
  });
}
