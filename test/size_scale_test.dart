// One size scale for the mobile app (the user, 2026-11-08): every tab's
// title, every secondary screen's bar and Back come from AppTheme, so
// nothing grows from one screen to the next.
import 'package:agritrade/theme/app_theme.dart';
import 'package:agritrade/widgets/agri_app_bar.dart';
import 'package:agritrade/widgets/app_back_button.dart';
import 'package:agritrade/widgets/explore_hero.dart';
import 'package:agritrade/widgets/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('the scale itself', () {
    expect(AppTheme.mainTitleSize, inInclusiveRange(20, 22));
    expect(AppTheme.barTitleSize, inInclusiveRange(16, 18));
    expect(AppTheme.barIconSize, inInclusiveRange(18, 20));
    expect(AppTheme.actionHeight, 46);
    expect(AppTheme.actionLabelSize, 13);
    expect(AppTheme.compactActionHeight, inInclusiveRange(34, 40));
  });

  testWidgets('Explore and every other tab title are the same size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ExploreHero(title: 'Explore', subtitle: 'Discover.'),
              PageTitle(title: 'Market'),
            ],
          ),
        ),
      ),
    );
    double size(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;
    expect(size('Explore'), AppTheme.mainTitleSize);
    expect(size('Market'), AppTheme.mainTitleSize);
  });

  testWidgets('a secondary screen: 17 title, 20 Back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: SizedBox()),
        onGenerateRoute: (_) => null,
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: const AgriAppBar(title: 'Order Details'),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(AgriAppBar.titleStyle().fontSize, AppTheme.barTitleSize);
    final back = tester.widget<Icon>(
      find.descendant(
        of: find.byType(AppBackIcon),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    expect(back.size, AppTheme.barIconSize);
  });
}
