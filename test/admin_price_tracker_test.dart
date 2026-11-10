// The Admin Dashboard's price tracker (Average Price vs. Admin Baseline,
// the user's reference of 2026-11-10): quantity-weighted retail prices of
// completed orders by day, the baseline as it stood each day, the three
// figure cards, the AgriTrade+ | Compare chart and the date ranges. Real
// records only, never mixed units.
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:agritrade/screen/admin_price_tracker.dart';
import 'package:agritrade/services/price_tracker_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 10, 9);

Map<String, dynamic> order(
  String commodity,
  num quantity,
  num price,
  DateTime completed, {
  String unit = 'kg',
  String status = 'completed',
  String pricingType = 'retail',
}) => {
  'status': status,
  'commodity': commodity,
  'productName': commodity,
  'quantity': quantity,
  'unit': unit,
  'pricePerUnit': price,
  'total': quantity * price,
  'pricingType': pricingType,
  'completedAt': Timestamp.fromDate(completed),
};

final orders = [
  order('Corn', 10, 50, DateTime(2026, 11, 2, 10)),
  order('Corn', 30, 70, DateTime(2026, 11, 2, 15)),
  order('Corn', 5, 60, DateTime(2026, 9, 1, 8)),
  order('Corn', 100, 40, DateTime(2026, 11, 3), pricingType: 'wholesale'),
  order('Corn', 2, 90, DateTime(2026, 11, 4), unit: 'sack'),
  order('Corn', 9, 99, DateTime(2026, 11, 5), status: 'shipped'),
  order('Rice', 4, 55, DateTime(2026, 11, 6)),
];

