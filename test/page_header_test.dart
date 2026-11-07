// The main tabs' header is a plain rectangular bar: logo and name on the
// left, the notification bell and Settings gear on the right.
import 'package:agritrade/widgets/agritrade_text.dart';
import 'package:agritrade/widgets/notification_bell.dart';
import 'package:agritrade/widgets/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the band is dark green with a curved, gold-striped edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageHeader(
            title: 'Market',
            trailing: Icon(Icons.notifications),
          ),
        ),
      ),
    );

    final band = tester.widget<CustomPaint>(
      find.byKey(const Key('pageHeaderBand')),
    );
    final painter = band.painter! as HeaderWavePainter;
    expect(painter.green, PageHeader.background);
    expect(painter.gold, PageHeader.accent);
  });

  // The real bell, without the unread count it reads from Firebase.
  Widget shell({
    VoidCallback? onSettings,
    VoidCallback? onBell,
    int unread = 0,
  }) => MediaQuery(
    data: const MediaQueryData(size: Size(360, 640)),
    child: MaterialApp(
      home: Scaffold(
        body: HomeLogoAction(
          onTap: () {},
          onSettings: onSettings,
          child: PageHeader(
            title: 'Market',
            trailing: NotificationBellButton(
              onPressed: onBell ?? () {},
              unread: unread,
            ),
          ),
        ),
      ),
    ),
  );

  final bell = find.byIcon(Icons.notifications_none_rounded);
  final gear = find.byIcon(Icons.settings_outlined);

  void phoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the gear sits beside the bell, and the logo stays on the left', (
    tester,
  ) async {
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(
      tester.getTopLeft(find.byType(AgriTradeText)).dx,
      lessThan(tester.getTopLeft(bell).dx),
    );
    expect(tester.getTopLeft(bell).dx, lessThan(tester.getTopLeft(gear).dx));
  });

  testWidgets('bell and gear are 24px apart, 21px from the screen edge', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(tester.getTopLeft(gear).dx - tester.getTopRight(bell).dx, 24);
    expect(360 - tester.getTopRight(gear).dx, 21);
  });

  testWidgets('both icons are the same size, on the same line', (tester) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    expect(tester.getSize(bell), tester.getSize(gear));
    expect(tester.getCenter(bell).dy, tester.getCenter(gear).dy);
  });

  testWidgets('the band row stays 40 tall, with a full tap area on each', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}));

    // 40 for the row (as in the user's picture), then the wave and its
    // gold stripe under it.
    final band = find.byKey(const Key('pageHeaderBand'));
    expect(
      tester.getSize(band).height,
      PageHeader.bandHeight + PageHeader.waveDepth,
    );
    expect(PageHeader.bandHeight, 40);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(tester.getSize(find.byWidget(button)), const Size(48, 48));
    }
  });

  testWidgets('the unread badge stays on the bell, clear of the gear', (
    tester,
  ) async {
    phoneScreen(tester);
    await tester.pumpWidget(shell(onSettings: () {}, unread: 3));

    final badge = tester.getRect(find.byKey(const Key('notificationDot')));
    final icon = tester.getRect(bell);
    expect(badge.overlaps(icon), isTrue);
    expect(badge.top, lessThan(icon.top));
    expect(badge.right, greaterThan(icon.right));
    expect(badge.right, lessThan(tester.getRect(gear).left));
  });

  testWidgets('unread shows a gold dot (no count); none hides it', (
    tester,
  ) async {
    await tester.pumpWidget(shell(unread: 120));
    final dot = tester.widget<Container>(
      find.byKey(const Key('notificationDot')),
    );
    expect(
      (dot.decoration! as BoxDecoration).color,
      NotificationBellButton.dotColor,
    );
    expect(find.text('120'), findsNothing);

    await tester.pumpWidget(shell());
    expect(find.byKey(const Key('notificationDot')), findsNothing);
  });

  testWidgets('the band is dark green, the name white with a gold +', (
    tester,
  ) async {
    await tester.pumpWidget(shell());
    expect(PageHeader.onBandColor, Colors.white);
    final name = tester.widget<AgriTradeText>(find.byType(AgriTradeText));
    expect(name.light, isTrue);
    expect(name.plusColor, PageHeader.accent);
  });

  testWidgets('the bell and the gear each do their own job', (tester) async {
    phoneScreen(tester);
    var bellTaps = 0;
    var gearTaps = 0;
    await tester.pumpWidget(
      shell(onBell: () => bellTaps++, onSettings: () => gearTaps++),
    );

    await tester.tap(bell);
    expect((bellTaps, gearTaps), (1, 0));
    await tester.tap(find.byTooltip('Settings'));
    expect((bellTaps, gearTaps), (1, 1));
  });

  testWidgets('with no role shell around it there is no gear', (tester) async {
    await tester.pumpWidget(shell());
    expect(gear, findsNothing);
  });
}
