// A section that collapses to its heading (AgriTrade+ Insights on the
// Market tab): the chevron or the heading closes and opens it, and the
// month beside the heading shows only while it is open.
import 'package:agritrade/widgets/collapsible_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: CollapsibleSection(
          heading: Text('AgriTrade+ Insights'),
          trailing: Text('Nov 2026'),
          body: Text('Best Sellers list'),
        ),
      ),
    ),
  );

  testWidgets('open to begin with: heading, month and body', (tester) async {
    await show(tester);
    expect(find.text('AgriTrade+ Insights'), findsOneWidget);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Best Sellers list'), findsOneWidget);
  });

  testWidgets('the chevron collapses it to its heading, and opens it again', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('sectionToggle')));
    await tester.pumpAndSettle();
    expect(find.text('AgriTrade+ Insights'), findsOneWidget);
    expect(find.text('Best Sellers list'), findsNothing);
    expect(find.text('Nov 2026'), findsNothing);

    await tester.tap(find.byKey(const Key('sectionToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Best Sellers list'), findsOneWidget);
    expect(find.text('Nov 2026'), findsOneWidget);
  });

  testWidgets('tapping the heading does the same', (tester) async {
    await show(tester);
    await tester.tap(find.text('AgriTrade+ Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Best Sellers list'), findsNothing);
    await tester.tap(find.text('AgriTrade+ Insights'));
    await tester.pumpAndSettle();
    expect(find.text('Best Sellers list'), findsOneWidget);
  });
}
