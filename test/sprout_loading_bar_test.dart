// The splash screen's loading bar: it fills once while the app starts (then
// stays full), with a sprout at the end of the fill and "Loading AgriTrade+…"
// under it, no percentage; it stands still when the phone has animations
// turned off.
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:agritrade/widgets/branded_loading_screen.dart';
import 'package:agritrade/widgets/sprout_loading_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SproutLoadingBar.resetFill);

  testWidgets('fills once, then stays full', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SproutLoadingBar), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue); // still filling

    // Once full nothing moves any more — it does not start over.
    await tester.pump(SproutLoadingBar.fillTime);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('nothing to wait for when it never began', () async {
    await SproutLoadingBar.untilFilled().timeout(
      const Duration(milliseconds: 100),
    );
  });

  testWidgets('the splash can wait until the bar is full', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    var done = false;
    SproutLoadingBar.untilFilled().then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isFalse); // still filling

    await tester.pump(SproutLoadingBar.fillTime);
    expect(done, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'carries on from the web page\'s own loading bar, not from empty',
    (tester) async {
      // The Admin website's page showed its copy of the bar for 1.5 s while
      // Flutter downloaded: the rest of the three seconds is left.
      final pageStart = DateTime.now().subtract(
        const Duration(milliseconds: 1500),
      );
      SproutLoadingBar.earlierStart = () => pageStart;
      addTearDown(() => SproutLoadingBar.earlierStart = () => null);

      await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
      var done = false;
      SproutLoadingBar.untilFilled().then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, isTrue);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('after a slow page load the last stretch is still seen filling, '
      'not shown full at once', (tester) async {
    // A debug build on localhost: the page's bar waited 20 s for Flutter.
    final pageStart = DateTime.now().subtract(const Duration(seconds: 20));
    SproutLoadingBar.earlierStart = () => pageStart;
    addTearDown(() => SproutLoadingBar.earlierStart = () => null);

    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    var done = false;
    SproutLoadingBar.untilFilled().then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, isFalse);
    expect(tester.binding.hasScheduledFrame, isTrue); // still filling
    await tester.pump(SproutLoadingBar.minFinishTime);
    expect(done, isTrue);
    await tester.pumpAndSettle();
  });

  test('the web page\'s bar never fills on its own', () {
    double at(int ms) =>
        SproutLoadingBar.pageBarProgress(Duration(milliseconds: ms));
    expect(at(0), 0);
    expect(at(1000), allOf(greaterThan(0.3), lessThan(0.7)));
    expect(at(2100), closeTo(0.7, 1e-9));
    expect(at(7050), closeTo(0.8, 1e-9));
    expect(at(12000), 0.9);
    expect(at(600000), 0.9);
  });

  testWidgets('says it is loading, with no percentage', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Loading AgriTrade+…'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('the name and the loading line, with no tagline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AgriTradeText), findsOneWidget);
    expect(find.text('Smart Agricultural Trading, Made Simple.'), findsNothing);
    expect(find.text('Loading AgriTrade+…'), findsOneWidget);
    expect(find.textContaining('dashboard'), findsNothing);
    await tester.pumpAndSettle();
  });

  for (final size in [const Size(844, 390), const Size(1366, 480)]) {
    testWidgets('all of it shows on a short screen, $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      final screen = Offset.zero & size;
      for (final (name, finder) in [
        ('the name', find.byType(AgriTradeText)),
        ('the loading line', find.text('Loading AgriTrade+…')),
      ]) {
        final box = tester.getRect(finder);
        expect(screen.contains(box.topLeft), isTrue, reason: name);
        expect(screen.contains(box.bottomRight), isTrue, reason: name);
      }
      await tester.pumpAndSettle();
    });
  }

  testWidgets('stands still with animations off', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SproutLoadingBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
