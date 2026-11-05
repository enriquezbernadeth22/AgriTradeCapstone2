// The Farmer's Best-Selling Products and Top Buyer Locations cards: they open
// on the current month, say so when it is empty, never pass an earlier month
// off as the current one, and fill in by themselves when an order completes.
import 'dart:async';

import 'package:agritrade/l10n/app_localizations.dart';
import 'package:agritrade/services/market_demand_service.dart';
import 'package:agritrade/widgets/market_demand_cards.dart';
import 'package:agritrade/widgets/month_year_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Map<String, dynamic> _sale(
  String product,
  DateTime date, {
  num quantity = 1,
  String unit = 'kg',
}) => {
  'productName': product,
  'status': 'completed',
  'unit': unit,
  'quantity': quantity,
  'buyerArea': 'Laurel',
  'completedAt': Timestamp.fromDate(date),
};

void main() {
  final november = DateTime(2026, 11);
  final today = DateTime(2026, 11, 5);

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<StreamController<List<Map<String, dynamic>>>> pumpCards(
    WidgetTester tester, [
    List<Map<String, dynamic>> sales = const [],
  ]) async {
    final controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketDemandCards(
              month: november,
              salesStream: controller.stream,
              now: today,
            ),
          ),
        ),
      ),
    );
    controller.add(sales);
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('an empty current month says so, with nothing from before', (
    tester,
  ) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 10, 12))]);

    expect(find.text('Nov 2026'), findsNWidgets(2));
    expect(find.textContaining('No completed orders in November'), findsOne);
    expect(find.text('Eggplant'), findsNothing);
  });

  testWidgets('"View previous month" moves only the card it is on', (
    tester,
  ) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 10, 12))]);

    // On Best-Selling Products.
    await tester.tap(find.text('View previous month').first);
    await tester.pump();
    expect(find.text('Oct 2026'), findsOneWidget);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Eggplant'), findsOneWidget);
    expect(find.text('Laurel'), findsNothing);

    // Then on Top Buyer Locations.
    await tester.tap(find.text('View previous month'));
    await tester.pump();
    expect(find.text('Oct 2026'), findsNWidgets(2));
    expect(find.text('Laurel'), findsOneWidget);
  });

  testWidgets('with nothing earlier on record there is no month to go to', (
    tester,
  ) async {
    await pumpCards(tester);

    expect(find.text('View previous month'), findsNothing);
    expect(find.text('Nov 2026'), findsNWidgets(2));

    // The calendar still opens, with only this month to choose.
    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('October'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Nov 2026'), findsNWidgets(2));
  });

  testWidgets('the month selector always shows the short month', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthPickerPill(month: november, onTap: () {}),
        ),
      ),
    );
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('November 2026'), findsNothing);
  });

  testWidgets('the month selector is a calendar, not a dropdown', (
    tester,
  ) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 9, 3))]);

    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<DateTime>), findsNothing);
    expect(find.text('Select Month'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    for (final month in ['January', 'June', 'December']) {
      expect(find.text(month), findsOneWidget);
    }
  });

  testWidgets('a month chosen on one card leaves the other card on its own '
      'month', (tester) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 9, 3))]);

    // Best-Selling Products to September.
    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('September'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Sep 2026'), findsOneWidget);
    expect(find.text('Eggplant'), findsOneWidget);
    // Top Buyer Locations is still on November, and empty.
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Laurel'), findsNothing);
    expect(
      find.textContaining(
        'No buyer locations on record for completed '
        'orders in November 2026',
      ),
      findsOneWidget,
    );

    // Top Buyer Locations to September, on its own pill.
    await tester.tap(find.text('Nov 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Sep 2026'), findsNWidgets(2));
    expect(find.text('Laurel'), findsOneWidget);
  });

  testWidgets('months before the first sale and after today cannot be chosen', (
    tester,
  ) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 9, 3))]);

    for (final month in ['August', 'December']) {
      await tester.tap(find.text('Nov 2026').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(month));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Nov 2026'), findsNWidgets(2), reason: month);
    }
  });

  testWidgets('Cancel keeps the month on show', (tester) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 9, 3))]);

    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('September'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Nov 2026'), findsNWidgets(2));
    expect(find.text('Eggplant'), findsNothing);
  });

  testWidgets('the calendar says where the months come from', (tester) async {
    await pumpCards(tester, [_sale('Eggplant', DateTime(2026, 9, 3))]);

    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Available from September 2026, based on the '
        'completed orders on record',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('verification date'), findsNothing);
  });

  testWidgets('the arrows reach an earlier year only when it has sales', (
    tester,
  ) async {
    await pumpCards(tester, [_sale('Corn', DateTime(2025, 12, 3))]);

    await tester.tap(find.text('Nov 2026').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget, reason: '2024 has no sales');

    await tester.tap(find.text('December'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Dec 2025'), findsOneWidget);
    expect(find.text('Corn'), findsOneWidget);
  });

  testWidgets('the card fills in as soon as an order completes', (
    tester,
  ) async {
    final sales = await pumpCards(tester);
    expect(find.text('Eggplant'), findsNothing);

    sales.add([_sale('Eggplant', DateTime(2026, 11, 2), quantity: 12)]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Eggplant'), findsOneWidget);
    expect(find.text('12 kg'), findsOneWidget);
    expect(find.textContaining('No completed orders'), findsNothing);
  });

  testWidgets('rows show the quantity sold, largest first', (tester) async {
    await pumpCards(tester, [
      _sale('Cattle', DateTime(2026, 11, 2), quantity: 2, unit: 'head'),
      _sale('Eggplant', DateTime(2026, 11, 3), quantity: 50),
    ]);

    expect(find.text('50 kg'), findsOneWidget);
    expect(find.text('2 heads'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Eggplant')).dy,
      lessThan(tester.getTopLeft(find.text('Cattle')).dy),
    );
  });

  testWidgets('tapping a buyer location shows what buyers there ordered', (
    tester,
  ) async {
    await pumpCards(tester, [
      _sale('Eggplant', DateTime(2026, 11, 2)),
      _sale('Eggplant', DateTime(2026, 11, 3)),
      _sale('Corn', DateTime(2026, 11, 4)),
    ]);

    await tester.tap(find.text('Laurel'));
    await tester.pumpAndSettle();

    expect(
      find.text('Completed orders from buyers here in November 2026'),
      findsOneWidget,
    );
    expect(find.text('2 orders'), findsOneWidget);
    expect(find.text('1 order'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2 orders')).dy,
      lessThan(tester.getTopLeft(find.text('1 order')).dy),
    );
  });

  test('Best-Selling Products lists the top five', () {
    expect(MarketDemandService.bestSellerLimit, 5);
  });
}
