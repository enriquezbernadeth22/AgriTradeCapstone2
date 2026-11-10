// The Admin Dashboard's Market Intelligence helpers: the commodity search
// matching, and Top-Selling Products — real figures only, with an empty
// state where there are no completed sales. The price tracker has its own
// test (admin_price_tracker_test.dart).
import 'package:agritrade/screen/admin_analytics_widgets.dart';
import 'package:agritrade/screen/admin_dashboard_screen.dart'
    show AdminPalette, AdminThemeScope;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: AdminThemeScope(
        palette: AdminPalette.light,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    ),
  );
}

const commodities = ['Corn', 'Chicken', 'Coconut', 'Sweet Potato', 'Rice'];

void main() {
  test('commodity search suggests names by the letters typed', () {
    expect(matchCommodities(commodities, 'ch'), ['Chicken']);
    expect(matchCommodities(commodities, 'co'), ['Coconut', 'Corn']);
    expect(matchCommodities(commodities, 'CO'), ['Coconut', 'Corn']);
    // A later word counts too, after names that start with the letters.
    expect(matchCommodities(commodities, 'po'), ['Sweet Potato']);
    expect(matchCommodities(['Sweet Corn', 'Corn'], 'co'), [
      'Corn',
      'Sweet Corn',
    ]);
    expect(matchCommodities(commodities, 'zz'), isEmpty);
    expect(matchCommodities(commodities, ''), [
      'Chicken',
      'Coconut',
      'Corn',
      'Rice',
      'Sweet Potato',
    ]);
  });

  testWidgets(
    'Top-Selling Products lists rank, orders, quantity and sales value',
    (tester) async {
      await pump(
        tester,
        const AdminTopProductsCard(
          products: [
            (name: 'Red Onion', orders: 9, revenue: 2400, quantity: 25),
            (name: 'Yellow Corn', orders: 4, revenue: 2180, quantity: 75),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Red Onion'), findsOneWidget);
      expect(find.text('9 orders'), findsOneWidget);
      expect(find.text('25 kg sold · ₱2,400.00'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Red Onion')).dy,
        lessThan(tester.getTopLeft(find.text('Yellow Corn')).dy),
      );
    },
  );

  testWidgets('Top-Selling Products has an empty state', (tester) async {
    await pump(tester, const AdminTopProductsCard(products: []));
    expect(tester.takeException(), isNull);
    expect(find.text('No completed sales data available yet.'), findsOneWidget);
  });
}
