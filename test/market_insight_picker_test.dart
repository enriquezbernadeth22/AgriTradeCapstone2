import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:agritrade/screen/market_tab.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/market_card_shell.dart';
import 'package:agritrade/widgets/market_demand_cards.dart';
import 'package:agritrade/widgets/month_year_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<List<MarketInsight>> pumpPicker(
    WidgetTester tester, {
    MarketInsight value = MarketInsight.marketAverage,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chosen = <MarketInsight>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: MarketInsightPicker(value: value, onChanged: chosen.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('the three insights side by side, by their right names', (
    tester,
  ) async {
    await pumpPicker(tester);
    final tops = [
      for (final label in ['Best Sellers', 'Market Average', 'Buyer Areas'])
        tester.getCenter(find.text(label)),
    ];
    // One row, in order.
    expect(tops.map((c) => c.dy).toSet(), hasLength(1));
    expect(tops[0].dx, lessThan(tops[1].dx));
    expect(tops[1].dx, lessThan(tops[2].dx));
    // No dropdown any more.
    expect(find.byType(DropdownButton<MarketInsight>), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
  });

  testWidgets('the chosen one is filled dark green with white text', (
    tester,
  ) async {
    await pumpPicker(tester, value: MarketInsight.bestSellers);
    Color? textColor(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;
    expect(textColor('Best Sellers'), Colors.white);
    expect(textColor('Market Average'), isNot(Colors.white));
  });

  testWidgets('tapping another one chooses it', (tester) async {
    final chosen = await pumpPicker(tester);
    await tester.tap(find.text('Buyer Areas'));
    expect(chosen, [MarketInsight.buyerLocations]);
    // The one already chosen does nothing.
    await tester.tap(find.text('Market Average'));
    expect(chosen, [MarketInsight.buyerLocations]);
  });

  testWidgets('it fits a small phone on one row', (tester) async {
    await pumpPicker(tester, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('Buyer Areas'), findsOneWidget);
  });

  testWidgets('the three are always the same size, even on a small phone', (
    tester,
  ) async {
    for (final width in [400.0, 320.0, 280.0]) {
      await pumpPicker(tester, width: width);
      final sizes = {
        for (final label in ['Best Sellers', 'Market Average', 'Buyer Areas'])
          tester.widget<Text>(find.text(label)).style!.fontSize,
      };
      expect(sizes, hasLength(1), reason: 'at  wide: ');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the picker and selected market card share one surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: MarketCardShell(
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('AgriTrade+ Insights'),
                MarketInsightPicker(
                  value: MarketInsight.marketAverage,
                  onChanged: (_) {},
                ),
              ],
            ),
            headerDivider: true,
            child: const MarketCardShell(
              title: null,
              subtitle: 'Average retail price of active marketplace listings',
              embedded: true,
              child: SizedBox(height: 20),
            ),
          ),
        ),
      ),
    );

    final shells = tester.widgetList<MarketCardShell>(
      find.byType(MarketCardShell),
    );
    expect(shells, hasLength(2));
    expect(shells.first.embedded, isFalse);
    expect(shells.last.embedded, isTrue);
    expect(find.text('Market Average'), findsOneWidget);
    expect(
      find.text('Average retail price of active marketplace listings'),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('AgriTrade+ Insights'),
        matching: find.byType(MarketCardShell),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'with the month at the top, a list shows that month and has no own',
    (tester) async {
      final moved = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.themeData(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarketDemandCards(
                month: DateTime(2026, 11),
                only: MarketDemandList.locations,
                embedded: true,
                monthTags: false,
                months: {
                  MarketDemandList.bestSellers: DateTime(2026, 11),
                  MarketDemandList.locations: DateTime(2026, 10),
                },
                onMonthChanged: (_, month) => moved.add(month),
                salesStream: Stream.value(const []),
                now: DateTime(2026, 11, 7),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MonthPickerPill), findsNothing);
      expect(find.textContaining('October 2026'), findsOneWidget);
    },
  );

  testWidgets('Best Sellers shows the quantity sold, no trend icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketDemandCards(
              month: DateTime(2026, 11),
              only: MarketDemandList.bestSellers,
              embedded: true,
              monthTags: false,
              salesStream: Stream.value([
                {
                  'productName': 'Corn',
                  'status': 'completed',
                  'unit': 'kg',
                  'quantity': 1,
                  'buyerArea': 'Laurel',
                  'pricingType': 'retail',
                  'completedAt': Timestamp.fromDate(DateTime(2026, 11, 3)),
                },
              ]),
              now: DateTime(2026, 11, 7),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 kg'), findsOneWidget);
    for (final icon in [
      Icons.fiber_new_outlined,
      Icons.trending_up_rounded,
      Icons.trending_flat_rounded,
      Icons.trending_down_rounded,
    ]) {
      expect(find.byIcon(icon), findsNothing);
    }
  });
}