void main() {
  group('the numbers', () {
    test('a day\'s price is weighted by quantity; wholesale, other units '
        'and unfinished orders are left out', () {
      final daily = dailyAveragePrices(orders, commodity: 'Corn', unit: 'kg');
      expect(
        [for (final d in daily.days) d.day],
        [DateTime(2026, 9, 1), DateTime(2026, 11, 2)],
      );
      // (10 × 50 + 30 × 70) / 40 kg.
      expect(daily.days.last.average, 65);
      expect(daily.days.last.sales, 2);
      expect(daily.otherUnitSales, 1);
    });

    test('the baseline steps: history and the current record, in the '
        'commodity\'s unit, the later record winning a day', () {
      final steps = baselineSteps(
        [
          {
            'price': 55,
            'unit': 'kg',
            'effectiveDate': Timestamp.fromDate(DateTime(2026, 8, 1)),
          },
          {
            'price': 900,
            'unit': 'sack',
            'effectiveDate': Timestamp.fromDate(DateTime(2026, 9, 1)),
          },
          {
            'price': 58,
            'unit': 'kg',
            'effectiveDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
            'recordedAt': Timestamp.fromDate(DateTime(2026, 10, 1, 8)),
          },
        ],
        current: {
          'baselinePrice': 62,
          'unit': 'kg',
          'effectiveDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 1, 9)),
        },
        unit: 'kg',
      );
      expect([for (final s in steps) s.price], [55, 62]);
      expect(baselineOn(steps, DateTime(2026, 7, 31)), isNull);
      expect(baselineOn(steps, DateTime(2026, 9, 15)), 55);
      expect(baselineOn(steps, DateTime(2026, 11, 1)), 62);
    });

    test('the windows and the cards agree', () {
      final days = dailyAveragePrices(
        orders,
        commodity: 'Corn',
        unit: 'kg',
      ).days;
      final steps = [BaselineStep(DateTime(2026, 8, 1), 60)];
      final week = trackerWindow(
        TrackerRange.week,
        now: now,
        days: days,
        steps: steps,
      );
      expect(week.start, DateTime(2026, 11, 4));
      expect(week.end, DateTime(2026, 11, 10));
      final all = trackerWindow(
        TrackerRange.all,
        now: now,
        days: days,
        steps: steps,
      );
      expect(all.start, DateTime(2026, 8, 1));

      final summary = PriceTrackerSummary.of(days, steps, all);
      // (5 × 60 + 10 × 50 + 30 × 70) / 45 kg.
      expect(summary.average, closeTo(64.44, 0.01));
      expect(summary.sales, 3);
      expect(summary.baseline, 60);
      expect(summary.difference, closeTo(4.44, 0.01));
      expect(summary.differencePercent, closeTo(7.41, 0.01));
      // From ₱60 on Sep 1 to ₱65 on Nov 2.
      expect(summary.changePercent, closeTo(8.33, 0.01));

      final empty = PriceTrackerSummary.of(days, steps, week);
      expect(empty.average, isNull);
      expect(empty.difference, isNull);
      expect(empty.changePercent, isNull);
    });
  });

  group('the tracker', () {
    final commodities = [
      const PriceTrackerCommodity(
        id: 'corn',
        name: 'Corn',
        category: 'Grains',
        unit: 'kg',
        record: {'baselinePrice': 60, 'unit': 'kg'},
      ),
      const PriceTrackerCommodity(
        id: 'rice',
        name: 'Rice',
        category: 'Grains',
        unit: 'kg',
      ),
      const PriceTrackerCommodity(
        id: 'coconut',
        name: 'Coconut',
        category: 'Fruits',
        unit: 'piece',
      ),
    ];

    Future<void> pump(WidgetTester tester) async {
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
                child: AdminPriceTracker(
                  commodities: commodities,
                  completedOrders: orders,
                  now: now,
                  loadBaselineHistory: (id) async => [
                    if (id == 'corn')
                      {
                        'price': 60,
                        'unit': 'kg',
                        'effectiveDate': Timestamp.fromDate(
                          DateTime(2026, 8, 1),
                        ),
                      },
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String textIn(WidgetTester tester, Key key) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join(' | ');

    testWidgets('a text-only list, the three figures and the chart', (
      tester,
    ) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      // No pictures anywhere in the list.
      expect(find.byType(Image), findsNothing);
      // Opens on the commodity sold most recently: Rice (Nov 6).
      expect(find.text('Rice'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('priceTrackerRow_corn')));
      await tester.pumpAndSettle();
      expect(find.text('Corn'), findsNWidgets(2));
      expect(find.text('Grains · per kg · Nov 2, 2026'), findsOneWidget);
      expect(find.text('Fruits · per piece · No sales yet'), findsOneWidget);

      expect(
        textIn(tester, const Key('priceTrackerAverage')),
        'AGRITRADE+ AVERAGE PRICE | ₱64.44 | /kg · 3 sales',
      );
      expect(
        textIn(tester, const Key('priceTrackerBaseline')),
        'ADMIN BASELINE | ₱60.00 | /kg',
      );
      expect(
        textIn(tester, const Key('priceTrackerDifference')),
        'PRICE DIFFERENCE | +₱4.44 | 7.4% above the baseline',
      );
      expect(find.text('+8.3%'), findsOneWidget);
      expect(find.text('2 days of data'), findsOneWidget);
      // The sack sold is said, not mixed in.
      expect(
        find.text(
          '1 completed sale in another unit not compared: prices here are '
          'per kg.',
        ),
        findsOneWidget,
      );
      // Compare: two lines, the second the baseline.
      expect(find.text('Admin Baseline'), findsOneWidget);
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData,
        hasLength(2),
      );
    });

    testWidgets('AgriTrade+ alone, the date ranges, and search', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('priceTrackerRow_corn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('priceTrackerTab_agritrade')));
      await tester.pumpAndSettle();
      expect(find.text('Admin Baseline'), findsNothing);
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData,
        hasLength(1),
      );

      // Nothing sold in the last 7 days: said, not drawn.
      await tester.tap(find.byKey(const Key('priceTrackerRange_week')));
      await tester.pumpAndSettle();
      expect(find.text('0 days of data'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      expect(
        find.text('No completed retail sales in this period.'),
        findsOneWidget,
      );
      expect(
        textIn(tester, const Key('priceTrackerDifference')),
        'PRICE DIFFERENCE | — | Needs a sale and a baseline',
      );

      await tester.enterText(
        find.byKey(const Key('priceTrackerSearch')),
        'coc',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('priceTrackerRow_corn')), findsNothing);
      await tester.tap(find.byKey(const Key('priceTrackerRow_coconut')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        textIn(tester, const Key('priceTrackerBaseline')),
        'ADMIN BASELINE | — | Not set for this period',
      );
    });

    testWidgets('hovering anywhere: a line that follows the pointer and a '
        'white box, AgriTrade+ in green and the baseline in red', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('priceTrackerRow_corn')));
      await tester.pumpAndSettle();
      final chart = tester.getRect(find.byType(LineChart));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(chart.center);
      await tester.pump();
      expect(find.byKey(const Key('priceTrackerHoverLine')), findsOneWidget);
      final firstX = tester
          .getTopLeft(find.byKey(const Key('priceTrackerHoverLine')))
          .dx;
      // Between two sale days: the last real sale, dated, never a made-up
      // price from the line between them.
      expect(find.textContaining('last sale Sep 1'), findsOneWidget);
      final box = tester.widget<Container>(
        find.byKey(const Key('priceTrackerTooltip')),
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        AdminPalette.light.surface,
      );
      final agri = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('priceTrackerTooltip')),
              matching: find.byType(Text),
            )
            .at(1),
      );
      expect(
        (agri.textSpan! as TextSpan).children!.first.style!.color,
        isNot(AdminPalette.light.textPrimary),
      );
      expect(find.text('Admin Baseline: ₱60.00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Admin Baseline: ₱60.00')).style!.color,
        const Color(0xFFC0392B),
      );

      // It follows the pointer smoothly, not only from point to point.
      await mouse.moveTo(chart.center + const Offset(37, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const Key('priceTrackerHoverLine'))).dx,
        closeTo(firstX + 37, 0.01),
      );

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byKey(const Key('priceTrackerHoverLine')), findsNothing);
    });

    testWidgets('the category chips filter the list', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Fruits'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('priceTrackerRow_corn')), findsNothing);
      expect(find.byKey(const Key('priceTrackerRow_coconut')), findsOneWidget);
    });
  });
}
