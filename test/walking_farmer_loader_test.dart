// The splash screen's walking-farmer loader: one walk across while the app
// starts (then he stands at the end), and standing still when the phone
// has animations turned off.
import 'package:agritrade/widgets/branded_loading_screen.dart';
import 'package:agritrade/widgets/walking_farmer_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WalkingFarmerLoader.resetWalk);

  testWidgets('walks across once, then stands at the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WalkingFarmerLoader), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue); // still walking

    // After the one crossing nothing moves any more — he does not start
    // over.
    await tester.pump(WalkingFarmerLoader.crossing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('nothing to wait for when he never set off', () async {
    await WalkingFarmerLoader.untilWalkDone().timeout(
      const Duration(milliseconds: 100),
    );
  });

  testWidgets('the splash can wait until he reaches the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    var done = false;
    WalkingFarmerLoader.untilWalkDone().then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(done, isFalse); // still walking

    await tester.pump(WalkingFarmerLoader.crossing);
    expect(done, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('the percentage counts up from 0% to 100% at the handoff', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    final midway = int.parse(
      tester
          .widgetList<Text>(find.textContaining('%'))
          .single
          .data!
          .replaceAll('%', ''),
    );
    expect(midway, inExclusiveRange(0, 100));
    await tester.pump(WalkingFarmerLoader.crossing);
    expect(find.text('100%'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('the name, the tagline and the loading line', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedLoadingScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Smart Agricultural Trading, Made Simple.'),
      findsOneWidget,
    );
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
      for (final text in [
        'Smart Agricultural Trading, Made Simple.',
        'Loading AgriTrade+…',
      ]) {
        final box = tester.getRect(find.text(text));
        expect(screen.contains(box.topLeft), isTrue, reason: text);
        expect(screen.contains(box.bottomRight), isTrue, reason: text);
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
          child: Center(child: WalkingFarmerLoader()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
