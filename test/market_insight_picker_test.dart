import 'package:agritrade/screen/market_tab.dart';
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/market_card_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('the insight menu is sized to its option text', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: MarketInsightPicker(
              value: MarketInsight.marketAverage,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final picker = tester.widget<DropdownButton<MarketInsight>>(
      find.byType(DropdownButton<MarketInsight>),
    );
    // Narrower than the picker itself (the test font is wider than
    // Montserrat, so no fixed number).
    expect(
      picker.menuWidth,
      lessThan(
        tester.getSize(find.byType(DropdownButton<MarketInsight>)).width,
      ),
    );
    expect(picker.menuWidth, greaterThan(150));
    expect(find.text('Current Market Average'), findsOneWidget);
    expect(find.text('View AgriTrade+ insights'), findsNothing);
    expect(find.byIcon(Icons.insights_rounded), findsNothing);
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
    expect(find.text('Current Market Average'), findsOneWidget);
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
}
