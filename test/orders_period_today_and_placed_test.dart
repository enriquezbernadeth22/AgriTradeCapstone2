// Orders can be shown for a period (today, the last 7 days, …); Market's
// Orders Today counts the orders confirmed today; and a buyer who places an
// order sees an Order Placed summary of it.
import 'package:agritrade/screen/market_tab.dart' show confirmedTodayCount;
import 'package:agritrade/screen/place_order_screen.dart'
    show showOrderPlacedDialog;
import 'package:agritrade/services/order_date_filter.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  final now = DateTime(2026, 11, 5, 15, 30);

  group('the period of Orders', () {
    bool shows(OrderDateFilter filter, DateTime placed) =>
        placedIn(placed, filter.rangeOn(now), now: now);

    test('All time shows everything', () {
      expect(OrderDateFilter.all.rangeOn(now), isNull);
      expect(shows(OrderDateFilter.all, DateTime(2020, 1, 1)), isTrue);
    });

    test('Today is today only, all day', () {
      expect(shows(OrderDateFilter.today, DateTime(2026, 11, 5, 0, 1)), isTrue);
      expect(
        shows(OrderDateFilter.today, DateTime(2026, 11, 5, 23, 59)),
        isTrue,
      );
      expect(
        shows(OrderDateFilter.today, DateTime(2026, 11, 4, 23, 59)),
        isFalse,
      );
    });

    test('Last 7 days counts today as the seventh', () {
      expect(shows(OrderDateFilter.last7Days, DateTime(2026, 10, 30)), isTrue);
      expect(shows(OrderDateFilter.last7Days, DateTime(2026, 10, 29)), isFalse);
    });

    test('months and the year', () {
      expect(shows(OrderDateFilter.last3Months, DateTime(2026, 8, 5)), isTrue);
      expect(shows(OrderDateFilter.last3Months, DateTime(2026, 8, 4)), isFalse);
      expect(shows(OrderDateFilter.last6Months, DateTime(2026, 5, 5)), isTrue);
      expect(shows(OrderDateFilter.thisYear, DateTime(2026, 1, 1)), isTrue);
      expect(shows(OrderDateFilter.thisYear, DateTime(2025, 12, 31)), isFalse);
    });

    test('a custom range includes both ends', () {
      final range = DateTimeRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 10),
      );
      final r = OrderDateFilter.custom.rangeOn(now, customRange: range);
      expect(placedIn(DateTime(2026, 10, 10, 22), r, now: now), isTrue);
      expect(placedIn(DateTime(2026, 10, 11), r, now: now), isFalse);
    });

    test('an order not yet stamped counts as today', () {
      expect(
        placedIn(null, OrderDateFilter.today.rangeOn(now), now: now),
        isTrue,
      );
    });
  });

  test('Orders Today counts the orders confirmed today and still to send', () {
    Timestamp at(DateTime d) => Timestamp.fromDate(d);
    final orders = [
      // Confirmed today (stamped when the stock was taken): counts.
      {'status': 'confirmed', 'stockDeductedAt': at(DateTime(2026, 11, 5, 9))},
      // An older order confirmed today (no stamp; last update today).
      {'status': 'confirmed', 'updatedAt': at(DateTime(2026, 11, 5, 8))},
      // Confirmed yesterday: not today's.
      {'status': 'confirmed', 'stockDeductedAt': at(DateTime(2026, 11, 4))},
      // Placed today but not confirmed yet, or already sent: not counted.
      {'status': 'pending', 'createdAt': at(DateTime(2026, 11, 5, 10))},
      {'status': 'shipped', 'stockDeductedAt': at(DateTime(2026, 11, 5, 7))},
    ];
    expect(confirmedTodayCount(orders, now: now), 2);
  });

  testWidgets('placing an order shows Order Placed with its summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOrderPlacedDialog(
                context,
                farmerName: 'Juan',
                lines: const [
                  ('Product', 'Eggplant'),
                  ('Order type', 'Wholesale'),
                  ('Quantity', '20 kg'),
                ],
                total: '₱800.00',
              ),
              child: const Text('place'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('place'));
    await tester.pumpAndSettle();
    expect(find.text('Order Placed!'), findsOneWidget);
    expect(find.textContaining('sent to Juan'), findsOneWidget);
    expect(find.text('Wholesale'), findsOneWidget);
    expect(find.text('20 kg'), findsOneWidget);
    expect(find.text('₱800.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('orderPlacedDone')));
    await tester.pumpAndSettle();
    expect(find.text('Order Placed!'), findsNothing);
  });

  testWidgets('with a delivery fee still to agree, it says so instead of a '
      'total', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showOrderPlacedDialog(
                context,
                farmerName: 'Juan',
                lines: const [('Product', 'Corn')],
                totalNote: 'Product subtotal ₱100.00 + delivery fee.',
              ),
              child: const Text('place'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('place'));
    await tester.pumpAndSettle();
    expect(find.text('Total'), findsNothing);
    expect(find.textContaining('+ delivery fee'), findsOneWidget);
  });
}
