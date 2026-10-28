// The portal's loading bar: it fills as the wait goes on — quickly, then
// slower — and never reaches the end by itself; with animations off it
// stands still.
import 'package:agritrade/screen/admin_filter_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _shown(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;

void main() {
  testWidgets('fills quickly, then slower, and is never full while waiting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AdminLoadingBar())),
      ),
    );
    expect(_shown(tester), 0);

    await tester.pump(const Duration(seconds: 1));
    final oneSecond = _shown(tester);
    expect(oneSecond, closeTo(0.49, 0.05));

    await tester.pump(const Duration(seconds: 2));
    final threeSeconds = _shown(tester);
    expect(threeSeconds, closeTo(0.83, 0.05));
    // Slower in the second two seconds than in the first one.
    expect(threeSeconds - oneSecond, lessThan(oneSecond));

    await tester.pump(const Duration(seconds: 30));
    expect(_shown(tester), lessThan(1));
    expect(_shown(tester), greaterThan(threeSeconds));
  });

  testWidgets('stands still, half full, with animations off', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Center(child: AdminLoadingBar())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_shown(tester), 0.5);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
