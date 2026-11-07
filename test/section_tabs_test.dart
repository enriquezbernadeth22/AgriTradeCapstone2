// The bar of Product Details' sections: Back, then the four tabs, one
// font size for all of them on any phone, the active one on a dark green
// pill in white; the page's own row has no Back.
import 'package:agritrade/widgets/section_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  const labels = ['Overview', 'Description', 'Reviews', 'Recommended'];

  Future<List<int>> show(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTabs(
            labels: labels,
            active: 1,
            onTap: tapped.add,
            onBack: () {},
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('one font size for all four, on any phone', (tester) async {
    for (final width in [412.0, 360.0, 320.0]) {
      await show(tester, width);
      final sizes = {
        for (final label in labels)
          tester.widget<Text>(find.text(label)).style!.fontSize,
      };
      expect(sizes, hasLength(1), reason: 'at $width wide: $sizes');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the active one is marked; a tap reports which', (tester) async {
    final tapped = await show(tester, 400);
    final chosen = tester.widget<Text>(find.text('Description')).style!;
    expect(chosen.fontWeight, FontWeight.w600);
    expect(chosen.color, Colors.white);
    expect(
      tester.widget<Text>(find.text('Reviews')).style!.fontWeight,
      FontWeight.w500,
    );
    await tester.tap(find.text('Recommended'));
    expect(tapped, [3]);
    expect(find.byKey(const Key('sectionTabsBack')), findsOneWidget);
  });

  testWidgets('the row on the page itself has no Back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTabs(
            labels: labels,
            active: 0,
            onTap: (_) {},
            keyPrefix: 'inlineTab',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sectionTabsBack')), findsNothing);
    expect(find.byKey(const Key('inlineTab2')), findsOneWidget);
  });
}
